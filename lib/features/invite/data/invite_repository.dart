import 'package:dio/dio.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Причини, з яких код може не спрацювати. Кожна має власне повідомлення на
/// екрані, бо «щось пішло не так» тут нічим не допоможе користувачу.
enum InviteFailure { notFound, alreadyUsed, tooManyAttempts, network }

class InviteException implements Exception {
  const InviteException(this.failure);
  final InviteFailure failure;
}

class InviteRepository {
  InviteRepository({required this.apiBase, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              // Коди коротші за будь-який ліміт, тож ретраїв не додаємо:
              // погашення не ідемпотентне, і повтор спалив би другий код.
              validateStatus: (_) => true,
            ),
          );

  final String apiBase;
  final Dio _dio;

  /// Гасить код і повертає персональне посилання на підписку.
  /// Кидає [InviteException] — сирі помилки Dio назовні не течуть.
  Future<String> redeem(String code) async {
    final normalized = code.trim().toUpperCase();

    final Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>('$apiBase/api/redeem/$normalized');
    } on DioException {
      throw const InviteException(InviteFailure.network);
    }

    switch (response.statusCode) {
      case 201:
        final url = (response.data as Map?)?['subscription_url'] as String?;
        if (url == null || url.isEmpty) {
          throw const InviteException(InviteFailure.network);
        }
        return url;
      case 404:
        throw const InviteException(InviteFailure.notFound);
      case 409:
        throw const InviteException(InviteFailure.alreadyUsed);
      case 429:
        throw const InviteException(InviteFailure.tooManyAttempts);
      default:
        throw const InviteException(InviteFailure.network);
    }
  }
}

final inviteRepositoryProvider = Provider<InviteRepository>(
  (ref) => InviteRepository(apiBase: Constants.apiBase),
);
