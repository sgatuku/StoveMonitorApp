import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:location/location.dart';
import '../api/rest_api.dart';
import 'notification_service.dart';
import 'location_utils.dart';

/// Simple background location monitoring service
/// Checks location every minute and triggers stove check only when leaving home
class BackgroundLocationService {
  static final BackgroundLocationService _instance =
      BackgroundLocationService._internal();
  factory BackgroundLocationService() => _instance;
  BackgroundLocationService._internal();

  // Constants
  static const Duration _locationCheckInterval = Duration(seconds: 30);

  // Method channel for native Android communication
  static const MethodChannel _batteryChannel = MethodChannel(
    'com.example.StoveMonitorApp/battery_optimization',
  );

  // State variables
  bool _isInitialized = false;
  bool _isMonitoring = false;
  LocationData? _homeLocation;
  bool _isNearHome = true;
  bool _hasCheckedStoveSinceLeaving = false;
  Timer? _locationTimer;
  final Location _location = Location();
  StoveDetectionClient? _apiClient;

  // Callbacks for external services
  Function(bool isNearHome, double distanceMiles)? onLocationStatusChanged;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isMonitoring => _isMonitoring;
  bool get isNearHome => _isNearHome;
  LocationData? get homeLocation => _homeLocation;

  /// Initialize the service
  Future<bool> initialize({
    required String apiBaseUrl,
    required String apiKey,
  }) async {
    try {
      if (_isInitialized) return true;

      // Initialize API client
      _apiClient = StoveDetectionClient(baseUrl: apiBaseUrl, apiKey: apiKey);

      // Initialize notification service
      await NotificationService().initialize();

      // Load saved settings asynchronously to avoid blocking
      _loadSettings().catchError((e) {
        debugPrint('BackgroundLocationService: Error loading settings: $e');
      });

      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('Failed to initialize BackgroundLocationService: $e');
      return false;
    }
  }

  /// Start monitoring location
  Future<void> startMonitoring() async {
    if (!_isInitialized) {
      return;
    }

    if (_homeLocation == null) {
      return;
    }

    if (_isMonitoring) {
      return;
    }

    try {
      // Check location immediately
      await _checkLocation();

      // Start timer for foreground execution (works on both platforms)
      _locationTimer = Timer.periodic(_locationCheckInterval, (_) {
        _checkLocation();
      });

      if (Platform.isAndroid) {
        // Start native Android foreground service for better background execution
        await _batteryChannel.invokeMethod('startBackgroundService');
      }

      _isMonitoring = true;

      // Show notification that background monitoring is active
      await NotificationService().showBackgroundMonitoringStartedNotification();
    } catch (e) {
      debugPrint('Failed to start monitoring: $e');
    }
  }

  /// Stop monitoring location
  Future<void> stopMonitoring() async {
    // Always cancel the foreground timer
    _locationTimer?.cancel();
    _locationTimer = null;

    if (Platform.isAndroid) {
      // Stop native Android foreground service
      await _batteryChannel.invokeMethod('stopBackgroundService');
    }

    _isMonitoring = false;

    // Show notification that background monitoring is stopped
    await NotificationService().showBackgroundMonitoringStoppedNotification();
  }

  /// Set home location
  Future<void> setHomeLocation(LocationData location) async {
    try {
      _homeLocation = location;
      await _saveHomeLocation(location);

      // Reset state when home location changes
      _isNearHome = true;
      _hasCheckedStoveSinceLeaving = false;
    } catch (e) {
      debugPrint('Failed to set home location: $e');
    }
  }

  /// Check current location and handle state changes
  Future<void> _checkLocation() async {
    try {
      final currentLocation = await _location.getLocation();
      if (currentLocation.latitude == null ||
          currentLocation.longitude == null) {
        return;
      }

      final wasNearHome = _isNearHome;
      _isNearHome = _isLocationNearHome(currentLocation);

      // Calculate distance for logging and callback
      double distanceMiles = 0.0;
      if (_homeLocation != null) {
        final distanceMeters = LocationUtils.calculateDistance(
          _homeLocation!.latitude!,
          _homeLocation!.longitude!,
          currentLocation.latitude!,
          currentLocation.longitude!,
        );
        distanceMiles = distanceMeters / 1609.34;
      }

      // Debug logging

      // Notify external services of location status change
      onLocationStatusChanged?.call(_isNearHome, distanceMiles);

      // Handle state transitions
      if (wasNearHome && !_isNearHome) {
        // Just left home
        _hasCheckedStoveSinceLeaving = false;
        await NotificationService().showLeftHomeNotification();
        await _checkStoveStatus();
      } else if (!wasNearHome && _isNearHome) {
        // Just returned home
        _hasCheckedStoveSinceLeaving = false;
        await NotificationService().showReturnedHomeNotification();
      }
    } catch (e) {
      debugPrint('❌ BACKGROUND: Error checking location: $e');
    }
  }

  /// Check if location is near home
  bool _isLocationNearHome(LocationData location) {
    if (_homeLocation == null) {
      return false;
    }

    return LocationUtils.isLocationNearHome(_homeLocation!, location);
  }

  /// Check stove status (only called when leaving home)
  Future<void> _checkStoveStatus() async {
    if (_apiClient == null || _hasCheckedStoveSinceLeaving) {
      return;
    }

    // Retry configuration
    const int maxRetries = 5;
    const Duration initialDelay = Duration(seconds: 2);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint(
          'BACKGROUND: Attempting stove detection (attempt $attempt/$maxRetries)',
        );

        final result = await _apiClient!.detectStoveWithCameraSafe(
          verbose: false,
        );

        if (result.isSuccess && result.data != null) {
          final detection = result.data!;

          // Send notification for all stove detection results
          await NotificationService().showStoveStatusNotification(
            stoveIsOn: detection.stoveIsOn,
            onKnobs: detection.summary.onKnobs,
            totalKnobs: detection.summary.totalKnobs,
          );

          _hasCheckedStoveSinceLeaving = true;
          debugPrint(
            'BACKGROUND: Stove detection successful on attempt $attempt',
          );
          return; // Success, exit retry loop
        } else {
          // Check if this is a retryable error (empty response or network issues)
          final error = result.error ?? 'Unknown error occurred';
          final isRetryable =
              error.contains('empty response') ||
              error.contains('connection') ||
              error.contains('timeout') ||
              error.contains('Unexpected end of input');

          if (isRetryable && attempt < maxRetries) {
            debugPrint(
              'BACKGROUND: Retryable error on attempt $attempt: $error',
            );
            await Future.delayed(initialDelay * attempt); // Exponential backoff
            continue; // Retry
          } else {
            // Non-retryable error or max attempts reached
            debugPrint(
              'BACKGROUND: Failed detection after $attempt attempts: $error',
            );

            // Send notification for failed detection
            await NotificationService().showStoveStatusNotification(
              stoveIsOn: false,
              onKnobs: 0,
              totalKnobs: 0,
              errorMessage: error,
            );
            return; // Exit after max attempts or non-retryable error
          }
        }
      } catch (e) {
        debugPrint('BACKGROUND: Exception on attempt $attempt: $e');

        final errorMsg = e.toString();
        final isRetryable =
            errorMsg.contains('empty response') ||
            errorMsg.contains('connection') ||
            errorMsg.contains('timeout') ||
            errorMsg.contains('Unexpected end of input') ||
            errorMsg.contains('FormatException');

        if (isRetryable && attempt < maxRetries) {
          debugPrint('BACKGROUND: Retryable exception on attempt $attempt');
          await Future.delayed(initialDelay * attempt); // Exponential backoff
          continue; // Retry
        } else {
          // Non-retryable exception or max attempts reached
          debugPrint(
            'BACKGROUND: Failed after $attempt attempts with exception: $e',
          );

          // Send notification for exception
          await NotificationService().showStoveStatusNotification(
            stoveIsOn: false,
            onKnobs: 0,
            totalKnobs: 0,
            errorMessage: errorMsg,
          );
          return; // Exit after max attempts or non-retryable error
        }
      }
    }
  }

  /// Load saved settings from file system
  Future<void> _loadSettings() async {
    try {
      // Get the app's storage directory using path_provider_plus
      final storagePath = await LocationUtils.getStorageDirectory();

      final homeLocationFile = File('$storagePath/home_location.json');

      // Check if file exists first to avoid unnecessary async operations
      if (await homeLocationFile.exists()) {
        try {
          final homeLocationJson = await homeLocationFile.readAsString();
          final homeLocationMap =
              json.decode(homeLocationJson) as Map<String, dynamic>;
          _homeLocation = LocationData.fromMap({
            'latitude': homeLocationMap['latitude'] as double,
            'longitude': homeLocationMap['longitude'] as double,
            'time': homeLocationMap['timestamp'] as double,
            'accuracy': homeLocationMap['accuracy'] as double,
            'altitude': homeLocationMap['altitude'] as double,
            'heading': homeLocationMap['heading'] as double,
            'speed': homeLocationMap['speed'] as double,
            'speed_accuracy': homeLocationMap['speedAccuracy'] as double,
          });
          debugPrint(
            'BackgroundLocationService: Home location loaded from storage',
          );
        } catch (e) {
          debugPrint(
            'BackgroundLocationService: Error loading home location: $e',
          );
          _homeLocation = null;
        }
      }
    } catch (e) {
      debugPrint('BackgroundLocationService: Error loading settings: $e');
      // Error loading settings - continue with defaults
    }
  }

  /// Save home location to file system
  Future<void> _saveHomeLocation(LocationData location) async {
    try {
      // Get the app's storage directory using path_provider_plus
      final storagePath = await LocationUtils.getStorageDirectory();

      final homeLocationFile = File('$storagePath/home_location.json');

      // Ensure directory exists
      final directory = Directory(storagePath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final locationMap = {
        'latitude': location.latitude,
        'longitude': location.longitude,
        'timestamp':
            location.time ?? DateTime.now().millisecondsSinceEpoch.toDouble(),
        'accuracy': location.accuracy,
        'altitude': location.altitude,
        'heading': location.heading,
        'speed': location.speed,
        'speedAccuracy': location.speedAccuracy,
      };

      await homeLocationFile.writeAsString(json.encode(locationMap));
    } catch (e) {
      // Error loading settings - continue with defaults
    }
  }

  /// Get current location
  Future<LocationData?> getCurrentLocation() async {
    try {
      return await _location.getLocation();
    } catch (e) {
      debugPrint('Error getting current location: $e');
      return null;
    }
  }

  /// Manually trigger location check (for testing)
  Future<void> triggerLocationCheck() async {
    await _checkLocation();
  }

  /// Calculate distance from home in miles
  Future<double?> getDistanceFromHomeMiles() async {
    if (_homeLocation == null) return null;

    try {
      final position = await _location.getLocation();
      if (position.latitude == null || position.longitude == null) return null;

      final distanceMiles = LocationUtils.getDistanceFromHomeMiles(
        _homeLocation!,
        position,
      );
      return distanceMiles;
    } catch (e) {
      return null;
    }
  }

  /// Request battery optimization disable
  Future<bool> requestBatteryOptimizationDisable() async {
    try {
      if (Platform.isAndroid) {
        await _batteryChannel.invokeMethod('requestBatteryOptimizationDisable');
        return true;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Check if battery optimization is disabled
  Future<bool> isBatteryOptimizationDisabled() async {
    try {
      if (Platform.isAndroid) {
        final result = await _batteryChannel.invokeMethod(
          'isBatteryOptimizationDisabled',
        );
        return result == true;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    await stopMonitoring();
    _apiClient?.dispose();
    _isInitialized = false;
  }
}
