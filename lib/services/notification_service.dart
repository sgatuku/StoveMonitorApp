import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  late FlutterLocalNotificationsPlugin _notifications;
  bool _isInitialized = false;

  /// Initialize the notification service
  Future<bool> initialize() async {
    try {
      _notifications = FlutterLocalNotificationsPlugin();

      // Initialize timezone data
      // Timezone initialization removed for production

      // Android initialization settings
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS initialization settings
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      // Linux initialization settings
      const linuxSettings = LinuxInitializationSettings(
        defaultActionName: 'Open notification',
      );

      // Combined initialization settings
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
        linux: linuxSettings,
      );

      // Initialize notifications
      final result = await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      if (result == true) {
        // Request permissions for iOS
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          await _notifications
              .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(
                alert: true,
                badge: true,
                sound: true,
              );
        }

        // Request permissions for Android 13+
        if (defaultTargetPlatform == TargetPlatform.android) {
          final androidImplementation = _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
          await androidImplementation?.requestNotificationsPermission();
        }

        _isInitialized = true;
        debugPrint('NotificationService initialized successfully');
        return true;
      } else {
        debugPrint('Failed to initialize NotificationService');
        return false;
      }
    } catch (e) {
      debugPrint('Error initializing NotificationService: $e');
      return false;
    }
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
    // Handle notification tap here
  }

  /// Show notification when stove is detected as on
  Future<void> showStoveOnNotification({
    required int onKnobs,
    required int totalKnobs,
  }) async {
    try {
      if (!_isInitialized) {
        debugPrint('NotificationService not initialized');
        return;
      }

      const androidDetails = AndroidNotificationDetails(
        'stove_monitor',
        'Stove Monitor',
        channelDescription: 'Notifications for stove monitoring',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        playSound: true,
        styleInformation: BigTextStyleInformation(
          'Your stove is still ON! Please check your stove immediately for safety.',
          contentTitle: '⚠️ Stove Alert',
          htmlFormatBigText: true,
        ),
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: 'stove_alert',
      );

      const linuxDetails = LinuxNotificationDetails();

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        linux: linuxDetails,
      );

      await _notifications.show(
        1, // Unique ID for stove notifications
        '⚠️ Stove Alert',
        'Your stove is still ON! $onKnobs out of $totalKnobs knobs are turned on.',
        notificationDetails,
        payload: 'stove_on',
      );

      debugPrint('Stove on notification shown');
    } catch (e) {
      debugPrint('Error showing stove notification: $e');
    }
  }

  /// Show notification for any stove detection result (on/off/failed)
  Future<void> showStoveStatusNotification({
    required bool stoveIsOn,
    required int onKnobs,
    required int totalKnobs,
    String? errorMessage,
  }) async {
    try {
      if (!_isInitialized) {
        debugPrint('NotificationService not initialized');
        return;
      }

      String title;
      String body;
      String payload;
      Importance importance;
      Priority priority;
      bool enableVibration = false;
      bool playSound = false;

      if (errorMessage != null) {
        // Detection failed
        title = '❌ Stove Detection Failed';
        body = 'Unable to check stove status: $errorMessage';
        payload = 'stove_detection_failed';
        importance = Importance.defaultImportance;
        priority = Priority.defaultPriority;
      } else if (stoveIsOn) {
        // Stove is on
        title = '⚠️ Stove is ON';
        body = 'Your stove is ON! $onKnobs out of $totalKnobs knobs are turned on.';
        payload = 'stove_on';
        importance = Importance.high;
        priority = Priority.high;
        enableVibration = true;
        playSound = true;
      } else {
        // Stove is off
        title = '✅ Stove is OFF';
        body = 'Your stove is OFF. All $totalKnobs knobs are turned off.';
        payload = 'stove_off';
        importance = Importance.defaultImportance;
        priority = Priority.defaultPriority;
      }

      final androidDetails = AndroidNotificationDetails(
        'stove_monitor',
        'Stove Monitor',
        channelDescription: 'Notifications for stove monitoring',
        importance: importance,
        priority: priority,
        icon: '@mipmap/ic_launcher',
        enableVibration: enableVibration,
        playSound: playSound,
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          htmlFormatBigText: true,
        ),
      );

      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: playSound,
        categoryIdentifier: stoveIsOn ? 'stove_alert' : 'stove_status',
      );

      const linuxDetails = LinuxNotificationDetails();

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        linux: linuxDetails,
      );

      await _notifications.show(
        9, // Unique ID for general stove status notifications
        title,
        body,
        notificationDetails,
        payload: payload,
      );

      debugPrint('Stove status notification shown: $title');
    } catch (e) {
      debugPrint('Error showing stove status notification: $e');
    }
  }

  /// Show notification when geofencing is set up
  Future<void> showGeofencingSetupNotification() async {
    try {
      if (!_isInitialized) return;

      const androidDetails = AndroidNotificationDetails(
        'stove_monitor',
        'Stove Monitor',
        channelDescription: 'Notifications for stove monitoring',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const linuxDetails = LinuxNotificationDetails();

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        linux: linuxDetails,
      );

      await _notifications.show(
        2,
        '📍 Geofencing Enabled',
        'Stove monitoring is now active. We\'ll check your stove when you leave home.',
        notificationDetails,
        payload: 'geofencing_enabled',
      );

      debugPrint('Geofencing setup notification shown');
    } catch (e) {
      debugPrint('Error showing setup notification: $e');
    }
  }

  /// Show notification when geofencing is disabled
  Future<void> showGeofencingDisabledNotification() async {
    try {
      if (!_isInitialized) return;

      const androidDetails = AndroidNotificationDetails(
        'stove_monitor',
        'Stove Monitor',
        channelDescription: 'Notifications for stove monitoring',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const linuxDetails = LinuxNotificationDetails();

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        linux: linuxDetails,
      );

      await _notifications.show(
        3,
        '📍 Geofencing Disabled',
        'Stove monitoring has been disabled. You can enable it again in settings.',
        notificationDetails,
        payload: 'geofencing_disabled',
      );

      debugPrint('Geofencing disabled notification shown');
    } catch (e) {
      debugPrint('Error showing disabled notification: $e');
    }
  }

  /// Show notification when home location is set
  Future<void> showHomeLocationSetNotification() async {
    try {
      if (!_isInitialized) return;

      const androidDetails = AndroidNotificationDetails(
        'stove_monitor',
        'Stove Monitor',
        channelDescription: 'Notifications for stove monitoring',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const linuxDetails = LinuxNotificationDetails();

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        linux: linuxDetails,
      );

      await _notifications.show(
        4,
        '🏠 Home Location Set',
        'Your home location has been saved. Geofencing is now ready to use.',
        notificationDetails,
        payload: 'home_location_set',
      );

      debugPrint('Home location set notification shown');
    } catch (e) {
      debugPrint('Error showing home location notification: $e');
    }
  }

  /// Show notification when user leaves home
  Future<void> showLeftHomeNotification() async {
    try {
      if (!_isInitialized) return;

      const androidDetails = AndroidNotificationDetails(
        'stove_monitor',
        'Stove Monitor',
        channelDescription: 'Notifications for stove monitoring',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const linuxDetails = LinuxNotificationDetails();

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        linux: linuxDetails,
      );

      await _notifications.show(
        5,
        '🚶 Left Home',
        'You\'ve left home. Checking your stove status now...',
        notificationDetails,
        payload: 'left_home',
      );

      debugPrint('Left home notification shown');
    } catch (e) {
      debugPrint('Error showing left home notification: $e');
    }
  }

  /// Show notification when user returns home
  Future<void> showReturnedHomeNotification() async {
    try {
      if (!_isInitialized) return;

      const androidDetails = AndroidNotificationDetails(
        'stove_monitor',
        'Stove Monitor',
        channelDescription: 'Notifications for stove monitoring',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const linuxDetails = LinuxNotificationDetails();

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        linux: linuxDetails,
      );

      await _notifications.show(
        6,
        '🏠 Returned Home',
        'Welcome back! Background monitoring is active.',
        notificationDetails,
        payload: 'returned_home',
      );

      debugPrint('Returned home notification shown');
    } catch (e) {
      debugPrint('Error showing returned home notification: $e');
    }
  }

  /// Show notification when background monitoring starts
  Future<void> showBackgroundMonitoringStartedNotification() async {
    try {
      if (!_isInitialized) return;

      const androidDetails = AndroidNotificationDetails(
        'stove_monitor',
        'Stove Monitor',
        channelDescription: 'Notifications for stove monitoring',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const linuxDetails = LinuxNotificationDetails();

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        linux: linuxDetails,
      );

      await _notifications.show(
        7,
        '🔄 Background Monitoring Started',
        'Location monitoring is now active in the background.',
        notificationDetails,
        payload: 'background_started',
      );

      debugPrint('Background monitoring started notification shown');
    } catch (e) {
      debugPrint('Error showing background monitoring started notification: $e');
    }
  }

  /// Show notification when background monitoring stops
  Future<void> showBackgroundMonitoringStoppedNotification() async {
    try {
      if (!_isInitialized) return;

      const androidDetails = AndroidNotificationDetails(
        'stove_monitor',
        'Stove Monitor',
        channelDescription: 'Notifications for stove monitoring',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const linuxDetails = LinuxNotificationDetails();

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        linux: linuxDetails,
      );

      await _notifications.show(
        8,
        '⏹️ Background Monitoring Stopped',
        'Location monitoring has been disabled.',
        notificationDetails,
        payload: 'background_stopped',
      );

      debugPrint('Background monitoring stopped notification shown');
    } catch (e) {
      debugPrint('Error showing background monitoring stopped notification: $e');
    }
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    try {
      await _notifications.cancelAll();
      debugPrint('All notifications cancelled');
    } catch (e) {
      debugPrint('Error cancelling notifications: $e');
    }
  }

  /// Cancel specific notification
  Future<void> cancelNotification(int id) async {
    try {
      await _notifications.cancel(id);
      debugPrint('Notification $id cancelled');
    } catch (e) {
      debugPrint('Error cancelling notification $id: $e');
    }
  }

  /// Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    try {
      if (!_isInitialized) return false;

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidImplementation = _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        return await androidImplementation?.areNotificationsEnabled() ?? false;
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // For iOS, assume notifications are enabled if initialized
        // In a production app, you might want to use platform channels for more detailed permission checking
        return _isInitialized;
      }

      return _isInitialized;
    } catch (e) {
      debugPrint('Error checking notification status: $e');
      return false;
    }
  }
}