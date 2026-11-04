do $$
begin
  create type public.status_corrida_enum as enum (
    'buscando_prestadores',
    'procurando_motoboy',
    'motoboy_a_caminho',
    'a_caminho_do_cliente',
    'aguardando_validacao_embarque',
    'em_andamento',
    'conduzindo_destino',
    'concluida',
    'cancelada'
  );
exception
  when duplicate_object then
    null;
end
$$;
