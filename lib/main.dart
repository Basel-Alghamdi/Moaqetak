import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'travel_time_service.dart';
import 'package:geolocator/geolocator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  bool inited = false;
  // Try with explicit options first
  try {
    if (Firebase.apps.isEmpty) {
      final opts = DefaultFirebaseOptions.maybeCurrentPlatform;
      if (opts != null) {
        await Firebase.initializeApp(options: opts);
      }
    }
    inited = Firebase.apps.isNotEmpty;
  } catch (_) {
    // Fallback: try default init (uses google-services/plist if present)
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      inited = Firebase.apps.isNotEmpty;
    } catch (_) {
      inited = false;
    }
  }

  if (inited) {
    try { await FirebaseAuth.instance.setLanguageCode('ar'); } catch (_) {}
  }
  runApp(const MowaqetakApp());
}

class MowaqetakApp extends StatelessWidget {
  const MowaqetakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality( // تأكيد RTL حتى بدون إعدادات محلية
      textDirection: TextDirection.rtl,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'مؤقتك',
        themeMode: ThemeMode.dark,
        theme: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF3B82F6),
            surface: Color(0xFF151922),
            secondary: Color(0xFF1B2130),
          ),
          scaffoldBackgroundColor: const Color(0xFF0F1115),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          cardColor: const Color(0xFF151922),
          textSelectionTheme: const TextSelectionThemeData(
            cursorColor: Color(0xFF3B82F6),
            selectionColor: Color(0x553B82F6),
            selectionHandleColor: Color(0xFF3B82F6),
          ),
          // Keep default text sizes to avoid apply() assertion on null fontSize
          textTheme: ThemeData.dark().textTheme,
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF111827),
            hintStyle: const TextStyle(color: Colors.white30),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF2A3243)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF3B82F6)),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
          ),
        ),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _showSplash = true;
  final List<AppointmentState> _appointments = [];
  User? _user;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    // Splash: brief, polished intro
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _showSplash = false);
    });
    // Subscribe to auth state only if Firebase is initialized
    if (Firebase.apps.isNotEmpty) {
      _authSub = FirebaseAuth.instance.authStateChanges().listen((u) {
        if (!mounted) return;
        setState(() => _user = u);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            centerTitle: false,
            title: _user == null
                ? OutlinedButton(
                    onPressed: _openAuth,
                    style: AppButtons.outline(),
                    child: const Text('تسجيل الدخول', style: TextStyle(fontSize: 16)),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.account_circle, size: 20, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(
                        _displayName(_user!),
                        style: const TextStyle(fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _signOut,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFF2A3243)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('تسجيل الخروج'),
                      ),
                    ],
                  ),
            leading: null,
            actions: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8.0),
                child: ElevatedButton.icon(
                  onPressed: _openNewAppointment,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('موعد جديد'),
                  style: AppButtons.primary(),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _appointments.isEmpty
                  ? _EmptyState(onCreate: _openNewAppointment)
                  : ListView.separated(
                      itemCount: _appointments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => _ResultCard(
                        state: _appointments[i],
                        onEdit: () => _openNewAppointment(initial: _appointments[i], index: i),
                        onDelete: () => _deleteAppointment(i),
                      ),
                    ),
            ),
          ),
        ),
        if (_showSplash)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [Color(0xFF0B0D11), Color(0xFF0F1422)],
              ),
            ),
            alignment: Alignment.center,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1),
              curve: Curves.easeOutBack,
              duration: const Duration(milliseconds: 600),
              builder: (context, scale, child) => Opacity(
                opacity: scale.clamp(0.0, 1.0),
                child: Transform.scale(scale: scale, child: child),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8)),
                      ],
                      border: Border.all(color: const Color(0xFF2A3243)),
                    ),
                    child: const Center(
                      child: Icon(Icons.timelapse, size: 44, color: Color(0xFF3B82F6)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('مؤقتك', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text('تنظيم مواعيدك بذكاء', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 16),
                  const SizedBox(
                    width: 140,
                    child: LinearProgressIndicator(minHeight: 4, color: Color(0xFF3B82F6), backgroundColor: Color(0xFF2A3243)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _openNewAppointment({AppointmentState? initial, int? index}) async {
    final result = await showDialog<AppointmentState>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AppointmentDialog(initial: initial),
    );
    if (result != null) {
      setState(() {
        if (index != null && index >= 0 && index < _appointments.length) {
          _appointments[index] = result;
        } else {
          _appointments.add(result);
        }
      });
    }
  }

  Future<void> _openAuth() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const _AuthDialog(),
    );
  }

  Future<void> _signOut() async {
    await AuthService.instance.signOut();
  }

  void _deleteAppointment(int i) {
    setState(() => _appointments.removeAt(i));
  }

  String _displayName(User user) {
    return user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : (user.email ?? 'مستخدم');
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('ابدأ بتنظيم مواعيدك', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('حدد موقعك والوجهة ووقت الموعد لنحسب وقت المغادرة المناسب لك.',
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onCreate,
            style: AppButtons.primary(),
            child: const Text('أنشئ موعدك الآن'),
          ),
        ],
      ),
    );
  }
}

class _AuthDialog extends StatefulWidget {
  const _AuthDialog();

  @override
  State<_AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<_AuthDialog> {
  bool _isLogin = true;
  String? _error;
  bool _busy = false;

  // Login controllers
  final _loginEmail = TextEditingController();
  final _loginPass = TextEditingController();
  String? _errLoginEmail;
  String? _errLoginPass;

  // Register controllers
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _regEmail = TextEditingController();
  final _regPass = TextEditingController();
  final _regPassConfirm = TextEditingController();
  String? _errFirst;
  String? _errLast;
  String? _errRegEmail;
  String? _errRegPass;
  String? _errRegConfirm;

  @override
  void dispose() {
    _loginEmail.dispose();
    _loginPass.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _regEmail.dispose();
    _regPass.dispose();
    _regPassConfirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Firebase.apps.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.only(bottom: 12.0),
                          child: AppBanner.error(
                            'لم يتم تهيئة Firebase. يرجى إعداد مفاتيح المشروع أولاً.\n(flutterfire configure أو ملفات GoogleService)'
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(8),
                      child: const Icon(Icons.lock_outline, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isLogin ? 'تسجيل الدخول' : 'إنشاء حساب جديد',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: 'إغلاق',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 12),
                if (_isLogin) _buildLoginForm() else _buildRegisterForm(),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(_error ?? '', style: const TextStyle(color: Colors.redAccent)),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _isLogin = !_isLogin),
                      child: Text(_isLogin ? 'إنشاء حساب جديد' : 'لديك حساب؟ تسجيل الدخول'),
                    ),
                    ElevatedButton(
                      onPressed: (_busy || Firebase.apps.isEmpty)
                          ? null
                          : (_isLogin ? _onLogin : _onRegister),
                      style: AppButtons.primary(),
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_isLogin ? 'تسجيل الدخول' : 'إنشاء الحساب'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Column(
      children: [
        _labeledField('البريد الإلكتروني', _loginEmail, keyboard: TextInputType.emailAddress, prefix: const Icon(Icons.alternate_email, size: 18), errorText: _errLoginEmail),
        _labeledField('كلمة المرور', _loginPass, obscure: true, enableVisibilityToggle: true, prefix: const Icon(Icons.lock_outline, size: 18), errorText: _errLoginPass),
      ],
    );
  }

  Widget _buildRegisterForm() {
    return Column(
      children: [
        _labeledField('الاسم الأول', _firstName, prefix: const Icon(Icons.person_outline, size: 18), errorText: _errFirst),
        _labeledField('اسم العائلة', _lastName, prefix: const Icon(Icons.person_outline, size: 18), errorText: _errLast),
        _labeledField('البريد الإلكتروني الشخصي', _regEmail, keyboard: TextInputType.emailAddress, prefix: const Icon(Icons.alternate_email, size: 18), errorText: _errRegEmail),
        _labeledField('كلمة المرور', _regPass, obscure: true, enableVisibilityToggle: true, prefix: const Icon(Icons.lock_outline, size: 18), errorText: _errRegPass),
        _labeledField('تأكيد كلمة المرور', _regPassConfirm, obscure: true, enableVisibilityToggle: true, prefix: const Icon(Icons.lock_outline, size: 18), errorText: _errRegConfirm),
      ],
    );
  }

  bool _loginPassHidden = true;
  bool _regPassHidden = true;
  bool _regPassConfirmHidden = true;

  Widget _labeledField(String label, TextEditingController ctrl,
      {bool obscure = false, TextInputType? keyboard, bool enableVisibilityToggle = false, Widget? prefix, String? errorText}) {
    bool isConfirm = identical(ctrl, _regPassConfirm);
    bool isLoginPass = identical(ctrl, _loginPass);
    bool isRegPass = identical(ctrl, _regPass);
    bool hidden = obscure && (isConfirm ? _regPassConfirmHidden : (isLoginPass ? _loginPassHidden : (isRegPass ? _regPassHidden : true)));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          TextField(
            controller: ctrl,
            obscureText: obscure ? hidden : false,
            keyboardType: keyboard,
            textAlign: TextAlign.right,
            textDirection: TextDirection.rtl,
            autocorrect: false,
            enableSuggestions: false,
            spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surfaceAlt,
              hintText: '',
              errorText: errorText,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
              prefixIcon: prefix == null
                  ? null
                  : Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8.0, end: 4.0),
                      child: prefix,
                    ),
              suffixIcon: enableVisibilityToggle
                  ? IconButton(
                      tooltip: hidden ? 'إظهار' : 'إخفاء',
                      onPressed: () => setState(() {
                        if (isConfirm) {
                          _regPassConfirmHidden = !_regPassConfirmHidden;
                        } else if (isLoginPass) {
                          _loginPassHidden = !_loginPassHidden;
                        } else if (isRegPass) {
                          _regPassHidden = !_regPassHidden;
                        }
                      }),
                      icon: Icon(hidden ? Icons.visibility : Icons.visibility_off),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onLogin() async {
    setState(() { _error = null; _busy = true; _errLoginEmail = null; _errLoginPass = null; });
    final email = _loginEmail.text.trim();
    final pass = _loginPass.text;
    bool ok = true;
    if (email.isEmpty || !_isEmail(email)) { _errLoginEmail = 'أدخل بريدًا إلكترونيًا صالحًا'; ok = false; }
    if (pass.isEmpty) { _errLoginPass = 'أدخل كلمة المرور'; ok = false; }
    if (!ok) { setState(() { _busy = false; }); return; }
    try {
      await AuthService.instance.signIn(email: email, password: pass);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = _authErrorMessage(e, login: true));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onRegister() async {
    setState(() { _error = null; _busy = true; _errFirst = _errLast = _errRegEmail = _errRegPass = _errRegConfirm = null; });
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    final email = _regEmail.text.trim();
    final pass = _regPass.text;
    final confirm = _regPassConfirm.text;
    bool ok = true;
    if (first.isEmpty) { _errFirst = 'الاسم الأول مطلوب'; ok = false; }
    if (last.isEmpty) { _errLast = 'اسم العائلة مطلوب'; ok = false; }
    if (email.isEmpty || !_isEmail(email)) { _errRegEmail = 'أدخل بريدًا إلكترونيًا صالحًا'; ok = false; }
    if (pass.length < 6) { _errRegPass = 'كلمة المرور لا تقل عن 6 أحرف'; ok = false; }
    if (confirm != pass) { _errRegConfirm = 'كلمتا المرور غير متطابقتين'; ok = false; }
    if (!ok) { setState(() { _busy = false; }); return; }
    try {
      await AuthService.instance.register(firstName: first, lastName: last, email: email, password: pass);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = _authErrorMessage(e, login: false));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isEmail(String v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);

  String _authErrorMessage(Object e, {required bool login}) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'user-not-found':
          return 'لا يوجد مستخدم مسجل بهذا البريد.';
        case 'wrong-password':
          return 'كلمة المرور غير صحيحة.';
        case 'invalid-email':
          return 'البريد الإلكتروني غير صالح.';
        case 'user-disabled':
          return 'تم تعطيل هذا الحساب.';
        case 'email-already-in-use':
          return 'البريد الإلكتروني مستخدم مسبقًا.';
        case 'weak-password':
          return 'كلمة المرور ضعيفة. اختر كلمة أقوى.';
        case 'operation-not-allowed':
          return 'نوع التسجيل غير مفعّل في المشروع.';
        default:
          return login ? 'تعذر تسجيل الدخول: ${e.message ?? e.code}' : 'تعذر إنشاء الحساب: ${e.message ?? e.code}';
      }
    }
    return login ? 'تعذر تسجيل الدخول: $e' : 'تعذر إنشاء الحساب: $e';
  }
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  bool get isReady => Firebase.apps.isNotEmpty;

  Future<void> signIn({required String email, required String password}) async {
    if (!isReady) {
      throw StateError('Firebase is not initialized');
    }
    final auth = FirebaseAuth.instance;
    await auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    if (!isReady) {
      throw StateError('Firebase is not initialized');
    }
    final auth = FirebaseAuth.instance;
    final cred = await auth.createUserWithEmailAndPassword(email: email, password: password);
    if (cred.user != null) {
      await cred.user!.updateDisplayName('$firstName $lastName');
      try { await cred.user!.sendEmailVerification(); } catch (_) {}
    }
  }

  Future<void> signOut() async {
    if (!isReady) return;
    await FirebaseAuth.instance.signOut();
  }
}

class _ResultCard extends StatelessWidget {
  final AppointmentState state;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const _ResultCard({required this.state, this.onEdit, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final leaveLocal = utcToRiyadhLocal(state.leaveAtUtc);
    final arriveLocal = utcToRiyadhLocal(state.arriveAtUtc);
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFF2A3243))),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('وقت المغادرة', style: TextStyle(color: Colors.white70)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                formatTime12Arabic(leaveLocal),
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700),
              ),
            ),
            const Divider(height: 24),
            _infoRow('إلى:', state.destLabel ?? 'الوجهة المحددة'),
            _infoRow('موعد الوصول:', formatFullArabic(arriveLocal)),
            _infoRow('مدة الرحلة التقديرية:', '${state.travelMinutes} دقيقة${state.travelSource == 'haversine' || state.travelSource == 'dummy' ? ' (تقديري)' : ''}'),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final local = utcToRiyadhLocal(state.leaveAtUtc);
                    final text = 'وقت المغادرة: ${formatTime12Arabic(local)} — ${formatDateArabic(local)}';
                    await Clipboard.setData(ClipboardData(text: text));
                    // ignore: use_build_context_synchronously
                    showSnack(context, 'تم نسخ وقت المغادرة');
                  },
                  style: AppButtons.outline(),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('نسخ وقت المغادرة'),
                ),
                const SizedBox(width: 8),
                if (onEdit != null)
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    style: AppButtons.outline(),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('تعديل'),
                  ),
                const SizedBox(width: 8),
                if (onDelete != null)
                  OutlinedButton.icon(
                    onPressed: onDelete,
                    style: AppButtons.outline(),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('حذف'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentDialog extends StatefulWidget {
  final AppointmentState? initial;
  const _AppointmentDialog({this.initial});

  @override
  State<_AppointmentDialog> createState() => _AppointmentDialogState();
}

class _AppointmentDialogState extends State<_AppointmentDialog> {
  LatLng? _origin;
  LatLng? _destination;

  late DateTime _dateLocal;
  late TimeOfDay _timeLocal;

  final _prepCtrl = TextEditingController(text: '10');
  final _delayCtrl = TextEditingController(text: '5');
  String? _error;
  String? _errPrep;
  String? _errDelay;
  final _labelCtrl = TextEditingController();

  @override
  void dispose() {
    _prepCtrl.dispose();
    _delayCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      final s = widget.initial!;
      _origin = s.origin;
      _destination = s.destination;
      _labelCtrl.text = s.destLabel ?? '';
      _prepCtrl.text = s.prepMinutes.toString();
      _delayCtrl.text = s.delayMinutes.toString();
      final arriveLocal = utcToRiyadhLocal(s.arriveAtUtc);
      _dateLocal = DateTime(arriveLocal.year, arriveLocal.month, arriveLocal.day);
      _timeLocal = TimeOfDay(hour: arriveLocal.hour, minute: arriveLocal.minute);
    } else {
      final now = riyadhNowLocal();
      _dateLocal = DateTime(now.year, now.month, now.day);
      _timeLocal = TimeOfDay(hour: now.hour, minute: now.minute);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 740),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(8),
                      child: const Icon(Icons.event, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('موعد جديد', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: 'إغلاق',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 12),
              _fieldGroup(
                label: 'الموقع الحالي',
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: () => _pickOnMap(true),
                      style: AppButtons.secondary(),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map_outlined, size: 18),
                          SizedBox(width: 6),
                          Text('اختيار من الخريطة'),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      onPressed: _useCurrentLocation,
                      style: AppButtons.outline(),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.my_location, size: 18),
                          SizedBox(width: 6),
                          Text('موقعي الحالي'),
                        ],
                      ),
                    ),
                    _origin == null
                        ? const AppTag('غير محدد', icon: Icons.place_outlined)
                        : AppTag('${_origin!.lat.toStringAsFixed(4)}, ${_origin!.lng.toStringAsFixed(4)}', icon: Icons.place_outlined),
                  ],
                ),
              ),
              _fieldGroup(
                label: 'الوجهة',
                child: Row(
                  children: [
                    ElevatedButton(
                      onPressed: () => _pickOnMap(false),
                      style: AppButtons.secondary(),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flag_outlined, size: 18),
                          SizedBox(width: 6),
                          Text('اختيار من الخريطة'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _destination == null
                        ? const AppTag('غير محدد', icon: Icons.flag_outlined)
                        : AppTag('${_destination!.lat.toStringAsFixed(4)}, ${_destination!.lng.toStringAsFixed(4)}', icon: Icons.flag_outlined),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _fieldGroup(
                      label: 'تاريخ الموعد',
                      child: OutlinedButton(
                        onPressed: _pickDate,
                        style: AppButtons.outline(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_today_outlined, size: 18),
                            const SizedBox(width: 6),
                            Text(formatDateArabic(_dateLocal)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _fieldGroup(
                      label: 'وقت الموعد',
                      child: OutlinedButton(
                        onPressed: _pickTime,
                        style: AppButtons.outline(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.schedule_outlined, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              formatTime12Arabic(DateTime(
                                _dateLocal.year, _dateLocal.month, _dateLocal.day, _timeLocal.hour, _timeLocal.minute,
                              )),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              _fieldGroup(
                label: 'اسم الوجهة (اختياري)',
                child: TextField(
                  controller: _labelCtrl,
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  autocorrect: false,
                  enableSuggestions: false,
                  spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.surfaceAlt,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _fieldGroup(
                      label: 'مدة الاستعداد (بالدقائق)',
                      child: TextField(
                        controller: _prepCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        textAlign: TextAlign.right,
                        textDirection: TextDirection.rtl,
                        autocorrect: false,
                        enableSuggestions: false,
                        spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
                        decoration: InputDecoration(
                          hintText: '0',
                          errorText: _errPrep,
                          filled: true,
                          fillColor: AppColors.surfaceAlt,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _fieldGroup(
                      label: 'وقت التأخير المتوقع (بالدقائق)',
                      child: TextField(
                        controller: _delayCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        textAlign: TextAlign.right,
                        textDirection: TextDirection.rtl,
                        autocorrect: false,
                        enableSuggestions: false,
                        spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
                        decoration: InputDecoration(
                          hintText: '0',
                          errorText: _errDelay,
                          filled: true,
                          fillColor: AppColors.surfaceAlt,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(_error ?? '', style: const TextStyle(color: Colors.redAccent)),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _onSave,
                  style: AppButtons.primary(),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('حفظ'),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  // Old secondary style removed. Use AppButtons.secondary() from ui.dart

  Widget _fieldGroup({required String label, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          child,
        ],
      ),
    );
  }

  Future<void> _pickOnMap(bool isOrigin) async {
    final picked = await showDialog<LatLng>(
      context: context,
      builder: (_) => const _DummyMapPicker(),
    );
    if (picked != null) {
      setState(() {
        if (isOrigin) {
          _origin = picked;
        } else {
          _destination = picked;
        }
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _error = 'خدمة الموقع غير مفعّلة على الجهاز.');
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
        setState(() => _error = 'تم رفض إذن الموقع. يرجى السماح للوصول.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 10));
      setState(() => _origin = LatLng(pos.latitude, pos.longitude));
    } catch (e) {
      setState(() => _error = 'تعذر تحديد الموقع الحالي: $e');
    }
  }

  Future<void> _pickDate() async {
    final now = riyadhNowLocal();
    final init = DateTime(_dateLocal.year, _dateLocal.month, _dateLocal.day);
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDate: init,
      helpText: 'اختر التاريخ',
      cancelText: 'إلغاء',
      confirmText: 'تأكيد',
    );
    if (picked != null) {
      setState(() => _dateLocal = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeLocal,
      helpText: 'اختر الوقت',
      cancelText: 'إلغاء',
      confirmText: 'تأكيد',
    );
    if (picked != null) setState(() => _timeLocal = picked);
  }

  Future<void> _onSave() async {
    setState(() { _error = null; _errPrep = null; _errDelay = null; });
    if (_origin == null || _destination == null) {
      setState(() => _error = 'يرجى تحديد الموقع والوجهة من الخريطة.');
      return;
    }
    final prep = _parseNonNegInt(_prepCtrl.text, -1);
    final delay = _parseNonNegInt(_delayCtrl.text, -1);
    bool ok = true;
    if (prep < 0) { _errPrep = 'أدخل رقمًا صحيحًا'; ok = false; }
    if (delay < 0) { _errDelay = 'أدخل رقمًا صحيحًا'; ok = false; }
    if (!ok) { setState(() {}); return; }

    final arriveLocal = DateTime(
      _dateLocal.year, _dateLocal.month, _dateLocal.day, _timeLocal.hour, _timeLocal.minute,
    );
    final arriveUtc = riyadhLocalToUtc(arriveLocal);

    // Compute an initial guess for leaveUtc using estimated travel time
    final initialTravelMin = estimateTravelMinutes(_origin!, _destination!);
    final initialTotalBefore = Duration(minutes: prep + delay + initialTravelMin);
    final leaveUtc = arriveUtc.subtract(initialTotalBefore);

    // Fetch realistic travel time from backend (or haversine fallback)
    final travelRes = await TravelTimeService.instance.fetch(
      origin: _origin!, destination: _destination!, departureUtc: leaveUtc, // initial guess; refined below if needed
    );
    final travelMin = travelRes.minutes;
    final totalBefore = Duration(minutes: prep + delay + travelMin);
    final adjustedLeaveUtc = arriveUtc.subtract(totalBefore);

    final state = AppointmentState(
      origin: _origin!,
      destination: _destination!,
      destLabel: _labelCtrl.text.trim().isEmpty ? 'الوجهة المحددة' : _labelCtrl.text.trim(),
      arriveAtUtc: arriveUtc,
      leaveAtUtc: adjustedLeaveUtc,
      travelMinutes: travelMin,
      prepMinutes: prep,
      delayMinutes: delay,
      travelSource: travelRes.source,
    );

    Navigator.of(context).pop(state);
  }

  int _parseNonNegInt(String s, int fallback) {
    final v = int.tryParse(s.trim());
    if (v == null || v < 0) return fallback;
    return v;
  }
}

class _DummyMapPicker extends StatefulWidget {
  const _DummyMapPicker();

  @override
  State<_DummyMapPicker> createState() => _DummyMapPickerState();
}

class _DummyMapPickerState extends State<_DummyMapPicker> {
  Offset? _tapPos;

  static const double latMin = 16.0;
  static const double latMax = 32.0;
  static const double lngMin = 34.0;
  static const double lngMax = 56.0;

  LatLng? get _pickedLatLng {
    if (_tapPos == null) return null;
    final box = _boxSize;
    if (box == null) return null;
    final pxX = (_tapPos!.dx / box.width).clamp(0.0, 1.0);
    final pxY = (_tapPos!.dy / box.height).clamp(0.0, 1.0);
    final lat = latMax - (latMax - latMin) * pxY;
    final lng = lngMin + (lngMax - lngMin) * pxX;
    return LatLng(lat, lng);
  }

  Size? _boxSize;

  @override
  Widget build(BuildContext context) {
    final picked = _pickedLatLng;
    return Dialog(
      backgroundColor: const Color(0xFF151922),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: Text('خريطة تجريبية', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 8),
            const Text('انقر على الخريطة لتحديد الموقع (بيانات وهمية)', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                _boxSize = Size(constraints.maxWidth, 220);
                return GestureDetector(
                  onTapDown: (d) => setState(() => _tapPos = d.localPosition),
                  child: Container(
                    height: 220,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E1320),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2A3243)),
                      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 14, offset: Offset(0, 6))],
                    ),
                    child: CustomPaint(
                      painter: _GridPainter(marker: _tapPos),
                      child: const SizedBox.expand(),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Text(
              picked == null
                  ? 'الإحداثيات: —'
                  : 'الإحداثيات: خط العرض ${picked.lat.toStringAsFixed(4)}، خط الطول ${picked.lng.toStringAsFixed(4)}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: picked == null ? null : () => Navigator.of(context).pop(picked),
                  style: AppButtons.primary(),
                  child: const Text('تأكيد الاختيار'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final Offset? marker;
  const _GridPainter({this.marker});

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF111827);
    canvas.drawRect(Offset.zero & size, bg);

    final gridPaint = Paint()
      ..color = const Color(0xFF2A3243)
      ..strokeWidth = 1;
    const step = 24.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (marker != null) {
      final circle = Paint()..color = const Color(0xFF22C55E);
      canvas.drawCircle(marker!, 6, circle);
      final ring = Paint()
        ..color = const Color(0xFF22C55E).withOpacity(0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8;
      canvas.drawCircle(marker!, 12, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => oldDelegate.marker != marker;
}

// البيانات والمنطق
class LatLng {
  final double lat;
  final double lng;
  const LatLng(this.lat, this.lng);
}

class AppointmentState {
  final LatLng origin;
  final LatLng destination;
  final String? destLabel;
  final DateTime arriveAtUtc;
  final DateTime leaveAtUtc;
  final int travelMinutes;
  final int prepMinutes;
  final int delayMinutes;
  final String? travelSource;
  const AppointmentState({
    required this.origin,
    required this.destination,
    required this.destLabel,
    required this.arriveAtUtc,
    required this.leaveAtUtc,
    required this.travelMinutes,
    required this.prepMinutes,
    required this.delayMinutes,
    this.travelSource,
  });
}

double haversineKm(LatLng a, LatLng b) {
  const R = 6371.0;
  double toRad(double d) => d * math.pi / 180.0;
  final dLat = toRad(b.lat - a.lat);
  final dLon = toRad(b.lng - a.lng);
  final lat1 = toRad(a.lat);
  final lat2 = toRad(b.lat);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  return R * c;
}

int estimateTravelMinutes(LatLng origin, LatLng dest) {
  final km = haversineKm(origin, dest);
  return (km * 1.5 + 5).round(); // وهمي: 1.5 دقيقة/كم + 5 دقائق
}

// توقيت مكة (UTC+3) بدون DST
DateTime riyadhNowLocal() => DateTime.now().toUtc().add(const Duration(hours: 3));
DateTime riyadhLocalToUtc(DateTime local) => local.subtract(const Duration(hours: 3));
DateTime utcToRiyadhLocal(DateTime utc) => utc.add(const Duration(hours: 3));

String twoDigits(int n) => n.toString().padLeft(2, '0');

String formatTime12Arabic(DateTime local) {
  int h = local.hour;
  final m = local.minute;
  final isPM = h >= 12;
  h = h % 12; if (h == 0) h = 12;
  final mer = isPM ? 'م' : 'ص';
  return '${twoDigits(h)}:${twoDigits(m)} $mer';
}

String formatDateArabic(DateTime local) {
  return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year}';
}

String formatFullArabic(DateTime local) {
  const days = {
    1: 'الاثنين',
    2: 'الثلاثاء',
    3: 'الأربعاء',
    4: 'الخميس',
    5: 'الجمعة',
    6: 'السبت',
    7: 'الأحد',
  };
  final dow = days[local.weekday] ?? '';
  return '$dow ${formatDateArabic(local)} ${formatTime12Arabic(local)}';
}
