import 'dart:convert';

const String jsonRpcVersion = '2.0';

sealed class JsonRpcMessage {
  const JsonRpcMessage();

  Map<String, Object?> toJson();

  String encode() => jsonEncode(toJson());
}

final class JsonRpcRequest extends JsonRpcMessage {
  const JsonRpcRequest({required this.method, required this.id, this.params});

  final String method;
  final Object id;
  final Object? params;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'jsonrpc': jsonRpcVersion,
    'method': method,
    if (params != null) 'params': params,
    'id': id,
  };
}

final class JsonRpcNotification extends JsonRpcMessage {
  const JsonRpcNotification({required this.method, this.params});

  final String method;
  final Object? params;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'jsonrpc': jsonRpcVersion,
    'method': method,
    if (params != null) 'params': params,
  };
}

final class JsonRpcResponse extends JsonRpcMessage {
  const JsonRpcResponse.success({required this.id, required this.result})
    : error = null;

  const JsonRpcResponse.error({required this.id, required this.error})
    : result = null;

  final Object? id;
  final Object? result;
  final JsonRpcError? error;

  bool get isSuccess => error == null;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'jsonrpc': jsonRpcVersion,
    if (error == null) 'result': result else 'error': error!.toJson(),
    'id': id,
  };
}

final class JsonRpcError {
  const JsonRpcError({required this.code, required this.message, this.data});

  static const int parseError = -32700;
  static const int invalidRequest = -32600;
  static const int methodNotFound = -32601;
  static const int invalidParams = -32602;
  static const int internalError = -32603;

  final int code;
  final String message;
  final Object? data;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    if (data != null) 'data': data,
  };
}

final class JsonRpcFormatException implements FormatException {
  const JsonRpcFormatException(this.message, {this.source});

  @override
  final String message;

  @override
  final Object? source;

  @override
  int? get offset => null;

  @override
  String toString() => 'JsonRpcFormatException: $message';
}

final class JsonRpcCodec {
  const JsonRpcCodec();

  JsonRpcMessage decode(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw JsonRpcFormatException('Invalid JSON', source: error);
    }
    if (decoded is! Map<String, Object?>) {
      throw const JsonRpcFormatException('Message must be a JSON object');
    }
    if (decoded['jsonrpc'] != jsonRpcVersion) {
      throw const JsonRpcFormatException('jsonrpc must equal 2.0');
    }

    if (decoded.containsKey('method')) {
      return _decodeCall(decoded);
    }
    return _decodeResponse(decoded);
  }

  JsonRpcMessage _decodeCall(Map<String, Object?> decoded) {
    final method = decoded['method'];
    if (method is! String || method.isEmpty) {
      throw const JsonRpcFormatException('method must be a non-empty string');
    }
    final params = decoded['params'];
    if (params != null &&
        params is! List<Object?> &&
        params is! Map<String, Object?>) {
      throw const JsonRpcFormatException('params must be an object or array');
    }
    if (!decoded.containsKey('id')) {
      return JsonRpcNotification(method: method, params: params);
    }
    final id = decoded['id'];
    if (id is! String && id is! int) {
      throw const JsonRpcFormatException('id must be a string or integer');
    }
    return JsonRpcRequest(method: method, id: id as Object, params: params);
  }

  JsonRpcResponse _decodeResponse(Map<String, Object?> decoded) {
    final id = decoded['id'];
    if (id != null && id is! String && id is! int) {
      throw const JsonRpcFormatException('response id has an invalid type');
    }
    final hasResult = decoded.containsKey('result');
    final hasError = decoded.containsKey('error');
    if (hasResult == hasError) {
      throw const JsonRpcFormatException(
        'response must contain exactly one of result or error',
      );
    }
    if (hasResult) {
      return JsonRpcResponse.success(id: id, result: decoded['result']);
    }
    final error = decoded['error'];
    if (error is! Map<String, Object?> ||
        error['code'] is! int ||
        error['message'] is! String) {
      throw const JsonRpcFormatException('invalid error object');
    }
    return JsonRpcResponse.error(
      id: id,
      error: JsonRpcError(
        code: error['code']! as int,
        message: error['message']! as String,
        data: error['data'],
      ),
    );
  }
}
