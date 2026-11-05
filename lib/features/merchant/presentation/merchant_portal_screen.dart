import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/auth/domain/auth_repository.dart';
import 'package:xofer/features/merchant/data/cep_lookup_repository.dart';
import 'package:xofer/features/merchant/domain/merchant_auth_repository.dart';
import 'package:xofer/features/merchant/domain/cnpj.dart';
import 'package:xofer/features/merchant/domain/merchant_profile.dart';
import 'package:xofer/features/merchant/domain/merchant_repository.dart';
import 'package:xofer/features/merchant/presentation/merchant_login_screen.dart';

class MerchantPortalScreen extends StatelessWidget {
  const MerchantPortalScreen({
    super.key,
    required this.authRepository,
    required this.merchantAuthRepository,
    required this.merchantRepository,
    required this.onCreateDelivery,
    required this.onCreateRescue,
  });

  final AuthRepository authRepository;
  final MerchantAuthRepository merchantAuthRepository;
  final MerchantRepository merchantRepository;
  final VoidCallback onCreateDelivery;
  final VoidCallback onCreateRescue;

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? auth.currentSession;
        if (session == null || session.user.isAnonymous) {
          return MerchantLoginScreen(authRepository: merchantAuthRepository);
        }
        return _MerchantAccountGate(
          authRepository: authRepository,
          merchantAuthRepository: merchantAuthRepository,
          merchantRepository: merchantRepository,
          onCreateDelivery: onCreateDelivery,
          onCreateRescue: onCreateRescue,
        );
      },
    );
  }
}

class _MerchantAccountGate extends StatefulWidget {
  const _MerchantAccountGate({
    required this.authRepository,
    required this.merchantAuthRepository,
    required this.merchantRepository,
    required this.onCreateDelivery,
    required this.onCreateRescue,
  });

  final AuthRepository authRepository;
  final MerchantAuthRepository merchantAuthRepository;
  final MerchantRepository merchantRepository;
  final VoidCallback onCreateDelivery;
  final VoidCallback onCreateRescue;

  @override
  State<_MerchantAccountGate> createState() => _MerchantAccountGateState();
}

class _MerchantAccountGateState extends State<_MerchantAccountGate> {
  late Future<MerchantProfile?> _profileFuture;

  Future<void> _signOut() async {
    try {
      await widget.authRepository.signOut();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  void initState() {
    super.initState();
    _profileFuture = widget.merchantRepository.fetchCurrent();
  }

  void _reload() {
    setState(() {
      _profileFuture = widget.merchantRepository.fetchCurrent();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MerchantProfile?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return _MessageScaffold(
            message: snapshot.error.toString(),
            actionLabel: 'Tentar novamente',
            onAction: _reload,
          );
        }
        final profile = snapshot.data;
        if (profile == null) {
          return _MerchantRegistrationScreen(
            repository: widget.merchantRepository,
            authRepository: widget.authRepository,
            onRegistered: _reload,
          );
        }
        if (profile.status != 'active') {
          return _MessageScaffold(
            title: profile.businessName,
            message: 'O acesso deste estabelecimento está suspenso.',
            actionLabel: 'Sair',
            onAction: _signOut,
          );
        }
        return _MerchantDashboardScreen(
          profile: profile,
          repository: widget.merchantRepository,
          authRepository: widget.authRepository,
          onCreateDelivery: widget.onCreateDelivery,
          onCreateRescue: widget.onCreateRescue,
        );
      },
    );
  }
}

class _MerchantRegistrationScreen extends StatefulWidget {
  const _MerchantRegistrationScreen({
    required this.repository,
    required this.authRepository,
    required this.onRegistered,
  });

  final MerchantRepository repository;
  final AuthRepository authRepository;
  final VoidCallback onRegistered;

  @override
  State<_MerchantRegistrationScreen> createState() =>
      _MerchantRegistrationScreenState();
}

class _MerchantRegistrationScreenState
    extends State<_MerchantRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessName = TextEditingController();
  final _legalName = TextEditingController();
  final _document = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _postalCode = TextEditingController();
  final _street = TextEditingController();
  final _buildingNumber = TextEditingController();
  final _district = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _socialLinks = TextEditingController();
  final _email = TextEditingController();
  final _cepLookup = CepLookupRepository();
  final _weekDays = const [
    'segunda',
    'terca',
    'quarta',
    'quinta',
    'sexta',
    'sabado',
    'domingo',
  ];
  final _selectedDays = <String>{};
  String? _openingTime;
  String? _closingTime;
  String? _resolvedCep;
  bool _lookingUpCep = false;
  bool _saving = false;
  String? _error;
  String? _cepError;

  List<String> get _hourOptions =>
      List.generate(24, (hour) => '${hour.toString().padLeft(2, '0')}:00');

  Future<void> _signOut() async {
    try {
      await widget.authRepository.signOut();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    _phone.text = user?.phone ?? '';
    _email.text = user?.email ?? '';
    final metadata = user?.userMetadata ?? const {};
    final signupBusinessName = metadata['merchant_business_name'];
    if (signupBusinessName is String) {
      _businessName.text = signupBusinessName;
      _legalName.text = signupBusinessName;
    }
    final signupLegalName = metadata['merchant_legal_name'];
    if (signupLegalName is String) _legalName.text = signupLegalName;
    final signupDocument = metadata['merchant_document'];
    if (signupDocument is String &&
        signupDocument.replaceAll(RegExp(r'\D'), '').length == 14) {
      _document.text = signupDocument.replaceAll(RegExp(r'\D'), '');
    }
    final signupPhone = metadata['merchant_phone'];
    if (signupPhone is String) _phone.text = signupPhone;
    final postalCode = metadata['merchant_postal_code'];
    if (postalCode is String) _postalCode.text = postalCode;
    final street = metadata['merchant_street'];
    if (street is String) _street.text = street;
    if (postalCode is String && street is String && street.isNotEmpty) {
      _resolvedCep = Cnpj.digitsOnly(postalCode);
    }
    final buildingNumber = metadata['merchant_building_number'];
    if (buildingNumber is String) _buildingNumber.text = buildingNumber;
    final district = metadata['merchant_district'];
    if (district is String) _district.text = district;
    final city = metadata['merchant_city'];
    if (city is String) _city.text = city;
    final state = metadata['merchant_state'];
    if (state is String) _state.text = state;
    final openingTime = metadata['merchant_opening_time'];
    if (openingTime is String) _openingTime = openingTime;
    final closingTime = metadata['merchant_closing_time'];
    if (closingTime is String) _closingTime = closingTime;
    final operatingDays = metadata['merchant_operating_days'];
    if (operatingDays is List) {
      _selectedDays.addAll(operatingDays.whereType<String>());
    }
    final socialLinks = metadata['merchant_social_links'];
    if (socialLinks is String) _socialLinks.text = socialLinks;
  }

  @override
  void dispose() {
    _businessName.dispose();
    _legalName.dispose();
    _document.dispose();
    _phone.dispose();
    _address.dispose();
    _postalCode.dispose();
    _street.dispose();
    _buildingNumber.dispose();
    _district.dispose();
    _city.dispose();
    _state.dispose();
    _socialLinks.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _lookupPostalCode() async {
    if (_lookingUpCep) return;
    setState(() {
      _lookingUpCep = true;
      _cepError = null;
    });
    try {
      final result = await _cepLookup.lookup(_postalCode.text);
      if (!mounted) return;
      setState(() {
        _postalCode.text = result.cep;
        _resolvedCep = result.cep;
        _street.text = result.street;
        _district.text = result.district;
        _city.text = result.city;
        _state.text = result.state;
      });
    } on CepLookupFailure catch (error) {
      if (mounted) setState(() => _cepError = error.message);
    } finally {
      if (mounted) setState(() => _lookingUpCep = false);
    }
  }

  void _onPostalCodeChanged(String value) {
    final digits = Cnpj.digitsOnly(value);
    if (_resolvedCep == null || digits == _resolvedCep) return;
    setState(() {
      _resolvedCep = null;
      _street.clear();
      _district.clear();
      _city.clear();
      _state.clear();
      _cepError = null;
    });
  }

  String get _fullAddress => [
    '${_street.text.trim()}, ${_buildingNumber.text.trim()}',
    _district.text.trim(),
    '${_city.text.trim()} - ${_state.text.trim().toUpperCase()}',
    'CEP ${_postalCode.text.replaceAll(RegExp(r'\D'), '')}',
    if (_address.text.trim().isNotEmpty) _address.text.trim(),
  ].join(', ');

  Future<void> _submit() async {
    if (_saving || _lookingUpCep) return;
    if ((_openingTime == null) != (_closingTime == null)) {
      setState(
        () => _error = 'Informe os horários de abertura e fechamento ou deixe ambos vazios.',
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.register(
        businessName: _businessName.text,
        document: _document.text,
        phone: _phone.text,
        address: _fullAddress,
        legalName: _legalName.text,
        postalCode: _postalCode.text,
        street: _street.text,
        buildingNumber: _buildingNumber.text,
        district: _district.text,
        city: _city.text,
        state: _state.text,
        openingTime: _openingTime,
        closingTime: _closingTime,
        operatingDays: _weekDays
            .where(_selectedDays.contains)
            .toList(growable: false),
        socialLinks: _socialLinks.text,
      );
      if (mounted) widget.onRegistered();
    } on MerchantFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadastro do estabelecimento'),
        actions: [
          IconButton(
            tooltip: 'Sair',
            onPressed: _signOut,
            icon: const Icon(Icons.logout, color: AppTheme.amber),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Icon(
                    Icons.storefront_outlined,
                    color: AppTheme.amber,
                    size: 44,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Dados do estabelecimento',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('merchant_business_name'),
                    controller: _businessName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nome Fantasia',
                    ),
                    validator: (value) => (value ?? '').trim().length < 3
                        ? 'Informe o nome fantasia.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('merchant_legal_name'),
                    controller: _legalName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Razão Social',
                    ),
                    validator: (value) => (value ?? '').trim().length < 3
                        ? 'Informe a razão social.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('merchant_cnpj'),
                    controller: _document,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(14),
                    ],
                    decoration: const InputDecoration(labelText: 'CNPJ'),
                    validator: (value) => Cnpj.isValid(value ?? '')
                        ? null
                        : 'Informe um CNPJ válido.',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('merchant_email'),
                    controller: _email,
                    readOnly: true,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-mail de acesso',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('merchant_phone'),
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Telefone do estabelecimento',
                    ),
                    validator: (value) => (value ?? '').trim().length < 8
                        ? 'Informe um telefone válido.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('merchant_postal_code'),
                    controller: _postalCode,
                    keyboardType: TextInputType.number,
                    onChanged: _onPostalCodeChanged,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    decoration: InputDecoration(
                      labelText: 'CEP',
                      errorText: _cepError,
                      suffixIcon: _lookingUpCep
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              tooltip: 'Buscar CEP',
                              onPressed: _saving ? null : _lookupPostalCode,
                              icon: const Icon(Icons.search),
                            ),
                    ),
                    validator: (value) =>
                        (value ?? '').replaceAll(RegExp(r'\D'), '').length == 8
                        ? null
                        : 'Informe um CEP válido.',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('merchant_street'),
                    controller: _street,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'Logradouro'),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Busque o endereço pelo CEP.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('merchant_building_number'),
                    controller: _buildingNumber,
                    decoration: const InputDecoration(
                      labelText: 'Número da edificação',
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Informe o número da edificação.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('merchant_district'),
                    controller: _district,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'Bairro'),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Busque o endereço pelo CEP.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          key: const Key('merchant_city'),
                          controller: _city,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Cidade',
                          ),
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'Busque o endereço pelo CEP.'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          key: const Key('merchant_state'),
                          controller: _state,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Estado',
                          ),
                          validator: (value) => (value ?? '').trim().length != 2
                              ? 'Estado inválido.'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('merchant_address'),
                    controller: _address,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Complemento / referência',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Informações opcionais',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: const Key('merchant_opening_time'),
                          initialValue: _openingTime,
                          decoration: const InputDecoration(
                            labelText: 'Hora de abertura',
                          ),
                          items: [
                            for (final hour in _hourOptions)
                              DropdownMenuItem(value: hour, child: Text(hour)),
                          ],
                          onChanged: _saving
                              ? null
                              : (value) => setState(() => _openingTime = value),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: const Key('merchant_closing_time'),
                          initialValue: _closingTime,
                          decoration: const InputDecoration(
                            labelText: 'Hora de fechamento',
                          ),
                          items: [
                            for (final hour in _hourOptions)
                              DropdownMenuItem(value: hour, child: Text(hour)),
                          ],
                          onChanged: _saving
                              ? null
                              : (value) => setState(() => _closingTime = value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Dias de funcionamento'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (var index = 0; index < _weekDays.length; index++)
                        FilterChip(
                          key: Key('merchant_operating_day_$index'),
                          label: Text(_dayLabels[index]),
                          selected: _selectedDays.contains(_weekDays[index]),
                          onSelected: _saving
                              ? null
                              : (selected) => setState(() {
                                  if (selected) {
                                    _selectedDays.add(_weekDays[index]);
                                  } else {
                                    _selectedDays.remove(_weekDays[index]);
                                  }
                                }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('merchant_social_links'),
                    controller: _socialLinks,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Redes sociais',
                      hintText: 'Links de Instagram, Facebook etc.',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      key: const Key('merchant_registration_error'),
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    key: const Key('merchant_register_button'),
                    onPressed: _saving || _lookingUpCep ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Text('Cadastrar estabelecimento'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MerchantDashboardScreen extends StatefulWidget {
  const _MerchantDashboardScreen({
    required this.profile,
    required this.repository,
    required this.authRepository,
    required this.onCreateDelivery,
    required this.onCreateRescue,
  });

  final MerchantProfile profile;
  final MerchantRepository repository;
  final AuthRepository authRepository;
  final VoidCallback onCreateDelivery;
  final VoidCallback onCreateRescue;

  @override
  State<_MerchantDashboardScreen> createState() =>
      _MerchantDashboardScreenState();
}

class _MerchantDashboardScreenState extends State<_MerchantDashboardScreen> {
  late final Stream<List<MerchantRide>> _rides = widget.repository.watchRides();

  Future<void> _signOut() async {
    try {
      await widget.authRepository.signOut();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _statusLabel(String status) {
    return switch (status) {
      'buscando_prestadores' => 'Buscando motorista',
      'procurando_motoboy' => 'Buscando motoboy',
      'motoboy_a_caminho' => 'Parceiro a caminho',
      'a_caminho_do_cliente' => 'Em deslocamento',
      'aguardando_validacao_embarque' => 'Aguardando confirmação',
      'conduzindo_destino' => 'A caminho do destino',
      'em_andamento' => 'Em andamento',
      'motorista_chegou' || 'motorista_entregue' => 'Motorista chegou',
      'concluida' => 'Concluído',
      'cancelada' => 'Cancelado',
      _ => status,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel do estabelecimento'),
        actions: [
          IconButton(
            key: const Key('merchant_sign_out'),
            tooltip: 'Sair',
            onPressed: _signOut,
            icon: const Icon(Icons.logout, color: AppTheme.amber),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<List<MerchantRide>>(
          stream: _rides,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Não foi possível atualizar os chamados: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final rides = snapshot.data!;
            final active = rides
                .where(
                  (ride) => ride.status != 'concluida' && !ride.isTerminalError,
                )
                .toList();
            final history = rides
                .where(
                  (ride) => ride.status == 'concluida' || ride.isTerminalError,
                )
                .toList();
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  widget.profile.businessName,
                  key: const Key('merchant_dashboard_name'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppTheme.amber,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Chamados ativos, histórico e status em tempo real',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  key: const Key('merchant_new_delivery'),
                  onPressed: widget.onCreateDelivery,
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Solicitar entrega com motoboy'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('merchant_new_rescue'),
                  onPressed: widget.onCreateRescue,
                  icon: const Icon(Icons.car_crash_outlined),
                  label: const Text('Solicitar Xofer'),
                ),
                const SizedBox(height: 24),
                Text(
                  'Chamados ativos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (active.isEmpty)
                  const _EmptySection(
                    message: 'Nenhum chamado ativo no momento.',
                  )
                else
                  for (final ride in active)
                    _RideCard(
                      ride: ride,
                      statusLabel: _statusLabel(ride.status),
                    ),
                const SizedBox(height: 20),
                Text(
                  'Histórico de pedidos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (history.isEmpty)
                  const _EmptySection(
                    message: 'Os pedidos concluídos aparecerão aqui.',
                  )
                else
                  for (final ride in history)
                    _RideCard(
                      ride: ride,
                      statusLabel: _statusLabel(ride.status),
                    ),
                const SizedBox(height: 16),
                const Text(
                  'Pagamentos digitais e carteira do estabelecimento ainda '
                  'não estão habilitados. Esta versão não realiza cobranças.',
                  key: Key('merchant_payment_notice'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RideCard extends StatelessWidget {
  const _RideCard({required this.ride, required this.statusLabel});

  final MerchantRide ride;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    final statusColor = ride.isTerminalError
        ? Colors.redAccent
        : switch (ride.status) {
            'concluida' => Colors.greenAccent,
            'motoboy_a_caminho' || 'a_caminho_do_cliente' => Colors.deepOrange,
            'aguardando_validacao_embarque' ||
            'motorista_chegou' ||
            'motorista_entregue' ||
            'em_andamento' ||
            'conduzindo_destino' => Colors.green,
            _ => AppTheme.amber,
          };
    final arrivalLabel = switch (ride.status) {
      'aguardando_validacao_embarque' ||
      'motorista_chegou' => 'Motorista chegou ao local',
      'motoboy_a_caminho' || 'a_caminho_do_cliente' =>
        ride.etaMinutes == null
            ? 'Motorista a caminho'
            : 'Previsão: ${ride.etaMinutes} min',
      _ => 'Aguardando atualização',
    };
    return AnimatedContainer(
      key: ValueKey('merchant_ride_card_${ride.id}'),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.graphiteSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statusColor.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        leading: Icon(
          ride.serviceType == 'delivery'
              ? Icons.local_shipping_outlined
              : Icons.car_crash_outlined,
          color: statusColor,
        ),
        title: Text(
          ride.customerName?.isNotEmpty == true
              ? ride.customerName!
              : ride.serviceType == 'delivery'
              ? 'Entrega'
              : 'Resgate',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ride.customerPhone?.isNotEmpty == true)
              Text(ride.customerPhone!),
            Text(
              '${ride.origin} → ${ride.destination}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(ride.driverDescription),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                statusLabel,
                key: ValueKey('${ride.id}_${ride.status}'),
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              arrivalLabel,
              style: TextStyle(color: statusColor.withValues(alpha: 0.9)),
            ),
            const SizedBox(height: 8),
            _MerchantRideStages(ride: ride, activeColor: statusColor),
          ],
        ),
        isThreeLine: true,
        trailing: Icon(
          ride.status == 'concluida'
              ? Icons.check_circle_outline
              : ride.status == 'cancelada'
              ? Icons.cancel_outlined
              : Icons.sync,
          color: statusColor,
        ),
      ),
    );
  }
}

class _MerchantRideStages extends StatelessWidget {
  const _MerchantRideStages({required this.ride, required this.activeColor});

  final MerchantRide ride;
  final Color activeColor;

  static const _deliveryStages = [
    ('procurando_motoboy', 'Busca'),
    ('motoboy_a_caminho', 'Aceito'),
    ('a_caminho_do_cliente', 'Coleta'),
    ('conduzindo_destino', 'Entrega'),
    ('concluida', 'Concluído'),
  ];

  static const _rescueStages = [
    ('buscando_prestadores', 'Motorista'),
    ('procurando_motoboy', 'Motoboy'),
    ('motoboy_a_caminho', 'Resgate'),
    ('a_caminho_do_cliente', 'Embarque'),
    ('aguardando_validacao_embarque', 'Validação'),
    ('conduzindo_destino', 'Destino'),
    ('em_andamento', 'Corrida'),
    ('concluida', 'Concluído'),
  ];

  @override
  Widget build(BuildContext context) {
    final stages = ride.serviceType == 'delivery'
        ? _deliveryStages
        : _rescueStages;
    final currentIndex = stages.indexWhere(
      (stage) =>
          stage.$1 == ride.status ||
          (ride.status == 'motorista_chegou' &&
              stage.$1 == 'aguardando_validacao_embarque') ||
          (ride.status == 'motorista_entregue' &&
              stage.$1 == 'conduzindo_destino'),
    );
    return Wrap(
      key: Key('merchant_ride_stages_${ride.id}'),
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var index = 0; index < stages.length; index++)
          _MerchantRideStage(
            key: ValueKey('${ride.id}_stage_$index'),
            label: stages[index].$2,
            active: !ride.isTerminalError && index == currentIndex,
            complete:
                !ride.isTerminalError &&
                (index < currentIndex ||
                    (ride.status == 'concluida' && index < stages.length - 1)),
            color: activeColor,
          ),
      ],
    );
  }
}

class _MerchantRideStage extends StatelessWidget {
  const _MerchantRideStage({
    super.key,
    required this.label,
    required this.active,
    required this.complete,
    required this.color,
  });

  final String label;
  final bool active;
  final bool complete;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final stageColor = complete
        ? Colors.greenAccent
        : active
        ? color
        : Colors.white38;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: stageColor.withValues(alpha: active || complete ? 0.16 : 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: stageColor.withValues(alpha: active || complete ? 0.8 : 0.2),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: stageColor,
          fontSize: 11,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(message, style: const TextStyle(color: Colors.white70)),
    );
  }
}

const _dayLabels = [
  'Segunda',
  'Terça',
  'Quarta',
  'Quinta',
  'Sexta',
  'Sábado',
  'Domingo',
];

class _MessageScaffold extends StatelessWidget {
  const _MessageScaffold({
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.title,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title ?? 'Estabelecimento')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}
