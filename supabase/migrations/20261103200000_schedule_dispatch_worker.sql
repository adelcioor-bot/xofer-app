create extension if not exists pg_cron;

create or replace function public.rpc_run_dispatch_worker_window()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_deadline timestamptz := clock_timestamp() + interval '50 seconds';
  v_result jsonb;
begin
  if not pg_try_advisory_lock(811, 34781) then
    return;
  end if;

  while clock_timestamp() < v_deadline loop
    begin
      perform public.rpc_expire_stale_attempts(100);
    exception
      when others then
        raise warning 'Dispatch worker expiration cycle failed: %', sqlerrm;
    end;

    while clock_timestamp() < v_deadline loop
      begin
        v_result := public.rpc_process_next_dispatch_attempt();
      exception
        when others then
          raise warning 'Dispatch worker processing cycle failed: %', sqlerrm;
          exit;
      end;

      exit when v_result is null;
    end loop;

    exit when clock_timestamp() >= v_deadline;
    perform pg_sleep(
      least(
        3::double precision,
        greatest(
          0::double precision,
          extract(epoch from (v_deadline - clock_timestamp()))
        )
      )
    );
  end loop;

  perform pg_advisory_unlock(811, 34781);
exception
  when others then
    perform pg_advisory_unlock(811, 34781);
    raise;
end;
$$;

revoke all on function public.rpc_run_dispatch_worker_window()
  from public, anon, authenticated, service_role;

do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid
    from cron.job
    where jobname = 'xofer-dispatch-worker'
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  perform cron.schedule(
    'xofer-dispatch-worker',
    '* * * * *',
    'select public.rpc_run_dispatch_worker_window();'
  );
end;
$$;
