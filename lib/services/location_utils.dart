import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:location/location.dart';
import 'package:path_provider/path_provider.dart';

/// Shared utilities for location calculations and constants
class LocationUtils {
  // Home radius configuration - single source of truth
  static const double homeRadiusMiles = 0.2;
  static const double homeRadiusMeters = homeRadiusMiles * 1609.34; // Convert miles to meters
  
  /// Calculate distance between two points using Haversine formula
  /// Returns distance in meters
  static double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth's radius in meters
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * asin(sqrt(a));
    return earthRadius * c;
  }
  
  /// Convert degrees to radians
  static double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }
  
  /// Check if a location is near home
  static bool isLocationNearHome(LocationData homeLocation, LocationData currentLocation) {
    if (homeLocation.latitude == null || 
        homeLocation.longitude == null ||
        currentLocation.latitude == null || 
        currentLocation.longitude == null) {
      return false;
    }

    final distance = calculateDistance(
      homeLocation.latitude!,
      homeLocation.longitude!,
      currentLocation.latitude!,
      currentLocation.longitude!,
    );

    return distance <= homeRadiusMeters;
  }
  
  /// Calculate distance from home in miles
  static double? getDistanceFromHomeMiles(LocationData homeLocation, LocationData currentLocation) {
    if (homeLocation.latitude == null || 
        homeLocation.longitude == null ||
        currentLocation.latitude == null || 
        currentLocation.longitude == null) {
      return null;
    }
    
    final distanceMeters = calculateDistance(
      homeLocation.latitude!,
      homeLocation.longitude!,
      currentLocation.latitude!,
      currentLocation.longitude!,
    );
    
    return distanceMeters / 1609.34; // Convert to miles
  }
  
  /// Get the storage directory for persisting app data
  /// This works on both iOS and Android by using the appropriate application directory
  static Future<String> getStorageDirectory() async {
    try {
      if (kIsWeb) {
        // For web, use current directory
        return Directory.current.path;
      }
      
      // Get the application documents directory
      final directory = await getApplicationDocumentsDirectory();
      return directory.path;
    } catch (e) {
      debugPrint('Error getting storage directory: $e');
      // Fallback to current directory
      return Directory.current.path;
    }
  }
}
