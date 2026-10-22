import 'package:dio/dio.dart';

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  /// No answer, a timeout, or a 502/503/504 from Render's proxy — the server is asleep or
  /// restarting, not refusing. Callers can wait for it and retry instead of failing.
  final bool serverAsleep;

  ApiException({this.statusCode, required this.message, this.serverAsleep = false});

  @override
  String toString() => message;

  static ApiException from(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final data = e.response?.data;

      String msg = 'Something went wrong. Please try again.';

      if (data is Map && data['message'] != null) {
        msg = data['message'].toString();
      } else if (status == 401) {
        msg = 'Session expired. Please log in again.';
      } else if (status == 403) {
        msg = 'You do not have permission to do that.';
      } else if (status == 404) {
        msg = 'Resource not found.';
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        msg = 'Request timed out. Check your network connection.';
      } else if (e.type == DioExceptionType.connectionError) {
        msg = e.requestOptions.method.toUpperCase() == 'GET'
            ? 'Cannot reach the server. Check your network.'
            : "You're offline. This needs an internet connection.";
      }

      final asleep = e.response == null
          ? const [DioExceptionType.connectionTimeout, DioExceptionType.receiveTimeout,
              DioExceptionType.connectionError, DioExceptionType.sendTimeout].contains(e.type)
          : const [502, 503, 504].contains(status);
      return ApiException(statusCode: status, message: msg, serverAsleep: asleep);
    }
    if (e is ApiException) return e;
    return ApiException(message: e.toString());
  }
}
