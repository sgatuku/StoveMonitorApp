import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:location/location.dart';
// import 'package:permission_handler/permission_handler.dart';
import '../api/rest_api.dart';
import 'notification_service.dart';
import 'background_location_service.dart';
import 'location_utils.dart';

class GeofencingService {
  static final GeofencingService _instance = GeofencingService._internal();
  factory GeofencingService() => _instance;
  GeofencingService._internal();

  // Constants (file names for storage)
  // static const String _homeLocationFileName = 'home_location.json';
  // static const String _geofencingEnabledFileName = 'geofencing_enabled.json';

  // State variables
  bool _isInitialized = false;
  bool _isGeofencingEnabled = false;
  LocationData? _homeLocation;
  bool _isNearHome = true; // Start assuming we're at home
  StoveDetectionClient? _apiClient;
  bool _settingsLoaded = false;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isGeofencingEnabled => _isGeofencingEnabled;
  bool get isNearHome => _isNearHome;
  LocationData? get homeLocation => _homeLocation;
  bool get settingsLoaded => _settingsLoaded;

  // Callbacks
  Function(DetectResponse)? onStoveDetected;
  Function(String)? onError;

  /// Initialize the geofencing service
  Future<bool> initialize({
    required String apiBaseUrl,
    required String apiKey,
  }) async {
    try {
      if (_isInitialized) return true;

      // Initialize API client
      _apiClient = StoveDetectionClient(
        baseUrl: apiBaseUrl,
        apiKey: apiKey,
      );

      // Initialize notification service
      await NotificationService().initialize();

      // Initialize background location service
      await BackgroundLocationService().initialize(
        apiBaseUrl: apiBaseUrl,
        apiKey: apiKey,
      );
      
      // Set up callback to receive location status updates
      BackgroundLocationService().onLocationStatusChanged = (isNearHome, distanceMiles) {
        _isNearHome = isNearHome;
        // Additional geofencing logic can be added here if needed
      };

      // Load saved settings asynchronously to avoid blocking
      _loadSettings().then((_) {
        _settingsLoaded = true;
        debugPrint('Settings loaded successfully');
      }).catchError((e) {
        debugPrint('Error loading settings: $e');
        _settingsLoaded = true; // Mark as loaded even if failed
      });

      // Request location permissions
      final hasPermission = await _requestLocationPermissions();
      if (!hasPermission) {
        onError?.call('Location permissions are required for geofencing');
        return false;
      }

      _isInitialized = true;
      debugPrint('GeofencingService initialized successfully');
      return true;
    } catch (e) {
      debugPrint('Failed to initialize GeofencingService: $e');
      onError?.call('Failed to initialize geofencing: $e');
      return false;
    }
  }

  /// Set home location and start geofencing
  Future<bool> setHomeLocation(LocationData location) async {
    try {
      _homeLocation = location;
      await _saveHomeLocation(location);
      
      // Update background location service with home location
      await BackgroundLocationService().setHomeLocation(location);
      
      // Start background location monitoring immediately when home location is set
      // This allows the user to see location updates even before enabling geofencing
      await BackgroundLocationService().startMonitoring();
      
      debugPrint('Home location set: ${location.latitude}, ${location.longitude}');
      return true;
    } catch (e) {
      debugPrint('Failed to set home location: $e');
      onError?.call('Failed to set home location: $e');
      return false;
    }
  }

  /// Enable or disable geofencing
  Future<bool> setGeofencingEnabled(bool enabled) async {
    try {
      debugPrint('🔄 GEOFENCING: Setting geofencing enabled to: $enabled');
      debugPrint('🔄 GEOFENCING: Home location exists: ${_homeLocation != null}');
      
      _isGeofencingEnabled = enabled;
      await _saveGeofencingEnabled(enabled);

      if (enabled && _homeLocation != null) {
        debugPrint('🔄 GEOFENCING: Starting background location monitoring...');
        await BackgroundLocationService().startMonitoring();
        debugPrint('✅ GEOFENCING: Background location monitoring started');
      } else {
        debugPrint('🔄 GEOFENCING: Stopping background location monitoring...');
        await BackgroundLocationService().stopMonitoring();
        debugPrint('✅ GEOFENCING: Background location monitoring stopped');
      }

      debugPrint('✅ GEOFENCING: Geofencing ${enabled ? 'enabled' : 'disabled'}');
      return true;
    } catch (e) {
      debugPrint('❌ GEOFENCING: Failed to set geofencing enabled: $e');
      onError?.call('Failed to update geofencing settings: $e');
      return false;
    }
  }



  /// Check stove status using the API
  Future<void> _checkStoveStatus() async {
    if (_apiClient == null) return;

    try {
      debugPrint('Checking stove status...');
      final result = await _apiClient!.detectStoveWithCameraSafe(
        verbose: true,
      );

      if (result.isSuccess && result.data != null) {
        final detection = result.data!;
        debugPrint('Stove detection result: ${detection.stoveIsOn ? 'ON' : 'OFF'}');
        
        // Notify callback
        onStoveDetected?.call(detection);

        // Send notification for all stove detection results
        await NotificationService().showStoveStatusNotification(
          stoveIsOn: detection.stoveIsOn,
          onKnobs: detection.summary.onKnobs,
          totalKnobs: detection.summary.totalKnobs,
        );
      } else {
        debugPrint('Stove detection failed: ${result.error}');
        onError?.call('Failed to check stove status: ${result.error}');
        
        // Send notification for failed detection
        await NotificationService().showStoveStatusNotification(
          stoveIsOn: false,
          onKnobs: 0,
          totalKnobs: 0,
          errorMessage: result.error ?? 'Unknown error occurred',
        );
      }
    } catch (e) {
      debugPrint('Error checking stove status: $e');
      onError?.call('Error checking stove status: $e');
      
      // Send notification for exception
      await NotificationService().showStoveStatusNotification(
        stoveIsOn: false,
        onKnobs: 0,
        totalKnobs: 0,
        errorMessage: e.toString(),
      );
    }
  }

  /// Request location permissions
  Future<bool> _requestLocationPermissions() async {
    try {
      // Delegate to BackgroundLocationService for permission handling
      // Since BackgroundLocationService already handles location permissions
      return true;
    } catch (e) {
      debugPrint('Error requesting location permissions: $e');
      onError?.call('Error requesting location permissions: $e');
      return false;
    }
  }


  /// Load saved settings
  Future<void> _loadSettings() async {
    try {
      // Get the app's storage directory using path_provider_plus
      final storagePath = await LocationUtils.getStorageDirectory();
      
      // Load both files in parallel for better performance
      final homeLocationFile = File('$storagePath/home_location.json');
      final geofencingFile = File('$storagePath/geofencing_enabled.json');
      
      // Check if files exist first to avoid unnecessary async operations
      final homeLocationExists = await homeLocationFile.exists();
      final geofencingExists = await geofencingFile.exists();
      
      // Load geofencing enabled state
      if (geofencingExists) {
        try {
          final geofencingJson = await geofencingFile.readAsString();
          final geofencingData = json.decode(geofencingJson) as Map<String, dynamic>;
          _isGeofencingEnabled = geofencingData['enabled'] as bool? ?? false;
          debugPrint('Geofencing enabled state loaded: $_isGeofencingEnabled');
        } catch (e) {
          debugPrint('Error loading geofencing state: $e');
          _isGeofencingEnabled = false;
        }
      } else {
        _isGeofencingEnabled = false;
      }
      
      // Load home location
      if (homeLocationExists) {
        try {
          final homeLocationJson = await homeLocationFile.readAsString();
          final homeLocationMap = json.decode(homeLocationJson) as Map<String, dynamic>;
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
          debugPrint('Home location loaded from storage: ${_homeLocation!.latitude}, ${_homeLocation!.longitude}');
          
          // Start background location monitoring since we have a home location
          // Do this asynchronously to avoid blocking the main thread
          BackgroundLocationService().startMonitoring().catchError((e) {
            debugPrint('Error starting background monitoring: $e');
          });
        } catch (e) {
          debugPrint('Error loading home location: $e');
          _homeLocation = null;
        }
      } else {
        debugPrint('No saved home location found');
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
      // Fallback to defaults
      _isGeofencingEnabled = false;
      _homeLocation = null;
    }
  }

  /// Save home location
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
        'timestamp': location.time ?? DateTime.now().millisecondsSinceEpoch.toDouble(),
        'accuracy': location.accuracy,
        'altitude': location.altitude,
        'heading': location.heading,
        'speed': location.speed,
        'speedAccuracy': location.speedAccuracy,
      };
      
      await homeLocationFile.writeAsString(json.encode(locationMap));
      debugPrint('Home location saved to storage: ${location.latitude}, ${location.longitude}');
    } catch (e) {
      debugPrint('Error saving home location: $e');
      // Fallback to in-memory storage
    }
  }

  /// Save geofencing enabled state
  Future<void> _saveGeofencingEnabled(bool enabled) async {
    try {
      // Get the app's storage directory using path_provider_plus
      final storagePath = await LocationUtils.getStorageDirectory();
      
      final geofencingFile = File('$storagePath/geofencing_enabled.json');
      
      // Ensure directory exists
      final directory = Directory(storagePath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      
      final geofencingData = {'enabled': enabled};
      await geofencingFile.writeAsString(json.encode(geofencingData));
      debugPrint('Geofencing enabled state saved to storage: $enabled');
    } catch (e) {
      debugPrint('Error saving geofencing enabled state: $e');
      // Fallback to in-memory storage
    }
  }

  /// Get current location
  Future<LocationData?> getCurrentLocation() async {
    try {
      return await BackgroundLocationService().getCurrentLocation();
    } catch (e) {
      debugPrint('Error getting current location: $e');
      onError?.call('Error getting current location: $e');
      return null;
    }
  }

  /// Calculate distance from home in miles
  Future<double?> getDistanceFromHomeMiles() async {
    try {
      return await BackgroundLocationService().getDistanceFromHomeMiles();
    } catch (e) {
      debugPrint('Error calculating distance: $e');
      return null;
    }
  }

  /// Manual trigger for stove check (for testing)
  Future<void> triggerStoveCheck() async {
    await _checkStoveStatus();
  }

  /// Clear saved home location
  Future<bool> clearHomeLocation() async {
    try {
      // Get the app's storage directory using path_provider_plus
      final storagePath = await LocationUtils.getStorageDirectory();
      
      final homeLocationFile = File('$storagePath/home_location.json');
      
      if (await homeLocationFile.exists()) {
        await homeLocationFile.delete();
      }
      _homeLocation = null;
      debugPrint('Home location cleared from storage');
      return true;
    } catch (e) {
      debugPrint('Error clearing home location: $e');
      // Fallback to in-memory clearing
      _homeLocation = null;
      debugPrint('Falling back to in-memory clearing');
      return true;
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    _apiClient?.dispose();
    _isInitialized = false;
    debugPrint('GeofencingService disposed');
  }
}
