/// Configuration file for sensitive data
/// 
/// This file should be added to .gitignore to prevent
/// committing sensitive information to version control.
/// 
/// Copy this file and update with your actual values:
/// 1. Copy config.dart to config_local.dart
/// 2. Update the values in config_local.dart
/// 3. Add config_local.dart to .gitignore
library;

class AppConfig {
  // Replace with your actual cloudflared domain URL
  static const String cloudflareUrl = 'https://<your-cloudflare-domain>.com';
  
  // Replace with your actual API key
  static const String apiKey = '<your-api-key>';
  
  // Replace with the image path your server expects
  static const String hardcodedImagePath = '<your-image-path>';
  
  // Optional: Add other configuration here
  static const int requestTimeoutSeconds = 30;
  static const bool enableVerboseLogging = true;
}
