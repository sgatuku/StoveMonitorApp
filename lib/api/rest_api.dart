import 'dart:convert';
import 'package:http/http.dart' as http;

/// Stove Detection REST API Client for Flutter
/// 
/// This file contains the complete API definition and client implementation
/// that can be used in both Android and iOS Flutter apps.
/// 
/// Dependencies required in pubspec.yaml:
///   http: ^1.1.0
///   json_annotation: ^4.8.1
///   json_serializable: ^6.7.1
///   build_runner: ^2.4.7

// API Constants
class APIEndpoints {
  static const String health = '/health';
  static const String status = '/status';
  static const String detect = '/detect';
}

class HTTPMethods {
  static const String get = 'GET';
  static const String post = 'POST';
}

class HTTPStatus {
  static const int ok = 200;
  static const int badRequest = 400;
  static const int unauthorized = 401;
  static const int notFound = 404;
  static const int methodNotAllowed = 405;
  static const int requestEntityTooLarge = 413;
  static const int internalServerError = 500;
}

class APIConfig {
  static const String defaultHost = '0.0.0.0';
  static const int defaultPort = 5000;
  static const int maxFileSizeMB = 16;
  static const String apiKeyHeader = 'X-API-Key';
  static const String contentTypeJson = 'application/json';
  
  static String getBaseUrl({
    String host = defaultHost,
    int port = defaultPort,
    bool useHttps = false,
  }) {
    final protocol = useHttps ? 'https' : 'http';
    final actualHost = host == '0.0.0.0' ? 'localhost' : host;
    return '$protocol://$actualHost:$port';
  }
}

// Data Models
class HealthResponse {
  final String status;
  final String timestamp;
  final String service;
  final bool authRequired;

  HealthResponse({
    required this.status,
    required this.timestamp,
    required this.service,
    required this.authRequired,
  });

  factory HealthResponse.fromJson(Map<String, dynamic> json) {
    return HealthResponse(
      status: json['status'] as String,
      timestamp: json['timestamp'] as String,
      service: json['service'] as String,
      authRequired: json['auth_required'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'timestamp': timestamp,
      'service': service,
      'auth_required': authRequired,
    };
  }
}

class StatusResponse {
  final String status;
  final String timestamp;
  final String userType;
  final Map<String, dynamic> configuration;
  final Map<String, String> endpoints;

  StatusResponse({
    required this.status,
    required this.timestamp,
    required this.userType,
    required this.configuration,
    required this.endpoints,
  });

  factory StatusResponse.fromJson(Map<String, dynamic> json) {
    return StatusResponse(
      status: json['status'] as String,
      timestamp: json['timestamp'] as String,
      userType: json['user_type'] as String,
      configuration: Map<String, dynamic>.from(json['configuration'] as Map),
      endpoints: Map<String, String>.from(json['endpoints'] as Map),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'timestamp': timestamp,
      'user_type': userType,
      'configuration': configuration,
      'endpoints': endpoints,
    };
  }
}

class DetectRequest {
  final String? imagePath;
  final bool useCamera;
  final double? tolerance;
  final double? offAngle;
  final bool verbose;

  DetectRequest({
    this.imagePath,
    this.useCamera = false,
    this.tolerance,
    this.offAngle,
    this.verbose = false,
  }) : assert(imagePath != null || useCamera, 'Either imagePath or useCamera must be provided');

  factory DetectRequest.fromJson(Map<String, dynamic> json) {
    return DetectRequest(
      imagePath: json['image_path'] as String?,
      useCamera: json['use_camera'] as bool? ?? false,
      tolerance: json['tolerance']?.toDouble(),
      offAngle: json['off_angle']?.toDouble(),
      verbose: json['verbose'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'verbose': verbose,
    };
    
    if (imagePath != null) {
      json['image_path'] = imagePath;
    }
    
    if (useCamera) {
      json['use_camera'] = useCamera;
    }
    
    if (tolerance != null) {
      json['tolerance'] = tolerance;
    }
    if (offAngle != null) {
      json['off_angle'] = offAngle;
    }
    
    return json;
  }
}

class KnobDetectionResult {
  final String file;
  final double? angle;
  final bool isOn;
  final int lineCount;
  final String? error;

  KnobDetectionResult({
    required this.file,
    this.angle,
    required this.isOn,
    required this.lineCount,
    this.error,
  });

  factory KnobDetectionResult.fromJson(Map<String, dynamic> json) {
    return KnobDetectionResult(
      file: json['file'] as String,
      angle: json['angle']?.toDouble(),
      isOn: json['is_on'] as bool,
      lineCount: json['line_count'] as int,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'file': file,
      'is_on': isOn,
      'line_count': lineCount,
    };
    
    if (angle != null) {
      json['angle'] = angle;
    }
    if (error != null) {
      json['error'] = error;
    }
    
    return json;
  }
}

class StoveStatusSummary {
  final bool stoveIsOn;
  final int totalKnobs;
  final int onKnobs;
  final int offKnobs;
  final int errorKnobs;
  final List<String> onKnobNames;
  final List<String> offKnobNames;
  final List<String> errorKnobNames;

  StoveStatusSummary({
    required this.stoveIsOn,
    required this.totalKnobs,
    required this.onKnobs,
    required this.offKnobs,
    required this.errorKnobs,
    required this.onKnobNames,
    required this.offKnobNames,
    required this.errorKnobNames,
  });

  factory StoveStatusSummary.fromJson(Map<String, dynamic> json) {
    return StoveStatusSummary(
      stoveIsOn: json['stove_is_on'] as bool,
      totalKnobs: json['total_knobs'] as int,
      onKnobs: json['on_knobs'] as int,
      offKnobs: json['off_knobs'] as int,
      errorKnobs: json['error_knobs'] as int,
      onKnobNames: List<String>.from(json['on_knob_names'] as List),
      offKnobNames: List<String>.from(json['off_knob_names'] as List),
      errorKnobNames: List<String>.from(json['error_knob_names'] as List),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stove_is_on': stoveIsOn,
      'total_knobs': totalKnobs,
      'on_knobs': onKnobs,
      'off_knobs': offKnobs,
      'error_knobs': errorKnobs,
      'on_knob_names': onKnobNames,
      'off_knob_names': offKnobNames,
      'error_knob_names': errorKnobNames,
    };
  }
}

class DetectionSettings {
  final double tolerance;
  final double offAngle;
  final String calibrationFile;

  DetectionSettings({
    required this.tolerance,
    required this.offAngle,
    required this.calibrationFile,
  });

  factory DetectionSettings.fromJson(Map<String, dynamic> json) {
    return DetectionSettings(
      tolerance: json['tolerance'].toDouble(),
      offAngle: json['off_angle'].toDouble(),
      calibrationFile: json['calibration_file'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tolerance': tolerance,
      'off_angle': offAngle,
      'calibration_file': calibrationFile,
    };
  }
}

class DetectionSummary {
  final int totalKnobs;
  final int onKnobs;
  final int offKnobs;
  final int errorKnobs;

  DetectionSummary({
    required this.totalKnobs,
    required this.onKnobs,
    required this.offKnobs,
    required this.errorKnobs,
  });

  factory DetectionSummary.fromJson(Map<String, dynamic> json) {
    return DetectionSummary(
      totalKnobs: json['total_knobs'] as int,
      onKnobs: json['on_knobs'] as int,
      offKnobs: json['off_knobs'] as int,
      errorKnobs: json['error_knobs'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_knobs': totalKnobs,
      'on_knobs': onKnobs,
      'off_knobs': offKnobs,
      'error_knobs': errorKnobs,
    };
  }
}

class CroppedImage {
  final String filename;
  final String data; // base64 encoded image data
  final String mimeType;

  CroppedImage({
    required this.filename,
    required this.data,
    required this.mimeType,
  });

  factory CroppedImage.fromJson(Map<String, dynamic> json) {
    return CroppedImage(
      filename: json['filename'] as String,
      data: json['data'] as String,
      mimeType: json['mime_type'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'filename': filename,
      'data': data,
      'mime_type': mimeType,
    };
  }
}

class DetectResponse {
  final bool success;
  final String timestamp;
  final String inputImage;
  final DetectionSettings settings;
  final List<KnobDetectionResult> detectionResults;
  final StoveStatusSummary stoveStatus;
  final bool stoveIsOn;
  final DetectionSummary summary;
  final String? userType;
  final String? imageSource;
  final List<CroppedImage>? croppedImages;

  DetectResponse({
    required this.success,
    required this.timestamp,
    required this.inputImage,
    required this.settings,
    required this.detectionResults,
    required this.stoveStatus,
    required this.stoveIsOn,
    required this.summary,
    this.userType,
    this.imageSource,
    this.croppedImages,
  });

  factory DetectResponse.fromJson(Map<String, dynamic> json) {
    return DetectResponse(
      success: json['success'] as bool,
      timestamp: json['timestamp'] as String,
      inputImage: json['input_image'] as String,
      settings: DetectionSettings.fromJson(json['settings'] as Map<String, dynamic>),
      detectionResults: (json['detection_results'] as List)
          .map((item) => KnobDetectionResult.fromJson(item as Map<String, dynamic>))
          .toList(),
      stoveStatus: StoveStatusSummary.fromJson(json['stove_status'] as Map<String, dynamic>),
      stoveIsOn: json['stove_is_on'] as bool,
      summary: DetectionSummary.fromJson(json['summary'] as Map<String, dynamic>),
      userType: json['user_type'] as String?,
      imageSource: json['image_source'] as String?,
      croppedImages: json['cropped_images'] != null 
          ? (json['cropped_images'] as List)
              .map((item) => CroppedImage.fromJson(item as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'timestamp': timestamp,
      'input_image': inputImage,
      'settings': settings.toJson(),
      'detection_results': detectionResults.map((item) => item.toJson()).toList(),
      'stove_status': stoveStatus.toJson(),
      'stove_is_on': stoveIsOn,
      'summary': summary.toJson(),
      if (userType != null) 'user_type': userType,
      if (imageSource != null) 'image_source': imageSource,
      if (croppedImages != null) 'cropped_images': croppedImages!.map((img) => img.toJson()).toList(),
    };
  }
}

class ErrorResponse {
  final String error;

  ErrorResponse({required this.error});

  factory ErrorResponse.fromJson(Map<String, dynamic> json) {
    return ErrorResponse(error: json['error'] as String);
  }

  Map<String, dynamic> toJson() {
    return {'error': error};
  }
}

// API Client
class StoveDetectionClient {
  final String baseUrl;
  final String? apiKey;
  final http.Client _client;

  StoveDetectionClient({
    required this.baseUrl,
    this.apiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Map<String, String> get _headers {
    final headers = <String, String>{};
    if (apiKey != null) {
      headers[APIConfig.apiKeyHeader] = apiKey!;
    }
    // Add cache control to prevent Cloudflare from serving stale/cached empty responses
    headers['Cache-Control'] = 'no-cache, no-store, must-revalidate';
    headers['Pragma'] = 'no-cache';
    return headers;
  }

  /// Check if the API server is healthy
  Future<HealthResponse> healthCheck() async {
    final response = await _client.get(
      Uri.parse('$baseUrl${APIEndpoints.health}'),
      headers: _headers,
    );

    if (response.statusCode == HTTPStatus.ok) {
      if (response.body.isEmpty) {
        throw Exception('Health check failed: Server returned empty response');
      }
      return HealthResponse.fromJson(json.decode(response.body));
    } else {
      throw Exception('Health check failed: ${response.statusCode} - ${response.body}');
    }
  }

  /// Get server status and configuration
  Future<StatusResponse> getStatus() async {
    final response = await _client.get(
      Uri.parse('$baseUrl${APIEndpoints.status}'),
      headers: _headers,
    );

    if (response.statusCode == HTTPStatus.ok) {
      if (response.body.isEmpty) {
        throw Exception('Status check failed: Server returned empty response');
      }
      return StatusResponse.fromJson(json.decode(response.body));
    } else {
      throw Exception('Status check failed: ${response.statusCode} - ${response.body}');
    }
  }

  /// Detect stove status from an image file
  Future<DetectResponse> detectStove({
    required String imagePath,
    double? tolerance,
    double? offAngle,
    bool verbose = false,
  }) async {
    final request = DetectRequest(
      imagePath: imagePath,
      tolerance: tolerance,
      offAngle: offAngle,
      verbose: verbose,
    );

    final response = await _client.post(
      Uri.parse('$baseUrl${APIEndpoints.detect}'),
      headers: {
        ..._headers,
        'Content-Type': APIConfig.contentTypeJson,
      },
      body: json.encode(request.toJson()),
    );

    if (response.statusCode == HTTPStatus.ok) {
      if (response.body.isEmpty) {
        throw Exception('Detection failed: Server returned empty response');
      }
      return DetectResponse.fromJson(json.decode(response.body));
    } else {
      if (response.body.isEmpty) {
        throw Exception('Detection failed: Server returned empty response (status: ${response.statusCode})');
      }
      final errorBody = json.decode(response.body);
      final error = ErrorResponse.fromJson(errorBody);
      throw Exception('Detection failed: ${error.error}');
    }
  }

  /// Detect stove status using live camera capture
  Future<DetectResponse> detectStoveWithCamera({
    double? tolerance,
    double? offAngle,
    bool verbose = false,
  }) async {
    final request = DetectRequest(
      useCamera: true,
      tolerance: tolerance,
      offAngle: offAngle,
      verbose: verbose,
    );

    final response = await _client.post(
      Uri.parse('$baseUrl${APIEndpoints.detect}'),
      headers: {
        ..._headers,
        'Content-Type': APIConfig.contentTypeJson,
      },
      body: json.encode(request.toJson()),
    );

    if (response.statusCode == HTTPStatus.ok) {
      if (response.body.isEmpty) {
        throw Exception('Camera detection failed: Server returned empty response');
      }
      return DetectResponse.fromJson(json.decode(response.body));
    } else {
      if (response.body.isEmpty) {
        throw Exception('Camera detection failed: Server returned empty response (status: ${response.statusCode})');
      }
      final errorBody = json.decode(response.body);
      final error = ErrorResponse.fromJson(errorBody);
      throw Exception('Camera detection failed: ${error.error}');
    }
  }

  void dispose() {
    _client.close();
  }
}

// API Result wrapper for better error handling
class APIResult<T> {
  final T? data;
  final String? error;
  final bool isSuccess;

  APIResult.success(this.data) : error = null, isSuccess = true;
  APIResult.error(this.error) : data = null, isSuccess = false;

  bool get isError => !isSuccess;
}

// Extension methods for easier error handling
extension StoveDetectionClientExtensions on StoveDetectionClient {
  Future<APIResult<HealthResponse>> healthCheckSafe() async {
    try {
      final result = await healthCheck();
      return APIResult.success(result);
    } catch (e) {
      return APIResult.error(e.toString());
    }
  }

  Future<APIResult<StatusResponse>> getStatusSafe() async {
    try {
      final result = await getStatus();
      return APIResult.success(result);
    } catch (e) {
      return APIResult.error(e.toString());
    }
  }

  Future<APIResult<DetectResponse>> detectStoveSafe({
    required String imagePath,
    double? tolerance,
    double? offAngle,
    bool verbose = false,
  }) async {
    try {
      final result = await detectStove(
        imagePath: imagePath,
        tolerance: tolerance,
        offAngle: offAngle,
        verbose: verbose,
      );
      return APIResult.success(result);
    } catch (e) {
      return APIResult.error(e.toString());
    }
  }

  Future<APIResult<DetectResponse>> detectStoveWithCameraSafe({
    double? tolerance,
    double? offAngle,
    bool verbose = false,
  }) async {
    try {
      final result = await detectStoveWithCamera(
        tolerance: tolerance,
        offAngle: offAngle,
        verbose: verbose,
      );
      return APIResult.success(result);
    } catch (e) {
      return APIResult.error(e.toString());
    }
  }
}
