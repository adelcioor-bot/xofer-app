class CorridaFailure implements Exception {
  const CorridaFailure(this.message);

  static const missingTableMessage =
      'A tabela de corridas ainda não existe no Supabase. '
      'Aplique a migração corridas para sincronizar as fases.';

  static const syncMessage = 'Não foi possível sincronizar a fase da corrida.';

  final String message;

  bool get isDuplicateKey {
    final normalized = message.toLowerCase();
    return normalized.contains('duplicate key') ||
        normalized.contains('unique constraint') ||
        normalized.contains('23505');
  }

  bool get isMissingTable {
    final normalized = message.toLowerCase();
    return normalized.contains('pgrst205') ||
        normalized.contains('could not find the table') ||
        (normalized.contains('schema cache') && normalized.contains('table'));
  }

  bool get isMissingColumn {
    final normalized = message.toLowerCase();
    return normalized.contains('pgrst204') ||
        (normalized.contains('column') &&
            normalized.contains('does not exist'));
  }

  String? get missingColumn {
    final schemaCache = RegExp(
      r"could not find the '([^']+)' column",
      caseSensitive: false,
    ).firstMatch(message);
    if (schemaCache != null) return schemaCache.group(1);
    final postgres = RegExp(
      r'column "([^"]+)"',
      caseSensitive: false,
    ).firstMatch(message);
    return postgres?.group(1);
  }

  String? get invalidEnumValue {
    final match = RegExp(
      r'invalid input value for enum [^:]+: "([^"]+)"',
      caseSensitive: false,
    ).firstMatch(message);
    return match?.group(1);
  }

  factory CorridaFailure.fromRemote({
    String? code,
    required String message,
    Object? details,
    String? hint,
  }) {
    final detected = CorridaFailure('${code ?? ''} $message');
    if (detected.isMissingTable) {
      return const CorridaFailure(missingTableMessage);
    }
    if (detected.isDuplicateKey) {
      return const CorridaFailure('Essa corrida já está em andamento.');
    }
    final column = detected.missingColumn;
    if (detected.isMissingColumn && column != null) {
      return CorridaFailure(
        'Falta a coluna $column na tabela corridas. '
        'Rode as migrações SQL mais recentes no Supabase.',
      );
    }
    final enumValue = detected.invalidEnumValue;
    if (enumValue != null) {
      return CorridaFailure(
        'O Supabase recusou o status $enumValue. '
        'Rode no SQL editor as migrações que atualizam status_corrida.',
      );
    }
    final normalized = message.toLowerCase();
    if ((code ?? '').toUpperCase() == 'PGRST116' ||
        normalized.contains('0 rows')) {
      return const CorridaFailure(
        'A corrida não pôde ser lida. Confira a permissão de leitura da tabela corridas.',
      );
    }
    if (normalized.contains('row-level security') ||
        normalized.contains('permission denied') ||
        (code ?? '') == '42501') {
      return const CorridaFailure(
        'Sem permissão para gravar a corrida. Entre novamente.',
      );
    }
    if (normalized.contains('violates foreign key') ||
        (code ?? '') == '23503') {
      return const CorridaFailure(
        'Não foi possível vincular o usuário a esta corrida. Entre novamente.',
      );
    }
    final explanation = [
      message,
      if (details != null && details.toString().trim().isNotEmpty)
        details.toString(),
      if (hint?.trim().isNotEmpty == true) hint!,
    ].join(' | ');
    return CorridaFailure(
      'Erro do Supabase${code == null ? '' : ' ($code)'}: $explanation',
    );
  }

  @override
  String toString() => message;
}
