-- Validação de embarque. Os valores novos do enum só podem ser gravados
-- numa execução seguinte a esta.

alter type public.status_corrida_enum add value if not exists 'aguardando_validacao_embarque';
alter type public.status_corrida_enum add value if not exists 'em_andamento';

alter table public.corridas add column if not exists token_validacao text;
