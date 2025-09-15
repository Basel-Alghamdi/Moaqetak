import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'travel_time_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:http/http.dart' as http;
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  assert(() {
    debugPaintSizeEnabled = false;
    debugPaintBaselinesEnabled = false;
    debugPaintPointersEnabled = false;
    debugRepaintRainbowEnabled = false;
    return true;
  }());
  await Hive.initFlutter();
  await Hive.openBox('appointments');
  await Hive.openBox('app_meta');
  await Hive.openBox('settings');
  // Enable runtime font fetching so iOS/Android emulators pull Tajawal
  // without needing pre-bundled assets.
  GoogleFonts.config.allowRuntimeFetching = true;
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
        theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: GoogleFonts.tajawal().fontFamily,
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
          // Professional Arabic font across the app (taller display)
          textTheme: GoogleFonts.tajawalTextTheme(ThemeData.dark().textTheme),
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

  @override
  void initState() {
    super.initState();
    // Splash: brief, polished intro
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _showSplash = false);
    });
    // Bootstrap data: migrate if needed, then load
    Future.microtask(_bootstrapData);
  }

  Future<void> _bootstrapData() async {
    await _maybeMigrateUtcV1();
    final box = Hive.box('appointments');
    final List<AppointmentState> loaded = [];
    for (var i = 0; i < box.length; i++) {
      final item = box.getAt(i);
      if (item is Map) {
        try {
          loaded.add(AppointmentState.fromMap(Map<String, dynamic>.from(item)));
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() {
      _appointments
        ..clear()
        ..addAll(loaded);
    });
  }

  Future<void> _maybeMigrateUtcV1() async {
    final meta = Hive.box('app_meta');
    final migrated = meta.get('migrated_utc_v1') == true;
    if (migrated) return;
    final box = Hive.box('appointments');
    for (var i = 0; i < box.length; i++) {
      final item = box.getAt(i);
      if (item is Map && item['arriveAtUtc'] is num && item['leaveAtUtc'] is num) {
        final m = Map<String, dynamic>.from(item);
        int a = (m['arriveAtUtc'] as num).toInt();
        int l = (m['leaveAtUtc'] as num).toInt();
        // Reinterpret stored epoch as device-local wall clock and treat it as UTC wall clock.
        DateTime relabelAsUtc(int ms) {
          final asLocal = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: false);
          return DateTime.utc(asLocal.year, asLocal.month, asLocal.day, asLocal.hour, asLocal.minute, asLocal.second, asLocal.millisecond, asLocal.microsecond);
        }
        final fixedA = relabelAsUtc(a).millisecondsSinceEpoch;
        final fixedL = relabelAsUtc(l).millisecondsSinceEpoch;
        if (fixedA != a || fixedL != l) {
          m['arriveAtUtc'] = fixedA;
          m['leaveAtUtc'] = fixedL;
          await box.putAt(i, m);
        }
      }
    }
    await meta.put('migrated_utc_v1', true);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            centerTitle: false,
            title: const Text('مؤقتك', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
            IconButton(
              tooltip: 'الإعدادات',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
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
        if (_showSplash) const _SplashView(),
      ],
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _openNewAppointment({AppointmentState? initial, int? index}) async {
    final result = await showDialog<AppointmentState>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AppointmentDialog(initial: initial),
    );
    if (result != null) {
      final box = Hive.box('appointments');
      if (index != null && index >= 0 && index < _appointments.length) {
        await box.putAt(index, result.toMap());
        setState(() => _appointments[index] = result);
      } else {
        await box.add(result.toMap());
        setState(() => _appointments.add(result));
      }
    }
  }

  void _deleteAppointment(int i) {
    final box = Hive.box('appointments');
    if (i >= 0 && i < box.length) {
      box.deleteAt(i);
    }
    setState(() => _appointments.removeAt(i));
  }

  Future<void> _openSettings() async {
    await showDialog(context: context, builder: (_) => const _SettingsDialog());
    setState(() {}); // refresh to reflect any theme-ish changes if needed
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

// Auth UI and Firebase integration removed — local-only app

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
            FittedBox(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                  onPressed: () async {
                    final local = utcToRiyadhLocal(state.leaveAtUtc);
                    final text = 'وقت المغادرة: ${formatTime12Arabic(local)} — ${formatDateArabic(local)}';
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!context.mounted) return;
                    showSnack(context, 'تم نسخ وقت المغادرة');
                  },
                  style: AppButtons.outline().copyWith(
                    side: const WidgetStatePropertyAll(BorderSide(color: AppColors.success)),
                    foregroundColor: WidgetStatePropertyAll(AppColors.success),
                    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                    minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
                  ),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('نسخ وقت المغادرة'),
                ),
                const SizedBox(width: 8),
                if (onEdit != null)
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    style: AppButtons.outline().copyWith(
                      side: const WidgetStatePropertyAll(BorderSide(color: AppColors.primary)),
                      foregroundColor: const WidgetStatePropertyAll(AppColors.primary),
                      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                      minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
                    ),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('تعديل'),
                  ),
                if (onDelete != null) const SizedBox(width: 8),
                if (onDelete != null)
                  OutlinedButton.icon(
                    onPressed: onDelete,
                    style: AppButtons.outline().copyWith(
                      side: const WidgetStatePropertyAll(BorderSide(color: AppColors.danger)),
                      foregroundColor: const WidgetStatePropertyAll(Colors.redAccent),
                      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                      minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('حذف'),
                  ),
                ],
              ),
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
  // Counter values for minutes (0..100)
  int _prepMinutes = 10;
  int _delayMinutes = 5;
  String? _error;
  // numeric validation errors are surfaced via _error banner
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
      _prepMinutes = s.prepMinutes;
      _delayMinutes = s.delayMinutes;
      final arriveLocal = utcToRiyadhLocal(s.arriveAtUtc);
      _dateLocal = DateTime(arriveLocal.year, arriveLocal.month, arriveLocal.day);
      _timeLocal = TimeOfDay(hour: arriveLocal.hour, minute: arriveLocal.minute);
    } else {
      final now = riyadhNowLocal();
      _dateLocal = DateTime(now.year, now.month, now.day);
      _timeLocal = TimeOfDay(hour: now.hour, minute: now.minute);
      _prepMinutes = 10;
      _delayMinutes = 5;
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
                        color: AppColors.primary.withValues(alpha: 0.12),
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
                    _origin == null
                        ? const AppTag('غير محدد', icon: Icons.place_outlined)
                        : AppTag('${_origin!.lat.toStringAsFixed(4)}, ${_origin!.lng.toStringAsFixed(4)}', icon: Icons.place_outlined),
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
                  ],
                ),
              ),
              _fieldGroup(
                label: 'الوجهة',
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: () => _pickOnMap(false),
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
                    _destination == null
                        ? const AppTag('غير محدد', icon: Icons.place_outlined)
                        : AppTag('${_destination!.lat.toStringAsFixed(4)}, ${_destination!.lng.toStringAsFixed(4)}', icon: Icons.place_outlined),
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
                      child: _minutesCounter(
                        value: _prepMinutes,
                        onChanged: (v) {
                          setState(() {
                            _prepMinutes = v.clamp(0, 100);
                            _prepCtrl.text = _prepMinutes.toString();
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _fieldGroup(
                      label: 'التأخير المتوقع (بالدقائق)',
                      child: _minutesCounter(
                        value: _delayMinutes,
                        onChanged: (v) {
                          setState(() {
                            _delayMinutes = v.clamp(0, 100);
                            _delayCtrl.text = _delayMinutes.toString();
                          });
                        },
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
                child: ElevatedButton(
                  onPressed: _onSave,
                  style: AppButtons.primary(),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('حفظ'),
                      SizedBox(width: 6),
                      Icon(Icons.check_circle_outline, size: 18),
                    ],
                  ),
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

  // Small counter control limited to 0..100 minutes
  Widget _minutesCounter({required int value, required ValueChanged<int> onChanged}) {
    final smallBtnStyle = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: const BorderSide(color: AppColors.border),
      padding: EdgeInsets.zero,
      minimumSize: const Size(32, 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
    // Force LTR inside control to keep [-][value][+] order in RTL UI
    // and give a unified width for consistent alignment between fields.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 140,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(
              onPressed: value <= 0 ? null : () => onChanged(value - 1),
              style: smallBtnStyle,
              child: const Icon(Icons.remove, size: 16),
            ),
            AppTag(
              '$value',
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            ),
            OutlinedButton(
              onPressed: value >= 100 ? null : () => onChanged(value + 1),
              style: smallBtnStyle,
              child: const Icon(Icons.add, size: 16),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickOnMap(bool isOrigin) async {
    final picked = await showDialog<LatLng>(
      context: context,
      builder: (_) => _OSMMapPicker(
        initial: isOrigin ? _origin : _destination,
        other: isOrigin ? _destination : _origin,
        isOrigin: isOrigin,
      ),
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
    setState(() { _error = null; });
    if (_origin == null || _destination == null) {
      setState(() => _error = 'يرجى تحديد الموقع والوجهة من الخريطة.');
      return;
    }
    final prep = _parseNonNegInt(_prepCtrl.text, -1);
    final delay = _parseNonNegInt(_delayCtrl.text, -1);
    if (prep < 0 || delay < 0) {
      setState(() { _error = 'أدخل أرقامًا صحيحة لمدة الاستعداد والتأخير'; });
      return;
    }

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

    if (!mounted) return;
    Navigator.of(context).pop(state);
  }

  int _parseNonNegInt(String s, int fallback) {
    final v = int.tryParse(s.trim());
    if (v == null || v < 0) return fallback;
    return v;
  }
}

class _OSMMapPicker extends StatefulWidget {
  final LatLng? initial; // active pin (origin or destination)
  final LatLng? other; // the other pin to display for context
  final bool isOrigin; // true if picking origin
  const _OSMMapPicker({this.initial, this.other, required this.isOrigin});

  @override
  State<_OSMMapPicker> createState() => _OSMMapPickerState();
}

class _OSMMapPickerState extends State<_OSMMapPicker> {
  ll.LatLng? _active;
  ll.LatLng? _other;
  bool _locTried = false;
  final MapController _mapController = MapController();

  // Search state
  final TextEditingController _searchCtrl = TextEditingController();
  List<_SearchResult> _searchResults = [];
  bool _searching = false;
  String? _searchError;

  // Track camera state for zoom controls
  late ll.LatLng _mapCenter;
  double _mapZoom = 12;

  // POIs (Places) state
  final List<_PoiCat> _poiCats = const [
    _PoiCat(key: 'all', label: 'الكل', color: Color(0xFF9CA3AF), icon: Icons.place_outlined),
    _PoiCat(key: 'restaurant', label: 'مطاعم', color: Color(0xFFf59e0b), icon: Icons.restaurant),
    _PoiCat(key: 'cafe', label: 'مقاهي', color: Color(0xFF10b981), icon: Icons.local_cafe),
    _PoiCat(key: 'shop', label: 'متاجر', color: Color(0xFF3b82f6), icon: Icons.storefront),
    _PoiCat(key: 'pharmacy', label: 'صيدليات', color: Color(0xFFef4444), icon: Icons.local_pharmacy),
    _PoiCat(key: 'hospital', label: 'مستشفيات', color: Color(0xFF8b5cf6), icon: Icons.local_hospital),
    _PoiCat(key: 'fuel', label: 'وقود', color: Color(0xFF22c55e), icon: Icons.local_gas_station),
  ];
  String _selectedPoiCat = 'all';
  List<_Poi> _pois = [];
  _Poi? _selectedPoi;
  bool _poiLoading = false;
  // Silent failure: no error banner shown for POIs
  Timer? _poiDebounce;

  @override
  void initState() {
    super.initState();
    _active = widget.initial == null ? null : ll.LatLng(widget.initial!.lat, widget.initial!.lng);
    _other = widget.other == null ? null : ll.LatLng(widget.other!.lat, widget.other!.lng);
    _mapCenter = _defaultCenter;
    _mapZoom = 12;
    _maybeGetLocation();
    // Initial POIs fetch once the dialog opens
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleFetchPois());
  }

  Future<void> _maybeGetLocation() async {
    if (widget.isOrigin && _active == null && !_locTried) {
      _locTried = true;
      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) return;
        LocationPermission p = await Geolocator.checkPermission();
        if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
        if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return;
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 10));
        setState(() { _active = ll.LatLng(pos.latitude, pos.longitude); });
      } catch (_) {}
    }
  }

  ll.LatLng get _defaultCenter => _active ?? _other ?? ll.LatLng(24.7136, 46.6753); // Riyadh

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.isOrigin ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
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
                Expanded(child: Text(widget.isOrigin ? 'اختيار الموقع الحالي' : 'اختيار الوجهة', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 8),
            const Text('اضغط على الخريطة لوضع المؤشر. يمكنك التحريك والتقريب.', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            SizedBox(
              height: 360,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _defaultCenter,
                        initialZoom: 12,
                        onTap: (tapPos, point) {
                          setState(() {
                            _active = point;
                            _mapCenter = point;
                          });
                        },
                        onMapEvent: (evt) {
                          // Update camera state for zoom buttons
                          try {
                            setState(() {
                              _mapCenter = evt.camera.center;
                              _mapZoom = evt.camera.zoom;
                            });
                          } catch (_) {}
                          _scheduleFetchPois();
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.moaqetak',
                        ),
                        // POIs markers layer
                        MarkerLayer(markers: [
                          for (final p in _pois)
                            Marker(
                              point: ll.LatLng(p.lat, p.lon),
                              width: 36,
                              height: 36,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() { _selectedPoi = p; });
                                },
                                child: _PoiMarker(color: p.color ?? _catByKey(p.cat)?.color ?? const Color(0xFF9CA3AF)),
                              ),
                            ),
                        ]),
                        MarkerLayer(markers: [
                          if (_other != null)
                            Marker(
                              point: _other!,
                              width: 36,
                              height: 36,
                              child: const Icon(Icons.location_on, color: Color(0xFF60A5FA), size: 36),
                            ),
                          if (_active != null)
                            Marker(
                              point: _active!,
                              width: 38,
                              height: 38,
                              child: Icon(Icons.location_on, color: activeColor, size: 38),
                            ),
                        ]),
                      ],
                    ),

                    // Search box overlay (top)
                    Positioned(
                      top: 10,
                      left: 10,
                      right: 10,
                      child: Column(
                        children: [
                          TextField(
                            controller: _searchCtrl,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (q) => _runSearch(q),
                            decoration: InputDecoration(
                              hintText: 'ابحث عن شارع، حي، أو مكان',
                              suffixIcon: _searching
                                  ? const Padding(
                                      padding: EdgeInsets.all(10.0),
                                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                    )
                                  : IconButton(
                                      tooltip: 'بحث',
                                      icon: const Icon(Icons.search),
                                      onPressed: () => _runSearch(_searchCtrl.text),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          // POI category chips
                          SizedBox(
                            height: 40,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _poiCats.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 6),
                              itemBuilder: (context, i) {
                                final c = _poiCats[i];
                                final sel = c.key == _selectedPoiCat;
                                return ChoiceChip(
                                  selected: sel,
                                  onSelected: (_) {
                                    setState(() {
                                      _selectedPoiCat = c.key;
                                      _selectedPoi = null;
                                    });
                                    _scheduleFetchPois(immediate: true);
                                  },
                                  label: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(c.icon, size: 16, color: sel ? Colors.black : c.color),
                                      const SizedBox(width: 6),
                                      Text(c.label),
                                    ],
                                  ),
                                  labelStyle: const TextStyle(fontSize: 12),
                                  selectedColor: c.color.withValues(alpha: 0.9),
                                  backgroundColor: const Color(0xFF111827),
                                  side: const BorderSide(color: Color(0xFF2A3243)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                );
                              },
                            ),
                          ),
                          if (_searchError != null)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
                              margin: const EdgeInsets.only(top: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A3243),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(_searchError!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            ),
                          if (_searchResults.isNotEmpty)
                            Container(
                              width: double.infinity,
                              constraints: const BoxConstraints(maxHeight: 180),
                              margin: const EdgeInsets.only(top: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF111827),
                                border: Border.all(color: const Color(0xFF2A3243)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.separated(
                                padding: EdgeInsets.zero,
                                itemCount: _searchResults.length,
                                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF2A3243)),
                                itemBuilder: (context, i) {
                                  final r = _searchResults[i];
                                  return ListTile(
                                    dense: true,
                                    title: Text(r.displayName, maxLines: 2, overflow: TextOverflow.ellipsis),
                                    onTap: () {
                                      final p = ll.LatLng(r.lat, r.lon);
                                      setState(() {
                                        _active = p;
                                        _mapCenter = p;
                                        _searchResults = [];
                                      });
                                      try {
                                        _mapController.move(p, 16);
                                      } catch (_) {}
                                    },
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Zoom controls (bottom left)
                    Positioned(
                      bottom: 10,
                      left: 10,
                      child: Column(
                        children: [
                          _ZoomBtn(
                            icon: Icons.add,
                            onPressed: () {
                              final double z = (_mapZoom.isNaN ? 12.0 : _mapZoom) + 1.0;
                              try { _mapController.move(_mapCenter, z); } catch (_) {}
                              setState(() => _mapZoom = z);
                            },
                          ),
                          const SizedBox(height: 8),
                          _ZoomBtn(
                            icon: Icons.remove,
                            onPressed: () {
                              final double z = (_mapZoom.isNaN ? 12.0 : _mapZoom) - 1.0;
                              try { _mapController.move(_mapCenter, z); } catch (_) {}
                              setState(() => _mapZoom = z);
                            },
                          ),
                        ],
                      ),
                    ),

                    // Loading indicator for POIs (top right)
                    if (_poiLoading)
                      const Positioned(
                        top: 12,
                        right: 12,
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),

                    // Error banner for POIs removed per request (silent failures)

                    // Selected POI quick action bar (bottom center)
                    if (_selectedPoi != null)
                      Positioned(
                        bottom: 10,
                        left: 60,
                        right: 60,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111827),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF2A3243)),
                          ),
                          child: Row(
                            children: [
                              Container(width: 10, height: 10, decoration: BoxDecoration(color: _selectedPoi!.color ?? _catByKey(_selectedPoi!.cat)?.color ?? const Color(0xFF9CA3AF), shape: BoxShape.circle)),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_selectedPoi!.name ?? 'مكان بدون اسم', maxLines: 1, overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () {
                                  final p = ll.LatLng(_selectedPoi!.lat, _selectedPoi!.lon);
                                  setState(() { _active = p; });
                                  try { _mapController.move(p, 17); } catch (_) {}
                                },
                                child: const Text('اختيار'),
                              ),
                              IconButton(
                                onPressed: () => setState(() { _selectedPoi = null; }),
                                icon: const Icon(Icons.close, size: 18),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _active == null
                  ? 'الإحداثيات: —'
                  : 'الإحداثيات: ${_active!.latitude.toStringAsFixed(5)}, ${_active!.longitude.toStringAsFixed(5)}',
              style: const TextStyle(color: Colors.white70),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: _active == null ? null : () => Navigator.of(context).pop(LatLng(_active!.latitude, _active!.longitude)),
                  style: AppButtons.primary(),
                  child: const Text('تأكيد الاختيار'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _searchResults = [];
        _searchError = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'json',
        'addressdetails': '1',
        'limit': '8',
        'q': q,
      });
      final resp = await http.get(
        uri,
        headers: {
          'User-Agent': 'Moaqetak/1.0 (contact@example.com)',
        },
      );
      if (resp.statusCode == 200) {
        final List data = json.decode(resp.body) as List;
        final results = data.take(8).map((e) {
          final lat = double.tryParse(e['lat']?.toString() ?? '');
          final lon = double.tryParse(e['lon']?.toString() ?? '');
          final name = (e['display_name'] ?? '').toString();
          return (lat != null && lon != null)
              ? _SearchResult(lat: lat, lon: lon, displayName: name)
              : null;
        }).whereType<_SearchResult>().toList();
        setState(() {
          _searchResults = results;
          _searching = false;
        });
      } else {
        setState(() {
          _searching = false;
          _searchError = 'فشل البحث (${resp.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        _searching = false;
        _searchError = 'تعذر الاتصال بالخدمة';
      });
    }
  }

  // === POIs fetching via Overpass API ===
  void _scheduleFetchPois({bool immediate = false}) {
    _poiDebounce?.cancel();
    if (immediate) {
      _fetchPois();
      return;
    }
    _poiDebounce = Timer(const Duration(milliseconds: 700), _fetchPois);
  }

  int _radiusForZoom(double z) {
    final zz = z.isNaN ? 12.0 : z;
    if (zz >= 16) return 500;
    if (zz >= 15) return 800;
    if (zz >= 14) return 1200;
    if (zz >= 13) return 2000;
    return 3000;
  }

  _PoiCat? _catByKey(String? key) => _poiCats.firstWhere((c) => c.key == key, orElse: () => const _PoiCat(key: 'all', label: 'الكل', color: Color(0xFF9CA3AF), icon: Icons.place_outlined));

  String _buildOverpassQuery(double lat, double lon, int radius, String cat) {
    String filters;
    if (cat == 'restaurant') {
      filters = 'nwr(around:$radius,$lat,$lon)[amenity=restaurant];';
    } else if (cat == 'cafe') {
      filters = 'nwr(around:$radius,$lat,$lon)[amenity=cafe];';
    } else if (cat == 'pharmacy') {
      filters = 'nwr(around:$radius,$lat,$lon)[amenity=pharmacy];';
    } else if (cat == 'hospital') {
      filters = 'nwr(around:$radius,$lat,$lon)[amenity~"^(hospital|clinic)\$"];';
    } else if (cat == 'fuel') {
      filters = 'nwr(around:$radius,$lat,$lon)[amenity=fuel];';
    } else if (cat == 'shop') {
      filters = 'nwr(around:$radius,$lat,$lon)[shop];';
    } else {
      filters = 'nwr(around:$radius,$lat,$lon)[amenity~"^(restaurant|cafe|fast_food|pharmacy|hospital|clinic|fuel)\$"];nwr(around:$radius,$lat,$lon)[shop];';
    }
    return "[out:json][timeout:25];($filters);out center 100;";
  }

  Future<void> _fetchPois() async {
    // Avoid heavy loads at far zooms
    if ((_mapZoom.isNaN ? 12.0 : _mapZoom) < 12) return;
    final lat = _mapCenter.latitude;
    final lon = _mapCenter.longitude;
    final radius = _radiusForZoom(_mapZoom);
    final q = _buildOverpassQuery(lat, lon, radius, _selectedPoiCat);
    setState(() {
      _poiLoading = true;
    });
    try {
      final uri = Uri.parse('https://overpass-api.de/api/interpreter');
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded', 'User-Agent': 'Moaqetak/1.0 (contact@example.com)'},
        body: 'data=${Uri.encodeComponent(q)}',
      );
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final List els = (data['elements'] as List? ?? []);
        final List<_Poi> pois = [];
        for (final e in els) {
          final m = e as Map<String, dynamic>;
          final tags = (m['tags'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? <String, String>{};
          double? plat;
          double? plon;
          if (m['lat'] != null && m['lon'] != null) {
            final la = (m['lat'] as num).toDouble();
            final lo = (m['lon'] as num).toDouble();
            plat = la; plon = lo;
          } else if (m['center'] != null) {
            final c = m['center'] as Map<String, dynamic>;
            final la = (c['lat'] as num?)?.toDouble();
            final lo = (c['lon'] as num?)?.toDouble();
            if (la != null && lo != null) { plat = la; plon = lo; }
          }
          if (plat == null || plon == null) continue;
          final name = tags['name:ar'] ?? tags['name'] ?? '';
          String cat = _selectedPoiCat;
          Color? color;
          if (tags.containsKey('amenity')) {
            final a = tags['amenity']!;
            if (a == 'restaurant') { cat = 'restaurant'; color = _catByKey(cat)?.color; }
            else if (a == 'cafe') { cat = 'cafe'; color = _catByKey(cat)?.color; }
            else if (a == 'pharmacy') { cat = 'pharmacy'; color = _catByKey(cat)?.color; }
            else if (a == 'hospital' || a == 'clinic') { cat = 'hospital'; color = _catByKey(cat)?.color; }
            else if (a == 'fuel') { cat = 'fuel'; color = _catByKey(cat)?.color; }
          } else if (tags.containsKey('shop')) {
            cat = 'shop'; color = _catByKey(cat)?.color;
          }
          pois.add(_Poi(lat: plat, lon: plon, name: name.isEmpty ? null : name, tags: tags, cat: cat, color: color));
          if (pois.length >= 150) break; // limit to avoid clutter
        }
        setState(() {
          _pois = pois;
          _poiLoading = false;
        });
      } else {
        setState(() { _poiLoading = false; });
      }
    } catch (e) {
      setState(() { _poiLoading = false; });
    }
  }
}

// البيانات والمنطق
class _SearchResult {
  final double lat;
  final double lon;
  final String displayName;
  const _SearchResult({required this.lat, required this.lon, required this.displayName});
}

class _ZoomBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  const _ZoomBtn({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(40, 40),
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Color(0xFF2A3243))),
      ),
      onPressed: onPressed,
      child: Icon(icon, size: 20),
    );
  }
}

class _PoiMarker extends StatelessWidget {
  final Color color;
  const _PoiMarker({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 2, spreadRadius: 0.5)],
        ),
      ),
    );
  }
}

class _PoiCat {
  final String key;
  final String label;
  final Color color;
  final IconData icon;
  const _PoiCat({required this.key, required this.label, required this.color, required this.icon});
}

class _Poi {
  final double lat;
  final double lon;
  final String? name;
  final Map<String, String> tags;
  final String cat;
  final Color? color;
  const _Poi({required this.lat, required this.lon, this.name, required this.tags, required this.cat, this.color});
}

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

  Map<String, dynamic> toMap() => {
        'origin': {'lat': origin.lat, 'lng': origin.lng},
        'destination': {'lat': destination.lat, 'lng': destination.lng},
        'destLabel': destLabel,
        'arriveAtUtc': arriveAtUtc.toUtc().millisecondsSinceEpoch,
        'leaveAtUtc': leaveAtUtc.toUtc().millisecondsSinceEpoch,
        'travelMinutes': travelMinutes,
        'prepMinutes': prepMinutes,
        'delayMinutes': delayMinutes,
        'travelSource': travelSource,
      };

  static AppointmentState fromMap(Map<String, dynamic> m) => AppointmentState(
        origin: LatLng((m['origin']?['lat'] as num).toDouble(), (m['origin']?['lng'] as num).toDouble()),
        destination: LatLng((m['destination']?['lat'] as num).toDouble(), (m['destination']?['lng'] as num).toDouble()),
        destLabel: (m['destLabel'] as String?) ?? 'الوجهة المحددة',
        arriveAtUtc: DateTime.fromMillisecondsSinceEpoch((m['arriveAtUtc'] as num).toInt(), isUtc: true),
        leaveAtUtc: DateTime.fromMillisecondsSinceEpoch((m['leaveAtUtc'] as num).toInt(), isUtc: true),
        travelMinutes: (m['travelMinutes'] as num).toInt(),
        prepMinutes: (m['prepMinutes'] as num).toInt(),
        delayMinutes: (m['delayMinutes'] as num).toInt(),
        travelSource: m['travelSource'] as String?,
      );
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
// Use UTC math to avoid device timezone side-effects when persisting.
DateTime riyadhNowLocal() => DateTime.now().toUtc().add(const Duration(hours: 3));
DateTime riyadhLocalToUtc(DateTime local) {
  final asUtc = DateTime.utc(
    local.year, local.month, local.day, local.hour, local.minute, local.second, local.millisecond, local.microsecond,
  );
  return asUtc.subtract(const Duration(hours: 3));
}
DateTime utcToRiyadhLocal(DateTime utc) {
  final u = utc.toUtc();
  return u.add(const Duration(hours: 3));
}

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
    7: 'الأحد',/*hi there*/
  };
  final dow = days[local.weekday] ?? '';
  return '$dow ${formatDateArabic(local)} ${formatTime12Arabic(local)}';
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();
  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late bool _online;
  late TextEditingController _googleKey;
  late TextEditingController _hereKey;
  late TextEditingController _mapboxKey;
  String _provider = 'google';

  @override
  void initState() {
    super.initState();
    final box = Hive.box('settings');
    _online = box.get('online_traffic_enabled') == true;
    _googleKey = TextEditingController(text: (box.get('google_api_key') as String?) ?? '');
    _hereKey = TextEditingController(text: (box.get('here_api_key') as String?) ?? '');
    _mapboxKey = TextEditingController(text: (box.get('mapbox_access_token') as String?) ?? '');
    _provider = (box.get('traffic_provider') as String?) ?? 'google';
  }

  @override
  void dispose() {
    _googleKey.dispose();
    _hereKey.dispose();
    _mapboxKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.settings_outlined),
                const SizedBox(width: 8),
                const Expanded(child: Text('الإعدادات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(color: AppColors.border),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              value: _online,
              title: const Text('استخدام حركة المرور المباشرة'),
              subtitle: const Text('يتطلب مفتاح API مفعّل الفوترة. في حال عدم التفعيل سيتم استخدام تقدير محلي.'),
              onChanged: (v) => setState(() => _online = v),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _online
                  ? Column(
                      key: const ValueKey('g'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('المزوّد'),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          value: _provider,
                          items: const [
                            DropdownMenuItem(value: 'google', child: Text('Google Distance Matrix')),
                            DropdownMenuItem(value: 'here', child: Text('HERE Routing v8')),
                            DropdownMenuItem(value: 'mapbox', child: Text('Mapbox Directions Traffic')),
                          ],
                          onChanged: (v) => setState(() => _provider = v ?? 'google'),
                        ),
                        const SizedBox(height: 10),
                        if (_provider == 'google') ...[
                          const Text('Google API Key'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _googleKey,
                            obscureText: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            decoration: const InputDecoration(hintText: 'AIza...'),
                          ),
                        ] else if (_provider == 'here') ...[
                          const Text('HERE API Key'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _hereKey,
                            obscureText: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            decoration: const InputDecoration(hintText: 'hereapikey...'),
                          ),
                        ] else ...[
                          const Text('Mapbox Access Token'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _mapboxKey,
                            obscureText: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            decoration: const InputDecoration(hintText: 'pk.eyJ...'),
                          ),
                        ],
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _onSave,
                  style: AppButtons.primary(),
                  child: const Text('حفظ'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onSave() async {
    final box = Hive.box('settings');
    await box.put('online_traffic_enabled', _online);
    await box.put('traffic_provider', _provider);
    await box.put('google_api_key', _googleKey.text.trim());
    await box.put('here_api_key', _hereKey.text.trim());
    await box.put('mapbox_access_token', _mapboxKey.text.trim());
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}

class _SplashView extends StatefulWidget {
  const _SplashView();

  @override
  State<_SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<_SplashView> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _a1;
  late final Animation<double> _a2;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat(reverse: true);
    _a1 = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _a2 = CurvedAnimation(parent: _ctrl, curve: const Interval(0.2, 1.0, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF0B0D11), Color(0xFF0F1422)],
        ),
      ),
      alignment: Alignment.center,
      child: Stack(
        children: [
          // Soft animated blobs
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _a1,
              builder: (_, __) {
                final t1 = (_a1.value - 0.5) * 2; // -1..1
                final t2 = (_a2.value - 0.5) * 2;
                return Stack(
                  children: [
                    _blob(Offset(120 * t1, -60 * t2), const Color(0xFF1B2130), 220),
                    _blob(Offset(-140 * t2, 80 * t1), const Color(0xFF0F172A), 260),
                    _blob(Offset(40 * t2, 120 * t1), const Color(0xFF111827), 200),
                  ],
                );
              },
            ),
          ),
          // Content
          Align(
            alignment: Alignment.center,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.9, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      gradient: const RadialGradient(colors: [Color(0xFF1F2937), Color(0xFF0F141F)]),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 30, offset: const Offset(0, 14)),
                        const BoxShadow(color: Color(0x553B82F6), blurRadius: 20, spreadRadius: 2),
                      ],
                      border: Border.all(color: const Color(0xFF2A3243)),
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/images/app_logo.png',
                        width: 72,
                        height: 72,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.timelapse, size: 50, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'مؤقتك',
                    style: GoogleFonts.tajawal(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      decoration: TextDecoration.none,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 34,
                    child: DefaultTextStyle(
                      style: GoogleFonts.tajawal(
                        color: Colors.white70,
                        fontSize: 18,
                        height: 1.35,
                        decoration: TextDecoration.none,
                        fontWeight: FontWeight.w600,
                      ),
                      child: AnimatedTextKit(
                        isRepeatingAnimation: true,
                        repeatForever: true,
                        animatedTexts: [
                          FadeAnimatedText('تنظيم مواعيدك بذكاء', duration: const Duration(milliseconds: 1400)),
                          FadeAnimatedText('حساب وقت المغادرة بدقة', duration: const Duration(milliseconds: 1400)),
                          FadeAnimatedText('محلي بالكامل — بدون إنترنت', duration: const Duration(milliseconds: 1400)),
                        ],
                      ),
                    ),
                  ),
                  // Progress bar removed for a cleaner splash appearance
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blob(Offset offset, Color color, double size) {
    return Align(
      alignment: Alignment.center,
      child: Transform.translate(
        offset: offset,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.6),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 50, spreadRadius: 10),
            ],
          ),
        ),
      ),
    );
  }
}
