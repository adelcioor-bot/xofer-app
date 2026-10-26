class ProviderFailure implements Exception {
  const ProviderFailure(this.message);

  static const missingTableMessage =
      'A tabela de parceiros ainda não existe no Supabase. '
      'Aplique a migração providers para gravar os cadastros.';

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
        normalized.contains('schema cache') ||
        normalized.contains('could not find the table') ||
        normalized.contains('tabela de parceiros ainda não existe');
  }

  @override
  String toString() => message;
}
