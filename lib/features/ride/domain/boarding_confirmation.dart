import 'package:xofer/prof/data/supabase_corrida_repository.dart';
import 'package:xofer/prof/domain/corrida_repository.dart';

abstract class BoardingConfirmation {
  Future<void> confirm(String scannedToken);

  Future<void> confirmReserveCode(String reserveCode);
}

class RepositoryBoardingConfirmation implements BoardingConfirmation {
  RepositoryBoardingConfirmation(this.repository);

  factory RepositoryBoardingConfirmation.remote() {
    return RepositoryBoardingConfirmation(SupabaseCorridaRepository());
  }

  final CorridaRepository repository;

  @override
  Future<void> confirm(String scannedToken) {
    return repository.confirmBoarding(scannedToken);
  }

  @override
  Future<void> confirmReserveCode(String reserveCode) async {
    await repository.confirmBoardingWithReserveCode(reserveCode);
  }
}
