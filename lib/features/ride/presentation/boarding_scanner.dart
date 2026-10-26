import 'package:flutter/material.dart';

class BoardingScanResult {
  const BoardingScanResult.qr(this.value) : isReserveCode = false;
  const BoardingScanResult.reserveCode(this.value) : isReserveCode = true;

  final String value;
  final bool isReserveCode;
}

abstract class BoardingScanner {
  Future<BoardingScanResult?> scan(
    BuildContext context, {
    required Future<String?> Function(String code) confirmReserveCode,
  });
}
