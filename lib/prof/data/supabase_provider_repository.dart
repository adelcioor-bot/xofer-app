import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xofer/prof/domain/partner_role.dart';
import 'package:xofer/prof/domain/provider_account.dart';
import 'package:xofer/prof/domain/provider_failure.dart';
import 'package:xofer/prof/domain/provider_repository.dart';

class SupabaseProviderRepository implements ProviderRepository {
  SupabaseProviderRepository({this.client});

  final SupabaseClient? client;
  static const bucket = 'provider-documents';

  SupabaseClient get _supabase => client ?? Supabase.instance.client;

  String get _userId {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) {
      throw const ProviderFailure('Sessão expirada. Entre novamente.');
    }
    return id;
  }

  @override
  Future<ProviderAccount?> findCurrent(PartnerRole role) async {
    final userId = _userId;
    try {
      final data = await _supabase
          .from('providers')
          .select()
          .eq('id', userId)
          .eq('role', role.wire)
          .maybeSingle();
      if (data == null) return null;
      return _accountFromMap(data);
    } on ProviderFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _fromPostgrest(error);
    } catch (_) {
      throw const ProviderFailure(
        'Não foi possível consultar o cadastro de parceiro.',
      );
    }
  }

  @override
  Future<ProviderAccount> saveApplication(ProviderApplication application) async {
    final userId = _userId;
    try {
      final cnhPath = await _upload(userId, application.role, 'cnh', application.cnh);
      final criminalPath = await _upload(
        userId,
        application.role,
        'antecedentes',
        application.criminalRecord,
      );
      final selfiePath = await _upload(
        userId,
        application.role,
        'selfie',
        application.selfie,
      );
      final crlvPath = application.crlv == null
          ? null
          : await _upload(userId, application.role, 'crlv', application.crlv!);

      final row = {
        'id': userId,
        'role': application.role.wire,
        'full_name': application.fullName.trim(),
        'document': application.document,
        'phone': application.phone,
        'email': application.email.trim(),
        'status_sistema': ProviderStatus.analise.wire,
        'cnh_path': cnhPath,
        'criminal_record_path': criminalPath,
        'crlv_path': crlvPath,
        'selfie_path': selfiePath,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final data = await _supabase
          .from('providers')
          .upsert(row, onConflict: 'id,role')
          .select()
          .single();
      return _accountFromMap(data);
    } on ProviderFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _fromPostgrest(error);
    } on StorageException catch (error) {
      throw ProviderFailure(error.message);
    } catch (_) {
      throw const ProviderFailure(
        'Não foi possível enviar o cadastro para análise.',
      );
    }
  }

  @override
  Future<ProviderAccount> ensureActiveTestPartner({
    required PartnerRole role,
    required String phone,
  }) async {
    final userId = _userId;
    final account = ProviderAccount(
      id: userId,
      role: role,
      fullName: 'Teste Xofer',
      document: '123456789',
      phone: phone,
      email: 'teste@xofer.app',
      status: ProviderStatus.ativo,
    );
    try {
      final data = await _supabase
          .from('providers')
          .upsert({
            'id': userId,
            'role': role.wire,
            'full_name': account.fullName,
            'document': account.document,
            'phone': phone,
            'email': account.email,
            'status_sistema': ProviderStatus.ativo.wire,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'id,role')
          .select()
          .single();
      return _accountFromMap(data);
    } on PostgrestException catch (error) {
      final failure = _fromPostgrest(error);
      if (failure.isDuplicateKey || failure.isMissingTable) return account;
      throw failure;
    } catch (_) {
      throw const ProviderFailure(
        'Não foi possível validar o motorista de teste.',
      );
    }
  }

  Future<String> _upload(
    String userId,
    PartnerRole role,
    String slot,
    CapturedDocument document,
  ) async {
    final path = '$userId/${role.wire}/$slot.jpg';
    await _supabase.storage.from(bucket).uploadBinary(
      path,
      Uint8List.fromList(document.bytes),
      fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
    );
    return path;
  }

  ProviderFailure _fromPostgrest(PostgrestException error) {
    final failure = ProviderFailure(error.message);
    if (failure.isMissingTable) {
      return const ProviderFailure(ProviderFailure.missingTableMessage);
    }
    return failure;
  }

  ProviderAccount _accountFromMap(Map<String, dynamic> map) {
    final roleWire = map['role'] as String? ?? '';
    return ProviderAccount(
      id: map['id'] as String,
      role: roleWire == PartnerRole.courier.wire
          ? PartnerRole.courier
          : PartnerRole.driver,
      fullName: map['full_name'] as String? ?? '',
      document: map['document'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String? ?? '',
      status: providerStatusFromWire(map['status_sistema'] as String? ?? ''),
    );
  }
}
