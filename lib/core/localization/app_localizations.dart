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
