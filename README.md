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

## Portal do estabelecimento

O portal merchant é um app Flutter independente, com entrypoint
`lib/merchant/main.dart`, separado dos apps do cliente e dos parceiros. Para
executá-lo localmente no servidor web:

```powershell
C:\src\flutter\bin\flutter.bat run -d web-server --web-hostname=localhost --web-port=3004 lib/merchant/main.dart
```

Qualquer host loopback (`localhost`, `127.0.0.1` ou `::1`) usa o Supabase
local, inclusive em build release. Hosts não locais usam o Supabase remoto.
Para desenvolvimento local, aplique as migrations e execute a Edge Function
merchant no ambiente local antes de usar login por CNPJ:

```powershell
supabase start
supabase migration up --local
supabase functions serve merchant-cnpj-login --no-verify-jwt
```

Crie as contas de teste localmente: usuários e sessões do Supabase local não
são compartilhados com o projeto remoto.

O login do merchant é independente dos demais papéis: aceita e-mail ou CNPJ
com senha. O CNPJ é resolvido no backend para o e-mail vinculado ao perfil,
sem retornar esse endereço ao cliente. Novos estabelecimentos criam uma conta
com e-mail e senha, confirmam o e-mail quando exigido pelo Supabase Auth e
preenchem o perfil completo: razão social, nome fantasia, CNPJ, telefone,
endereço estruturado por CEP (com consulta ViaCEP), horários, dias de
funcionamento e redes sociais. Recuperação de senha é enviada por e-mail.
Cadastro e solicitações são autorizados no backend pelo `auth.uid()` e pelas
políticas RLS.

A migration `20261104120000_merchant_email_password_auth.sql` adiciona o e-mail
do perfil e preenche perfis existentes a partir da conta Supabase.
A migration `20261104130000_merchant_cnpj_login_identifiers.sql` registra o
CNPJ informado na criação da conta e vincula o perfil completo ao mesmo
identificador. Contas já criadas sem CNPJ devem entrar primeiro pelo e-mail e
concluir o cadastro do estabelecimento; depois disso, o CNPJ também funciona.
A migration `20261104140000_merchant_registration_details.sql` adiciona os
campos de endereço estruturado e funcionamento e atualiza o RPC de cadastro.
A Edge
Function `merchant-cnpj-login` deve ser publicada sem validação JWT de entrada,
pois é chamada antes da autenticação e valida a senha via Supabase Auth:

```powershell
supabase functions deploy merchant-cnpj-login --no-verify-jwt
```

Ela usa `SUPABASE_SERVICE_ROLE_KEY` somente no servidor para consultar o vínculo
CNPJ/e-mail; a resposta ao cliente contém apenas os tokens da sessão autenticada.

O painel recebe `corridas` do próprio estabelecimento por Supabase Realtime e
separa chamados ativos do histórico. Entregas criam um despacho direto para
motoboys; resgates usam o fluxo de motorista seguido pelo motoboy. Ambos
solicitam preço ao `rpc_generate_ride_quote` com `requester_type = 'merchant'`
e criam a corrida e o despacho atomicamente por
`rpc_create_merchant_ride_dispatch`. A origem da rota é a localização atual do
dispositivo; o destino é selecionado no mapa. Ao confirmar um chamado, a tela
de confirmação retorna imediatamente ao painel, onde os cards ativos continuam
acompanhando as transições de status em tempo real e permitem solicitar outro
serviço sem esperar a conclusão do chamado atual.

A migration `20261104090000_merchant_portal_and_dispatch.sql` adiciona o perfil,
as regras de acesso e a criação dos chamados. Pagamentos digitais e carteira
merchant ainda não estão integrados: os chamados ficam com
`payment_status = 'not_configured'` e esta versão não realiza cobranças.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
