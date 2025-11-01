import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:location/location.dart';
import 'api/rest_api.dart';
import 'config_local.dart';
import 'services/geofencing_service.dart';
import 'services/notification_service.dart';
import 'services/background_location_service.dart';
import 'services/location_utils.dart';

void main() {
  runApp(const StoveMonitorApp());
}

class StoveMonitorApp extends StatelessWidget {
  const StoveMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stove Monitor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: const StoveMonitorHomePage(),
    );
  }
}

class StoveMonitorHomePage extends StatefulWidget {
  const StoveMonitorHomePage({super.key});

  @override
  State<StoveMonitorHomePage> createState() => _StoveMonitorHomePageState();
}

class _StoveMonitorHomePageState extends State<StoveMonitorHomePage> {
  // Configuration loaded from config_local.dart

  late StoveDetectionClient _apiClient;
  late GeofencingService _geofencingService;
  bool _isLoading = false;
  String _statusMessage = 'Ready to check stove status';
  DetectResponse? _lastDetection;
  String? _errorMessage;
  
  // Geofencing state
  bool _isGeofencingEnabled = false;
  bool _isNearHome = true;
  LocationData? _homeLocation;
  LocationData? _currentLocation;
  bool _isSettingHomeLocation = false;
  
  // Loading states
  bool _isInitializingGeofencing = true;
  String _initializationStatus = 'Initializing geofencing...';

  @override
  void initState() {
    super.initState();
    _apiClient = StoveDetectionClient(
      baseUrl: AppConfig.cloudflareUrl,
      apiKey: AppConfig.apiKey,
    );
    _geofencingService = GeofencingService();
    // Initialize geofencing asynchronously to avoid blocking UI
    _initializeGeofencingAsync();
  }

  @override
  void dispose() {
    _apiClient.dispose();
    _geofencingService.dispose();
    super.dispose();
  }

  Future<void> _initializeGeofencingAsync() async {
    try {
      setState(() {
        _initializationStatus = 'Initializing geofencing service...';
      });

      final success = await _geofencingService.initialize(
        apiBaseUrl: AppConfig.cloudflareUrl,
        apiKey: AppConfig.apiKey,
      );

      if (success) {
        setState(() {
          _initializationStatus = 'Setting up callbacks...';
        });

        // Set up callbacks
        _geofencingService.onStoveDetected = _onStoveDetected;
        _geofencingService.onError = _onGeofencingError;

        setState(() {
          _initializationStatus = 'Loading geofencing settings...';
        });

        // Wait for settings to be loaded (with timeout)
        debugPrint('UI: Waiting for settings to load...');
        int attempts = 0;
        while (!_geofencingService.settingsLoaded && attempts < 100) { // 5 second timeout
          await Future.delayed(const Duration(milliseconds: 50));
          attempts++;
        }
        
        if (!_geofencingService.settingsLoaded) {
          debugPrint('UI: Settings loading timeout, proceeding anyway...');
        } else {
          debugPrint('UI: Settings loaded, updating UI state...');
        }
        
        setState(() {
          _isGeofencingEnabled = _geofencingService.isGeofencingEnabled;
          _isNearHome = _geofencingService.isNearHome;
          _homeLocation = _geofencingService.homeLocation;
        });

        setState(() {
          _initializationStatus = 'Getting current location...';
        });

        // Get current location asynchronously
        _updateCurrentLocationAsync();
      } else {
        setState(() {
          _errorMessage = 'Failed to initialize geofencing service';
          _isInitializingGeofencing = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize geofencing: $e';
        _isInitializingGeofencing = false;
      });
    }
  }

  Future<void> _updateCurrentLocationAsync() async {
    try {
      debugPrint('UI: Getting current location...');
      
      // Add timeout to location request
      final location = await BackgroundLocationService().getCurrentLocation().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('UI: Location request timed out');
          return null;
        },
      );
      
      if (location != null) {
        debugPrint('UI: Got current location: ${location.latitude}, ${location.longitude}');
        setState(() {
          _currentLocation = location;
          _initializationStatus = 'Calculating distance from home...';
        });
        
        // Calculate distance from home if home is set
        if (_homeLocation != null) {
          debugPrint('UI: Calculating distance from home...');
          final distance = await BackgroundLocationService().getDistanceFromHomeMiles().timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('UI: Distance calculation timed out');
              return null;
            },
          );
          if (distance != null) {
            debugPrint('UI: Distance from home: $distance miles');
            setState(() {
              _isNearHome = distance <= LocationUtils.homeRadiusMiles;
            });
          }
        }
      } else {
        debugPrint('UI: Failed to get current location');
      }
      
      // Mark initialization as complete
      debugPrint('UI: Marking initialization as complete');
      setState(() {
        _isInitializingGeofencing = false;
        _initializationStatus = 'Geofencing ready';
      });
    } catch (e) {
      debugPrint('UI: Error getting current location: $e');
      setState(() {
        _isInitializingGeofencing = false;
        _errorMessage = 'Error getting current location: $e';
      });
    }
  }

  void _onStoveDetected(DetectResponse detection) {
    setState(() {
      _lastDetection = detection;
      _statusMessage = detection.stoveIsOn 
          ? '⚠️ STOVE IS ON! (Detected via geofencing)' 
          : '✅ Stove is off (Detected via geofencing)';
    });
  }

  void _onGeofencingError(String error) {
    setState(() {
      _errorMessage = 'Geofencing error: $error';
    });
  }

  Future<void> _setHomeLocation() async {
    setState(() {
      _isSettingHomeLocation = true;
      _errorMessage = null;
    });

    try {
      // Get current location
      final location = await _geofencingService.getCurrentLocation();
      if (location != null) {
        final success = await _geofencingService.setHomeLocation(location);
        if (success) {
          setState(() {
            _homeLocation = location;
            _currentLocation = location;
          });
          await NotificationService().showHomeLocationSetNotification();
        } else {
          setState(() {
            _errorMessage = 'Failed to set home location';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Could not get current location. Please ensure location permissions are granted.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error setting home location: $e';
      });
    } finally {
      setState(() {
        _isSettingHomeLocation = false;
      });
    }
  }

  Future<void> _clearHomeLocation() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await _geofencingService.clearHomeLocation();
      if (success) {
        setState(() {
          _homeLocation = null;
        });
        setState(() {
          _statusMessage = 'Home location cleared. Set a new home location to enable geofencing.';
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to clear home location';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error clearing home location: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleGeofencing(bool enabled) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await _geofencingService.setGeofencingEnabled(enabled);
      if (success) {
        setState(() {
          _isGeofencingEnabled = enabled;
        });
        
        if (enabled) {
          await NotificationService().showGeofencingSetupNotification();
        } else {
          await NotificationService().showGeofencingDisabledNotification();
        }
      } else {
        setState(() {
          _errorMessage = 'Failed to ${enabled ? 'enable' : 'disable'} geofencing';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error toggling geofencing: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }



  Future<void> _checkStoveStatus() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = 'Taking camera image and checking stove status...';
    });

    try {
      final result = await _apiClient.detectStoveWithCameraSafe();

      if (result.isSuccess && result.data != null) {
        setState(() {
          _lastDetection = result.data;
          _statusMessage = result.data!.stoveIsOn 
              ? '⚠️ STOVE IS ON!' 
              : '✅ Stove is off';
        });
        
        // Show notification for all stove detection results
        await NotificationService().showStoveStatusNotification(
          stoveIsOn: result.data!.stoveIsOn,
          onKnobs: result.data!.summary.onKnobs,
          totalKnobs: result.data!.summary.totalKnobs,
        );
      } else {
        setState(() {
          _errorMessage = result.error ?? 'Unknown error occurred';
          _statusMessage = 'Error checking stove status';
        });
        
        // Show notification for failed detection
        await NotificationService().showStoveStatusNotification(
          stoveIsOn: false,
          onKnobs: 0,
          totalKnobs: 0,
          errorMessage: result.error ?? 'Unknown error occurred',
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _statusMessage = 'Error checking stove status';
      });
      
      // Show notification for exception
      await NotificationService().showStoveStatusNotification(
        stoveIsOn: false,
        onKnobs: 0,
        totalKnobs: 0,
        errorMessage: e.toString(),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildCroppedImageWidget(CroppedImage croppedImage, int index) {
    try {
      final bytes = base64Decode(croppedImage.data);
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                child: Image.memory(
                  Uint8List.fromList(bytes),
                  fit: BoxFit.contain,
                  width: double.infinity,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey.shade200,
                      child: const Icon(
                        Icons.error,
                        color: Colors.red,
                        size: 32,
                      ),
                    );
                  },
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
              ),
              child: Text(
                'Knob ${index + 1}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.red.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error,
              color: Colors.red,
              size: 32,
            ),
            const SizedBox(height: 4),
            Text(
              'Knob ${index + 1}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              'Decode Error',
              style: TextStyle(
                fontSize: 10,
                color: Colors.red.shade600,
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Stove Monitor'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status Icon
            Icon(
              _lastDetection?.stoveIsOn == true 
                  ? Icons.warning 
                  : Icons.check_circle,
              size: 80,
              color: _lastDetection?.stoveIsOn == true 
                  ? Colors.red 
                  : Colors.green,
            ),
            
            const SizedBox(height: 20),
            
            // Status Message
            Text(
              _statusMessage,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 20),
            
            // Geofencing Status Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isInitializingGeofencing 
                    ? Colors.blue.shade50 
                    : (_isGeofencingEnabled ? Colors.green.shade50 : Colors.grey.shade50),
                border: Border.all(
                  color: _isInitializingGeofencing 
                      ? Colors.blue.shade200 
                      : (_isGeofencingEnabled ? Colors.green.shade200 : Colors.grey.shade200),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (_isInitializingGeofencing) ...[
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Geofencing Status',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          'Loading...',
                          style: TextStyle(
                            color: Colors.blue.shade600,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ] else ...[
                        Icon(
                          _isGeofencingEnabled ? Icons.location_on : Icons.location_off,
                          color: _isGeofencingEnabled ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Geofencing Status',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        Switch(
                          value: _isGeofencingEnabled,
                          onChanged: _isLoading ? null : _toggleGeofencing,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_isInitializingGeofencing) ...[
                    Text(
                      _initializationStatus,
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ] else ...[
                    Text(
                      _isGeofencingEnabled 
                          ? 'Monitoring enabled - Will check stove when you leave home'
                          : 'Monitoring disabled - Manual checks only',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (_homeLocation != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Home: ${_homeLocation!.latitude!.toStringAsFixed(4)}, ${_homeLocation!.longitude!.toStringAsFixed(4)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          TextButton(
                            onPressed: _isLoading ? null : _clearHomeLocation,
                            child: Text(
                              'Clear',
                              style: TextStyle(
                                color: Colors.red.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_currentLocation != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Current: ${_currentLocation!.latitude!.toStringAsFixed(4)}, ${_currentLocation!.longitude!.toStringAsFixed(4)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isNearHome ? '📍 At home' : '🚶 Away from home',
                        style: TextStyle(
                          color: _isNearHome ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Home Location Setup
            if (_homeLocation == null && !_isInitializingGeofencing) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  border: Border.all(color: Colors.blue.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.home,
                      size: 32,
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Set Home Location',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Set your current location as home to enable automatic stove monitoring',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSettingHomeLocation ? null : _setHomeLocation,
                        icon: _isSettingHomeLocation 
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location),
                        label: Text(_isSettingHomeLocation ? 'Setting...' : 'Set as Home'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // Error Message (if any)
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade700),
                  textAlign: TextAlign.center,
                ),
              ),
            
            const SizedBox(height: 30),
            
            // Detection Details (if available)
            if (_lastDetection != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Detection Details:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('Total Knobs: ${_lastDetection!.summary.totalKnobs}'),
                    Text('On Knobs: ${_lastDetection!.summary.onKnobs}'),
                    Text('Off Knobs: ${_lastDetection!.summary.offKnobs}'),
                    if (_lastDetection!.summary.errorKnobs > 0)
                      Text('Error Knobs: ${_lastDetection!.summary.errorKnobs}'),
                    const SizedBox(height: 8),
                    Text(
                      'Timestamp: ${_lastDetection!.timestamp}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              
              // Cropped Images Display (if available)
              if (_lastDetection!.croppedImages != null && _lastDetection!.croppedImages!.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stove Knob Cropped Images:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 1,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 1.2,
                        ),
                        itemCount: _lastDetection!.croppedImages!.length,
                        itemBuilder: (context, index) {
                          final croppedImage = _lastDetection!.croppedImages![index];
                          return _buildCroppedImageWidget(croppedImage, index);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ],
            
            // Check Button
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _checkStoveStatus,
                icon: _isLoading 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_isLoading ? 'Checking...' : 'Check Stove Status'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _lastDetection?.stoveIsOn == true 
                      ? Colors.red 
                      : Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Settings'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Configuration Info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border.all(color: Colors.blue.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Configuration',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildConfigItem('Server URL', AppConfig.cloudflareUrl),
                  _buildConfigItem('Mode', 'Live Camera Capture'),
                  _buildConfigItem('API Key', '${AppConfig.apiKey.substring(0, 8)}...'),
                  _buildConfigItem('Geofencing Radius', '${LocationUtils.homeRadiusMiles} miles'),
                  const SizedBox(height: 8),
                  Text(
                    'Note: Configuration is loaded from config_local.dart',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // App Information
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.apps,
                        color: Colors.grey.shade700,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'App Information',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildConfigItem('Version', '1.0.0'),
                  _buildConfigItem('Platform', 'Flutter'),
                  _buildConfigItem('Build Type', 'Production'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}