import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  static const supportedLocales = [Locale('en'), Locale('ar')];

  static const localizationsDelegates = <LocalizationsDelegate>[
    _AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  String tr(String key) =>
      _strings[locale.languageCode]?[key] ?? _strings['en']![key] ?? key;

  // ignore: unused_element
  static const Map<String, Map<String, String>> _strings = {
    'en': {
      // Common
      'app_name': 'CARDIAG',
      'cancel': 'Cancel',
      'ok': 'OK',
      'retry': 'Retry',
      'please_wait': 'Please wait...',
      'back': 'Back',
      'save': 'Save',
      'edit': 'Edit',

      // Bottom nav
      'home': 'Home',
      'scan': 'Scan',
      'smart_key': 'Smart Key',
      'history': 'History',
      'settings': 'Settings',

      // Splash
      'vehicle_diagnostics': 'VEHICLE DIAGNOSTICS',
      'initializing': 'INITIALIZING...',

      // Auth
      'welcome_back': 'Welcome Back',
      'join_cardiag': 'Join CARDIAG',
      'login_tab': 'LOGIN',
      'signup_tab': 'SIGN UP',
      'email': 'Email',
      'password': 'Password',
      'confirm_password': 'Confirm Password',
      'full_name': 'Full Name',
      'forgot_password': 'Forgot Password?',
      'already_have_account': 'Already have an account?',
      'dont_have_account': "Don't have an account?",
      'enter_email': 'Enter your email',
      'enter_password': 'Enter your password',
      'enter_full_name': 'Enter your full name',
      'confirm_your_password': 'Confirm your password',
      'invalid_credentials': 'Invalid email or password',

      // Connection
      'connect_to_vehicle': 'Connect to Vehicle',
      'select_obd_adapter': 'SELECT OBD-II ADAPTER',
      'checking_permissions': 'Checking permissions...',
      'bt_permission_required': 'Bluetooth permission required',
      'please_turn_on_bt': 'Please turn on Bluetooth',
      'searching_devices': 'Searching for devices...',
      'connecting_to': 'Connecting to',
      'connected_to': 'Connected to',
      'connection_failed': 'Connection failed. Tap a device to retry.',
      'unknown_device': 'Unknown Device',
      'available_devices': 'AVAILABLE DEVICES',
      'no_devices_found': 'No devices found yet...',
      'go_to_settings_bt': 'Go to Settings to grant Bluetooth access',
      'enable_bluetooth': 'Enable Bluetooth in your device settings',
      'location_services_required': 'Location Services Required',
      'location_services_required_sub': 'Enable Location Services in Settings — Android needs it to scan Bluetooth devices',
      'devices_found_nearby': 'device(s) found nearby',
      'tap_scan_vehicle': 'Tap SCAN VEHICLE to proceed',
      'scan_vehicle': 'SCAN VEHICLE',
      'btn_scanning': 'SCANNING...',
      'btn_connecting': 'CONNECTING...',
      'open_settings_btn': 'OPEN SETTINGS',
      'btn_retry': 'RETRY',
      'btn_please_wait': 'PLEASE WAIT',
      'tap_to_rescan': 'Tap to rescan',
      'trouble_connecting':
          'Having trouble connecting? Check our troubleshooting guide',
      'initializing_obd': 'Initializing ELM327...',
      'obd_init_failed': 'OBD Initialization Failed',
      'obd_init_failed_sub': 'Device may not be ELM327 compatible. Tap RETRY to scan again.',
      'btn_initializing': 'INITIALIZING...',

      // Dashboard
      'vehicle_health': 'Vehicle Health',
      'overall_health': 'Overall Health',
      'engine': 'Engine',
      'battery': 'Battery',
      'brakes': 'Brakes',
      'warning_lights': 'Warning Lights',
      'recent_scans': 'Recent Scans',
      'no_scans_yet': 'No scans yet. Run a diagnostic to see results here.',
      'connected': 'Connected',
      'disconnected': 'Disconnected',
      'quick_scan': 'Quick Scan',
      'run_diagnostics': 'Run a quick vehicle diagnostic',
      'codes_detected': 'codes detected',
      'no_issues_found': 'No issues found',
      'code_detected': 'code detected',
      'video_tutorials': 'Video Tutorials',
      'learn_to_fix': 'Learn how to fix your car issues',
      'watch_now': 'Watch Now',
      'check_engine': 'Check Engine',
      'oil': 'Oil',
      'abs': 'ABS',
      'airbag': 'Airbag',
      'temp': 'Temp',
      'fuel': 'Fuel',
      'exhaust': 'Exhaust',
      'misfire': 'Misfire',
      'o2_sensor': 'O2 Sensor',
      'fuel_trim': 'Fuel Trim',
      'injector': 'Injector',
      'maf_sensor': 'MAF',
      'network': 'Network',
      'service': 'Service',
      'traction': 'Traction',
      'steering': 'Steering',
      'egr': 'EGR',
      'throttle': 'Throttle',
      'fuel_pressure': 'Fuel Press',
      'mil': 'MIL',
      'body': 'Body',

      // Diagnostic Codes
      'diagnostic_codes': 'Diagnostic Codes',
      'all': 'All',
      'transmission': 'Transmission',
      'severity_critical': 'Critical',
      'severity_warning': 'Warning',
      'severity_info': 'Info',
      'view_solution': 'View Solution',
      'no_codes_found': 'No codes found',

      // Smart Key
      'smart_key_title': 'Smart Key',
      'vehicle_status': 'Vehicle Status',
      'locked': 'Locked',
      'unlocked': 'Unlocked',
      'lock': 'Lock',
      'unlock': 'Unlock',
      'engine_off': 'Engine Off',
      'engine_on': 'Engine On',
      'start_engine': 'Start Engine',
      'stop_engine': 'Stop Engine',
      'trunk': 'Trunk',
      'open_trunk': 'Open Trunk',
      'panic': 'Panic',
      'remote_start': 'Remote Start',
      'climate_control': 'Climate Control',
      'find_car': 'Find Car',
      'last_location': 'Last known location',

      // History
      'history_title': 'Scan History',
      'no_history': 'No scan history',
      'view_codes': 'View Codes',
      'scan_again': 'Scan Again',

      // Settings
      'settings_title': 'Settings',
      'general': 'General',
      'notifications': 'Notifications',
      'notifications_sub': 'Receive alerts for diagnostic issues',
      'auto_scan': 'Auto-Scan',
      'auto_scan_sub': 'Automatically scan on connection',
      'dark_mode': 'Dark Mode',
      'dark_mode_sub': 'Use dark theme',
      'sound_effects': 'Sound Effects',
      'sound_effects_sub': 'Play sounds for actions',
      'dash_cam': 'Dash Cam',
      'dash_cam_sub': 'Record video while driving',
      'preferences': 'Preferences',
      'language': 'Language',
      'units': 'Units',
      'vehicle_profile': 'Vehicle Profile',
      'vehicle_profile_sub': 'Manage your vehicles',
      'data_privacy': 'Data & Privacy',
      'data_privacy_sub': 'Manage your data preferences',
      'about': 'About',
      'app_version': 'App Version',
      'terms_of_service': 'Terms of Service',
      'terms_sub': 'View terms and conditions',
      'privacy_policy': 'Privacy Policy',
      'privacy_sub': 'How we protect your data',
      'support': 'Support',
      'support_sub': 'Get help and contact us',
      'danger_zone': 'Danger Zone',
      'logout': 'Logout',
      'logout_confirm': 'Logout?',
      'logout_confirm_msg': 'Are you sure you want to logout?',
      'select': 'Select',
      'dtc_lookup': 'DTC Code Lookup',
      'dtc_lookup_sub': 'Search any OBD-II fault code',

      // Dashboard - OBD connection banner
      'obd_not_connected': 'OBD Not Connected',
      'tap_to_connect': 'Tap to connect Bluetooth OBD adapter',
      'press_back_to_exit': 'Press back again to exit',

      // Dash cam settings screen
      'dash_cam_settings': 'Dash Cam Settings',
      'dash_cam_settings_sub': 'Configure recording options',
      'video_quality': 'Video Quality',
      'video_quality_sub': 'Resolution of recorded clips',
      'loop_recording': 'Loop Recording',
      'loop_recording_sub': 'Overwrite oldest clips when storage is full',
      'auto_start_recording': 'Auto-Start Recording',
      'auto_start_sub': 'Begin recording when app opens',
      'incident_detection': 'Incident Detection',
      'incident_detection_sub': 'Save clip automatically on sudden stop',

      // DTC Lookup page
      'dtc_lookup_title': 'DTC Lookup',
      'dtc_enter_code_hint': 'Enter DTC code (e.g. P0300)',
      'dtc_get_description': 'Get Description',
      'dtc_description_label': 'Description:',
      'dtc_enter_code_error': 'Please enter a DTC code.',
      'dtc_no_description_prefix': 'No description found for code',
      'dtc_fetch_failed': 'Failed to fetch description. Please try again.',

      // Exit app dialog
      'exit_app': 'Exit App',
      'exit_app_confirm': 'Are you sure you want to exit?',
      'exit': 'Exit',

      // Live data graph
      'live_data_graph': 'Live Data Graph',
      'live_data': 'Live Data',
      'select_channel': 'Select at least one channel',

      // History screen
      'no_scan_history_yet': 'No scan history yet',
      'run_scan_to_log': 'Run a diagnostic scan to start logging.',
      'clear_history': 'Clear History?',
      'clear_history_content': 'All scan records will be deleted permanently.',
      'clear_all': 'Clear All',
      'total_scans': 'Total Scans',
      'with_codes': 'With Codes',
      'clean_scan': 'Clean',

      // Maintenance screen
      'maintenance_tracker': 'Maintenance Tracker',
      'current_mileage': 'Current Mileage',
      'set': 'Set',
      'log_label': 'Log',
      'confirm': 'Confirm',
      'set_current_mileage': 'Set Current Mileage',
      'mileage_km': 'Mileage (km)',
      'never_serviced': 'Never serviced',
      'status_overdue': 'OVERDUE',
      'status_due_soon': 'DUE SOON',
      'status_ok': 'OK',
      'log_service_msg_prefix': 'This will record today\'s date and',
      'log_service_msg_suffix': 'km as the last service.',

      // Mode selection screen
      'what_do_you_need': 'What do you need today?',
      'car_diagnostics': 'Car Diagnostics',
      'car_diagnostics_sub':
          'Connect via Bluetooth OBD-II adapter to read live data, fault codes and performance metrics',
      'connect_bluetooth': 'Connect Bluetooth',
      'roadside_assistance': 'Roadside Assistance',
      'roadside_assistance_sub':
          'Request a certified driver for towing, battery, tire or fuel service — anywhere, anytime',
      'request_help': 'Request Help',
      'switch_services': 'You can switch between services anytime',
      'live_engine_data': 'Live engine data & RPM',
      'fault_code_scanner': 'Fault code scanner (DTC)',
      'performance_metrics': 'Performance metrics',
      'towing_service': 'Towing & flatbed service',
      'battery_tire_repair': 'Battery & tire repair',
      'fuel_delivery': 'Fuel delivery',

      // Diagnostic codes screen
      'failed_clear_codes': 'Failed to clear codes – check adapter connection.',
      'go_to_connection': 'Go to Connection',
      'clear_codes': 'Clear Codes?',
      'clear': 'Clear',
      'failed_read_codes': 'Failed to read codes',
      'clear_codes_content':
          'This will erase all fault codes and reset the MIL lamp. '
          'Emissions readiness monitors will also reset.',

      // Dashboard screen
      'graph': 'Graph',
      'timing': 'Timing',

      // Profile screen
      'update': 'Update',
      'done': 'Done',
      'success': 'Success!',
      'profile_updated': 'Your profile has been updated successfully!',
      'drive_score': 'Drive Score',

      // Video player screen
      'like': 'Like',
      'enable_pip': 'Enable PIP',

      // Roadside screens
      'select_service_needed': 'Select the service you need',
      'avg_15_min': 'Avg. 15 min',
      'certified_drivers': 'Certified Drivers',
      'rating_48': '4.8 Rating',
      'how_was_experience': 'How was your experience?',
      'service_details': 'Service Details',
      'your_location': 'Your Location',
      'price_estimate_label': 'Price Estimate',
      'total_estimate': 'Total Estimate',
      'cash_payment': 'Cash payment on service completion',
      'photos': 'Photos',
      'add': 'Add',
      'no_photos_added': 'No photos added — tap Add to take one',
      'request_service_label': 'Request Service',
      'request_history_title': 'Request History',
      'no_requests_yet': 'No requests yet',
      'detecting_address': 'Detecting address...',
      'finding_nearest_driver': 'Finding Nearest Driver',
      'drivers_online': 'Drivers Online',
      'search_radius_label': 'Search Radius',
      'avg_arrival': 'Avg. Arrival',
    },
    'ar': {
      // Common
      'app_name': 'كارداياج',
      'cancel': 'إلغاء',
      'ok': 'حسناً',
      'retry': 'إعادة المحاولة',
      'please_wait': 'يرجى الانتظار...',
      'back': 'رجوع',
      'save': 'حفظ',
      'edit': 'تعديل',

      // Bottom nav
      'home': 'الرئيسية',
      'scan': 'فحص',
      'smart_key': 'المفتاح الذكي',
      'history': 'السجل',
      'settings': 'الإعدادات',

      // Splash
      'vehicle_diagnostics': 'تشخيص المركبات',
      'initializing': 'جارٍ التهيئة...',

      // Auth
      'welcome_back': 'مرحباً بعودتك',
      'join_cardiag': 'انضم إلى كارداياج',
      'login_tab': 'تسجيل الدخول',
      'signup_tab': 'إنشاء حساب',
      'email': 'البريد الإلكتروني',
      'password': 'كلمة المرور',
      'confirm_password': 'تأكيد كلمة المرور',
      'full_name': 'الاسم الكامل',
      'forgot_password': 'نسيت كلمة المرور؟',
      'already_have_account': 'هل لديك حساب بالفعل؟',
      'dont_have_account': 'ليس لديك حساب؟',
      'enter_email': 'أدخل بريدك الإلكتروني',
      'enter_password': 'أدخل كلمة المرور',
      'enter_full_name': 'أدخل اسمك الكامل',
      'confirm_your_password': 'أكّد كلمة المرور',
      'invalid_credentials': 'البريد الإلكتروني أو كلمة المرور غير صحيحة',

      // Connection
      'connect_to_vehicle': 'الاتصال بالمركبة',
      'select_obd_adapter': 'اختر محول OBD-II',
      'checking_permissions': 'التحقق من الأذونات...',
      'bt_permission_required': 'إذن البلوتوث مطلوب',
      'please_turn_on_bt': 'يرجى تشغيل البلوتوث',
      'searching_devices': 'البحث عن الأجهزة...',
      'connecting_to': 'جارٍ الاتصال بـ',
      'connected_to': 'متصل بـ',
      'connection_failed': 'فشل الاتصال. اضغط على الجهاز للمحاولة مجدداً.',
      'unknown_device': 'جهاز غير معروف',
      'available_devices': 'الأجهزة المتاحة',
      'no_devices_found': 'لم يتم العثور على أجهزة بعد...',
      'go_to_settings_bt': 'انتقل إلى الإعدادات لمنح الوصول إلى البلوتوث',
      'enable_bluetooth': 'تفعيل البلوتوث في إعدادات جهازك',
      'location_services_required': 'خدمات الموقع مطلوبة',
      'location_services_required_sub': 'فعّل خدمات الموقع في الإعدادات — يحتاج أندرويد إليها لمسح أجهزة البلوتوث',
      'devices_found_nearby': 'جهاز/أجهزة موجودة بالقرب',
      'tap_scan_vehicle': 'اضغط "فحص المركبة" للمتابعة',
      'scan_vehicle': 'فحص المركبة',
      'btn_scanning': 'جارٍ المسح...',
      'btn_connecting': 'جارٍ الاتصال...',
      'open_settings_btn': 'فتح الإعدادات',
      'btn_retry': 'إعادة المحاولة',
      'btn_please_wait': 'يرجى الانتظار',
      'tap_to_rescan': 'اضغط لإعادة المسح',
      'trouble_connecting':
          'تواجه مشكلة في الاتصال؟ راجع دليل استكشاف الأخطاء',
      'initializing_obd': 'جارٍ تهيئة ELM327...',
      'obd_init_failed': 'فشل تهيئة OBD',
      'obd_init_failed_sub': 'قد لا يكون الجهاز متوافقاً مع ELM327. اضغط إعادة المحاولة للمسح مجدداً.',
      'btn_initializing': 'جارٍ التهيئة...',

      // Dashboard
      'vehicle_health': 'صحة المركبة',
      'overall_health': 'الصحة العامة',
      'engine': 'المحرك',
      'battery': 'البطارية',
      'brakes': 'الفرامل',
      'warning_lights': 'أضواء التحذير',
      'recent_scans': 'عمليات الفحص الأخيرة',
      'no_scans_yet': 'لا توجد عمليات فحص بعد. قم بتشغيل تشخيص لرؤية النتائج هنا.',
      'connected': 'متصل',
      'disconnected': 'غير متصل',
      'quick_scan': 'فحص سريع',
      'run_diagnostics': 'إجراء تشخيص سريع للمركبة',
      'codes_detected': 'أكواد مكتشفة',
      'no_issues_found': 'لا توجد مشاكل',
      'code_detected': 'كود مكتشف',
      'video_tutorials': 'شروحات الفيديو',
      'learn_to_fix': 'تعلم كيف تصلح مشاكل سيارتك',
      'watch_now': 'شاهد الآن',
      'check_engine': 'فحص المحرك',
      'oil': 'الزيت',
      'abs': 'ABS',
      'airbag': 'الوسادة الهوائية',
      'temp': 'الحرارة',
      'fuel': 'الوقود',
      'exhaust': 'العادم',
      'misfire': 'اشتعال خاطئ',
      'o2_sensor': 'مستشعر O2',
      'fuel_trim': 'تعديل الوقود',
      'injector': 'الحاقن',
      'maf_sensor': 'مستشعر MAF',
      'network': 'الشبكة',
      'service': 'الصيانة',
      'traction': 'التثبيت',
      'steering': 'التوجيه',
      'egr': 'EGR',
      'throttle': 'الخانق',
      'fuel_pressure': 'ضغط الوقود',
      'mil': 'MIL',
      'body': 'الكهرباء',

      // Diagnostic Codes
      'diagnostic_codes': 'أكواد التشخيص',
      'all': 'الكل',
      'transmission': 'ناقل الحركة',
      'severity_critical': 'حرج',
      'severity_warning': 'تحذير',
      'severity_info': 'معلومة',
      'view_solution': 'عرض الحل',
      'no_codes_found': 'لم يتم العثور على أكواد',

      // Smart Key
      'smart_key_title': 'المفتاح الذكي',
      'vehicle_status': 'حالة المركبة',
      'locked': 'مقفل',
      'unlocked': 'مفتوح',
      'lock': 'قفل',
      'unlock': 'فتح',
      'engine_off': 'المحرك متوقف',
      'engine_on': 'المحرك يعمل',
      'start_engine': 'تشغيل المحرك',
      'stop_engine': 'إيقاف المحرك',
      'trunk': 'الصندوق',
      'open_trunk': 'فتح الصندوق',
      'panic': 'إنذار الطوارئ',
      'remote_start': 'تشغيل عن بُعد',
      'climate_control': 'التحكم بالمناخ',
      'find_car': 'إيجاد السيارة',
      'last_location': 'الموقع الأخير المعروف',

      // History
      'history_title': 'سجل الفحص',
      'no_history': 'لا يوجد سجل فحص',
      'view_codes': 'عرض الأكواد',
      'scan_again': 'فحص مجدداً',

      // Settings
      'settings_title': 'الإعدادات',
      'general': 'عام',
      'notifications': 'الإشعارات',
      'notifications_sub': 'تلقي تنبيهات لمشاكل التشخيص',
      'auto_scan': 'الفحص التلقائي',
      'auto_scan_sub': 'فحص تلقائي عند الاتصال',
      'dark_mode': 'الوضع الداكن',
      'dark_mode_sub': 'استخدام المظهر الداكن',
      'sound_effects': 'المؤثرات الصوتية',
      'sound_effects_sub': 'تشغيل الأصوات للإجراءات',
      'dash_cam': 'كاميرا لوحة القيادة',
      'dash_cam_sub': 'تسجيل الفيديو أثناء القيادة',
      'preferences': 'التفضيلات',
      'language': 'اللغة',
      'units': 'الوحدات',
      'vehicle_profile': 'ملف المركبة',
      'vehicle_profile_sub': 'إدارة مركباتك',
      'data_privacy': 'البيانات والخصوصية',
      'data_privacy_sub': 'إدارة تفضيلات بياناتك',
      'about': 'حول',
      'app_version': 'إصدار التطبيق',
      'terms_of_service': 'شروط الخدمة',
      'terms_sub': 'عرض الشروط والأحكام',
      'privacy_policy': 'سياسة الخصوصية',
      'privacy_sub': 'كيف نحمي بياناتك',
      'support': 'الدعم',
      'support_sub': 'احصل على مساعدة وتواصل معنا',
      'danger_zone': 'المنطقة الخطرة',
      'logout': 'تسجيل الخروج',
      'logout_confirm': 'تسجيل الخروج؟',
      'logout_confirm_msg': 'هل أنت متأكد أنك تريد تسجيل الخروج؟',
      'select': 'اختر',
      'dtc_lookup': 'بحث عن كود OBD-II',
      'dtc_lookup_sub': 'ابحث عن أي كود عطل OBD-II',

      // Dashboard - OBD connection banner
      'obd_not_connected': 'OBD غير متصل',
      'tap_to_connect': 'اضغط لتوصيل محول OBD عبر البلوتوث',
      'press_back_to_exit': 'اضغط رجوع مرة أخرى للخروج',

      // Dash cam settings screen
      'dash_cam_settings': 'إعدادات كاميرا اللوحة',
      'dash_cam_settings_sub': 'ضبط خيارات التسجيل',
      'video_quality': 'جودة الفيديو',
      'video_quality_sub': 'دقة المقاطع المسجلة',
      'loop_recording': 'التسجيل الدائري',
      'loop_recording_sub': 'استبدال أقدم المقاطع عند امتلاء التخزين',
      'auto_start_recording': 'البدء التلقائي للتسجيل',
      'auto_start_sub': 'ابدأ التسجيل عند فتح التطبيق',
      'incident_detection': 'كشف الحوادث',
      'incident_detection_sub': 'حفظ المقطع تلقائياً عند التوقف المفاجئ',

      // DTC Lookup page
      'dtc_lookup_title': 'بحث DTC',
      'dtc_enter_code_hint': 'أدخل كود DTC (مثال: P0300)',
      'dtc_get_description': 'احصل على الوصف',
      'dtc_description_label': 'الوصف:',
      'dtc_enter_code_error': 'يرجى إدخال كود DTC.',
      'dtc_no_description_prefix': 'لم يتم العثور على وصف للكود',
      'dtc_fetch_failed': 'فشل في جلب الوصف. يرجى المحاولة مجدداً.',

      // Exit app dialog
      'exit_app': 'الخروج من التطبيق',
      'exit_app_confirm': 'هل أنت متأكد أنك تريد الخروج؟',
      'exit': 'خروج',

      // Live data graph
      'live_data_graph': 'رسم البيانات الحية',
      'live_data': 'البيانات الحية',
      'select_channel': 'اختر قناة واحدة على الأقل',

      // History screen
      'no_scan_history_yet': 'لا يوجد سجل فحص بعد',
      'run_scan_to_log': 'قم بإجراء فحص تشخيصي لبدء السجل.',
      'clear_history': 'مسح السجل؟',
      'clear_history_content': 'سيتم حذف جميع سجلات الفحص بشكل دائم.',
      'clear_all': 'مسح الكل',
      'total_scans': 'إجمالي الفحوصات',
      'with_codes': 'مع أكواد',
      'clean_scan': 'نظيف',

      // Maintenance screen
      'maintenance_tracker': 'متتبع الصيانة',
      'current_mileage': 'عداد الكيلومترات الحالي',
      'set': 'تعيين',
      'log_label': 'تسجيل',
      'confirm': 'تأكيد',
      'set_current_mileage': 'تعيين عداد الكيلومترات الحالي',
      'mileage_km': 'المسافة (كم)',
      'never_serviced': 'لم يتم الصيانة من قبل',
      'status_overdue': 'متأخر',
      'status_due_soon': 'موعده قريب',
      'status_ok': 'جيد',
      'log_service_msg_prefix': 'سيسجل هذا تاريخ اليوم و',
      'log_service_msg_suffix': 'كم كآخر خدمة.',

      // Mode selection screen
      'what_do_you_need': 'ماذا تحتاج اليوم؟',
      'car_diagnostics': 'تشخيص السيارة',
      'car_diagnostics_sub':
          'اتصل عبر محول OBD-II بالبلوتوث لقراءة البيانات الحية وأكواد الأعطال ومقاييس الأداء',
      'connect_bluetooth': 'الاتصال بالبلوتوث',
      'roadside_assistance': 'المساعدة على الطريق',
      'roadside_assistance_sub':
          'اطلب سائقاً معتمداً لخدمات السحب والبطارية والإطارات أو الوقود — في أي مكان وأي وقت',
      'request_help': 'طلب مساعدة',
      'switch_services': 'يمكنك التبديل بين الخدمات في أي وقت',
      'live_engine_data': 'بيانات المحرك الحية وعدد الدورات',
      'fault_code_scanner': 'ماسح أكواد الأعطال (DTC)',
      'performance_metrics': 'مقاييس الأداء',
      'towing_service': 'خدمة السحب والمقطورة',
      'battery_tire_repair': 'إصلاح البطارية والإطارات',
      'fuel_delivery': 'توصيل الوقود',

      // Diagnostic codes screen
      'failed_clear_codes': 'فشل في مسح الأكواد – تحقق من اتصال المحول.',
      'go_to_connection': 'الانتقال إلى الاتصال',
      'clear_codes': 'مسح الأكواد؟',
      'clear': 'مسح',
      'failed_read_codes': 'فشل في قراءة الأكواد',
      'clear_codes_content':
          'سيؤدي هذا إلى مسح جميع أكواد الأعطال وإعادة تعيين مصباح MIL. '
          'ستتم إعادة تعيين مراقبات جاهزية الانبعاثات أيضاً.',

      // Dashboard screen
      'graph': 'رسم بياني',
      'timing': 'التوقيت',

      // Profile screen
      'update': 'تحديث',
      'done': 'تم',
      'success': 'تم بنجاح!',
      'profile_updated': 'تم تحديث ملفك الشخصي بنجاح!',
      'drive_score': 'نقاط القيادة',

      // Video player screen
      'like': 'إعجاب',
      'enable_pip': 'تفعيل PIP',

      // Roadside screens
      'select_service_needed': 'اختر الخدمة التي تحتاجها',
      'avg_15_min': 'متوسط 15 دقيقة',
      'certified_drivers': 'سائقون معتمدون',
      'rating_48': 'تقييم 4.8',
      'how_was_experience': 'كيف كانت تجربتك؟',
      'service_details': 'تفاصيل الخدمة',
      'your_location': 'موقعك',
      'price_estimate_label': 'تقدير السعر',
      'total_estimate': 'الإجمالي المقدر',
      'cash_payment': 'الدفع نقداً عند اكتمال الخدمة',
      'photos': 'الصور',
      'add': 'إضافة',
      'no_photos_added': 'لم تُضف صور — اضغط "إضافة" لالتقاط صورة',
      'request_service_label': 'طلب الخدمة',
      'request_history_title': 'سجل الطلبات',
      'no_requests_yet': 'لا توجد طلبات بعد',
      'detecting_address': 'جارٍ تحديد العنوان...',
      'finding_nearest_driver': 'البحث عن أقرب سائق',
      'drivers_online': 'سائقون متصلون',
      'search_radius_label': 'نطاق البحث',
      'avg_arrival': 'متوسط وقت الوصول',
    },
  };
}

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  String tr(String key) => AppLocalizations.of(this).tr(key);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'ar'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(locale));

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}
