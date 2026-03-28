class ApiResponse<T> {
  ApiResponse({
    required this.success,
    required this.message,
    required this.data,
    required this.timestamp,
  });

  final bool success;
  final String? message;
  final T? data;
  final DateTime? timestamp;

  static ApiResponse<R> fromJson<R>(
    Map<String, dynamic> json,
    R Function(Object? raw) decode,
  ) {
    return ApiResponse<R>(
      success: json['success'] == true,
      message: json['message']?.toString(),
      data: decode(json['data']),
      timestamp: json['timestamp'] == null
          ? null
          : DateTime.tryParse(json['timestamp'].toString()),
    );
  }
}
