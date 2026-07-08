import 'package:flutter/foundation.dart';

class AppException implements Exception {
  final String message;
  final String? code;
  final Object? originalError;

  AppException(this.message, {this.code, this.originalError});

  @override
  String toString() => 'AppException($code): $message';
}

class BaseService {
  @protected
  Future<T> safeCall<T>(Future<T> Function() call,
      {String? fallbackMessage}) async {
    try {
      return await call();
    } catch (e) {
      debugPrint('Service error: $e');
      throw AppException(
        fallbackMessage ?? 'An unexpected error occurred',
        code: 'SERVICE_ERROR',
        originalError: e,
      );
    }
  }
}
