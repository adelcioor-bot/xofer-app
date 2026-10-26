# xofer

A new Flutter project.

## Sessões e roteamento

`AppBootstrap` inicializa o Supabase antes de montar os apps e mantém
`persistSession` ativo pelo armazenamento padrão do `supabase_flutter`. Na
abertura, o Xofer restaura a sessão e segue para o mapa ou para o cadastro de
perfil caso esteja incompleto. O Xofer Prof restaura a sessão, procura o papel
de parceiro e abre o fluxo correspondente; sem sessão, inicia pela seleção do
papel e autenticação por SMS/OTP. Sair encerra a sessão local do Supabase e
encerra a sessão autenticada.

## Telefone de teste

Os números `4141994141` (passageiro), `4141004141` (motorista) e
`4141014141` (motoboy) usam o mesmo fluxo real de SMS/OTP do Supabase Auth que os
demais números. Configure-os como usuários de telefone no Supabase Auth e
habilite o envio de SMS/OTP para que cada sessão tenha seu próprio `auth.uid()`.

O perfil de passageiro de teste é preenchido em `profiles` usando o ID da sessão
autenticada. No Xofer Prof, os usuários de motorista e motoboy são vinculados a
`providers` com o mesmo ID autenticado; as chamadas e aceites também usam esse ID
e são protegidos pelo RLS.

## Corridas reais

O cliente cria a linha em `corridas` com status `buscando_prestadores` e sem
motorista atribuído. O radar recebe somente linhas disponíveis pela consulta
inicial e pelo Supabase Realtime. Quando o motorista aceita, o status passa a
`procurando_motoboy`, sem preencher `motoboy_id`; o radar do motoboy mostra
somente essas corridas. A oferta do motoboy é uma etapa independente, calculada
entre a posição atual dele e a posição registrada do motorista; o card mostra
a distância e o ganho estimado desse resgate, sem misturar os dados de tarifa
da corrida original. O aceite do resgate grava o `auth.uid()` em `motoboy_id`
e muda o status para `motoboy_a_caminho`. A tela ativa do motorista mantém a
busca visível e só mostra o motoboy e sua posição sincronizada quando esse ID
estiver preenchido. Aplique as migrações de `supabase/migrations` em ordem,
incluindo `20261024155000_busca_corridas_status.sql` e
`20261024160000_busca_corridas.sql`, para habilitar os status, o vínculo com o
solicitante e as políticas RLS.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
