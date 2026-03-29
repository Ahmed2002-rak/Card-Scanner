import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show cameras;
import '../constants/app_version.dart';
import '../services/secure_licensing.dart';
import 'history_screen.dart';
import 'scan_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'activation_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppShell
// ─────────────────────────────────────────────────────────────────────────────
class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  bool _isActivated = true;
  bool _isKilled = false;
  bool _isUpdateForced = false; // blocks app until user downloads new version

  StreamSubscription? _licenseSub;
  StreamSubscription? _settingsSub;

  String? _announcementText;
  String? _announcementId;
  String _supportLink = 'https://t.me/your_default_support';
  String _apkUrl = '';

  // Brand palette (shared with ActivationScreen)
  static const _indigo = Color(0xFF1A237E);
  static const _accent = Color(0xFFFFC107);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  // ── Startup sequence ───────────────────────────────────────────────────────

  Future<void> _bootstrap() async {
    // 1. Check update before anything else (non-blocking on error)
    _checkForUpdates();

    // 2. Check local activation state
    final activated = await SecureLicensing.isActivated();
    if (!mounted) return;
    setState(() => _isActivated = activated);

    if (activated) {
      await _initListeners();
      _checkExpiryWarning();
    }
  }

  Future<void> _checkForUpdates() async {
    final status = await SecureLicensing.checkForUpdate(kAppVersion);
    if (!mounted || !status.hasUpdate) return;

    setState(() {
      _apkUrl = status.apkUrl;
      if (status.isForced) _isUpdateForced = true;
    });

    if (!status.isForced) {
      // Small delay so the app renders before the popup appears
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) _showOptionalUpdateDialog(status);
    }
  }

  // ── Listeners ──────────────────────────────────────────────────────────────

  Future<void> _cancelListeners() async {
    await _licenseSub?.cancel();
    await _settingsSub?.cancel();
    _licenseSub = null;
    _settingsSub = null;
  }

  Future<void> _initListeners() async {
    await _cancelListeners();
    final deviceId = await SecureLicensing.getDeviceId();

    // License stream — real-time revocation / block / expiry
    if (deviceId.isNotEmpty) {
      _licenseSub = SecureLicensing.getLicenseSnapshotStream(deviceId).listen((
        doc,
      ) async {
        if (doc == null || !doc.exists) {
          if (await SecureLicensing.isActivated()) {
            await SecureLicensing.deactivate();
            if (mounted) setState(() => _isActivated = false);
          }
          return;
        }

        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'] as String?;
        bool isExpired = false;

        if (data['expiryDate'] != null) {
          final expiry = (data['expiryDate'] as Timestamp).toDate();
          if (DateTime.now().isAfter(expiry)) isExpired = true;
        }

        if (status == 'blocked' || status == 'deleted' || isExpired) {
          await SecureLicensing.deactivate();
          if (mounted) {
            setState(() => _isActivated = false);
            _showRevokedDialog(isExpired ? 'expired' : 'revoked');
          }
        } else if (status == 'active' && !isExpired) {
          if (mounted) setState(() => _isActivated = true);
        }
      }, onError: (_) {});
    }

    // Settings stream — kill switch, announcement, support link, update info
    _settingsSub = SecureLicensing.getSettingsStream().listen((doc) {
      if (!doc.exists || !mounted) return;
      final data = doc.data() as Map<String, dynamic>;

      setState(() {
        _isKilled = data['killSwitch'] ?? false;
        _supportLink = data['supportLink'] ?? _supportLink;
        _apkUrl = data['apkUrl'] ?? _apkUrl;
        _announcementText = data['announcement'];
        _announcementId = data['announcementId'];
      });

      // Real-time forced-update enforcement
      final latest = (data['latestVersion'] ?? '') as String;
      final min = (data['minVersion'] ?? '') as String;
      if (min.isNotEmpty) {
        final nowForced = SecureLicensing.checkVersionForced(kAppVersion, min);
        if (nowForced && mounted) setState(() => _isUpdateForced = true);
      }

      if (_announcementText != null && _announcementText!.isNotEmpty) {
        _checkAndShowAnnouncement(_announcementText!, _announcementId);
      }
    });
  }

  // ── Expiry Warning ─────────────────────────────────────────────────────────

  Future<void> _checkExpiryWarning() async {
    try {
      final key = await SecureLicensing.getStoredKey();
      if (key == null) return;

      final result = await FirebaseFirestore.instance
          .collection('licenses')
          .where('key', isEqualTo: key)
          .limit(1)
          .get();

      if (result.docs.isEmpty) return;
      final data = result.docs.first.data();
      if (data['expiryDate'] == null) return;

      final expiry = (data['expiryDate'] as Timestamp).toDate();
      final daysLeft = expiry.difference(DateTime.now()).inDays;

      if (await SecureLicensing.shouldShowExpiryWarning(daysLeft) && mounted) {
        await SecureLicensing.markExpiryWarningShown();
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) _showExpiryDialog(daysLeft);
      }
    } catch (_) {}
  }

  // ── Announcement ───────────────────────────────────────────────────────────

  Future<void> _checkAndShowAnnouncement(String text, String? id) async {
    if (!await SecureLicensing.shouldShowAnnouncement(id)) return;
    if (!mounted) return;
    _showDialog(
      icon: Icons.campaign_rounded,
      iconBg: _indigo.withOpacity(0.12),
      iconColor: _indigo,
      title: 'Announcement',
      body: text,
      actions: [
        _DialogBtn(
          label: 'Got it',
          isPrimary: true,
          onTap: () {
            if (id != null) SecureLicensing.markAnnouncementRead(id);
          },
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ██  DIALOGS  ██
  // A single _showDialog() helper powers every popup in the app.
  // ─────────────────────────────────────────────────────────────────────────

  void _showDialog({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String body,
    required List<_DialogBtn> actions,
    bool barrierDismissible = true,
  }) {
    showDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (ctx) => _AppDialog(
        icon: icon,
        iconBg: iconBg,
        iconColor: iconColor,
        title: title,
        body: body,
        actions: actions,
      ),
    );
  }

  void _showRevokedDialog(String type) {
    final isExpired = type == 'expired';
    _showDialog(
      barrierDismissible: false,
      icon: isExpired ? Icons.timer_off_rounded : Icons.block_rounded,
      iconBg: (isExpired ? Colors.orange : Colors.red).withOpacity(0.12),
      iconColor: isExpired ? Colors.orange : Colors.red,
      title: isExpired ? 'Licence Expired' : 'Licence Revoked',
      body: isExpired
          ? 'Your licence has expired. Please contact support to renew and continue using the app.'
          : 'Your access has been disabled by the administrator. Contact support or use a different key.',
      actions: [
        _DialogBtn(label: 'Contact Support', onTap: _launchSupport),
        _DialogBtn(
          label: 'Enter New Key',
          isPrimary: true,
          onTap: () => setState(() => _isActivated = false),
        ),
      ],
    );
  }

  void _showExpiryDialog(int daysLeft) {
    final msg = daysLeft == 0
        ? 'Your licence expires today! Renew now to avoid losing access.'
        : 'Your licence expires in $daysLeft day${daysLeft == 1 ? '' : 's'}. Renew before it runs out.';
    _showDialog(
      icon: Icons.access_time_rounded,
      iconBg: Colors.orange.withOpacity(0.12),
      iconColor: Colors.orange,
      title: 'Expiring Soon',
      body: msg,
      actions: [
        _DialogBtn(label: 'Dismiss', onTap: () {}),
        _DialogBtn(
          label: 'Renew Now',
          isPrimary: true,
          color: Colors.orange,
          onTap: _launchSupport,
        ),
      ],
    );
  }

  void _showOptionalUpdateDialog(UpdateStatus status) {
    _showDialog(
      icon: Icons.system_update_rounded,
      iconBg: Colors.teal.withOpacity(0.12),
      iconColor: Colors.teal,
      title: 'Update Available',
      body:
          'Version ${status.latestVersion} is available.\n\n${status.updateNotes.isNotEmpty ? status.updateNotes : "Download the latest version for new features and improvements."}',
      actions: [
        _DialogBtn(label: 'Later', onTap: () {}),
        _DialogBtn(
          label: 'Download',
          isPrimary: true,
          color: Colors.teal,
          onTap: _launchApkUrl,
        ),
      ],
    );
  }

  // ── URL helpers ───────────────────────────────────────────────────────────

  void _launchSupport() {
    String url = _supportLink;
    if (!url.startsWith('http'))
      url = 'https://t.me/${url.replaceAll('@', '')}';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _launchApkUrl() {
    if (_apkUrl.isEmpty) return;
    launchUrl(Uri.parse(_apkUrl), mode: LaunchMode.externalApplication);
  }

  void _onActivated() {
    setState(() => _isActivated = true);
    _initListeners();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _licenseSub?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Priority: Kill Switch → Forced Update → Activation → App
    if (_isKilled) return _buildKillSwitchScreen();
    if (_isUpdateForced) return _buildForcedUpdateScreen();
    if (!_isActivated) return ActivationScreen(onActivated: _onActivated);
    return _buildMainApp();
  }

  // ── Full-screen states ────────────────────────────────────────────────────

  Widget _buildKillSwitchScreen() => _FullScreenState(
    icon: Icons.warning_amber_rounded,
    iconColor: Colors.red,
    title: 'App Temporarily Disabled',
    subtitle:
        'A major update or maintenance is in progress.\nPlease check back later.',
    buttonLabel: 'Contact Support',
    onButton: _launchSupport,
  );

  Widget _buildForcedUpdateScreen() => _FullScreenState(
    icon: Icons.system_update_rounded,
    iconColor: Colors.teal,
    title: 'Update Required',
    subtitle:
        'A critical update is required to continue.\nTap below to download the latest version.',
    buttonLabel: 'Download Update',
    onButton: _launchApkUrl,
    secondaryLabel: 'v$kAppVersion installed — update required',
  );

  Widget _buildMainApp() {
    final pages = [
      ScanTab(
        cameras: cameras,
        onGoHistory: () => setState(() => _index = 1),
        isActivated: _isActivated,
      ),
      HistoryTab(isActivated: _isActivated),
      const SearchTab(),
      const SettingsTab(),
    ];
    return Scaffold(
      body: SafeArea(top: false, child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_rounded),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AppDialog — shared beautiful dialog used for every popup in the app
// ─────────────────────────────────────────────────────────────────────────────
class _DialogBtn {
  final String label;
  final bool isPrimary;
  final Color? color;
  final VoidCallback onTap;

  const _DialogBtn({
    required this.label,
    required this.onTap,
    this.isPrimary = false,
    this.color,
  });
}

class _AppDialog extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String body;
  final List<_DialogBtn> actions;

  const _AppDialog({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon circle
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(shape: BoxShape.circle, color: iconBg),
              child: Icon(icon, size: 38, color: iconColor),
            ),
            const SizedBox(height: 20),
            // Title
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
                height: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            // Body
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.65,
              ),
            ),
            const SizedBox(height: 28),
            // Actions
            if (actions.length == 1)
              _buildBtn(context, actions.first, fullWidth: true)
            else
              Row(
                children: actions
                    .map(
                      (a) => Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: a == actions.first ? 0 : 6,
                            right: a == actions.last ? 0 : 6,
                          ),
                          child: _buildBtn(context, a),
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBtn(
    BuildContext context,
    _DialogBtn btn, {
    bool fullWidth = false,
  }) {
    final primaryColor = btn.color ?? const Color(0xFF1A237E);
    final child = Text(
      btn.label,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: btn.isPrimary ? Colors.white : const Color(0xFF374151),
      ),
    );

    if (btn.isPrimary) {
      return SizedBox(
        width: fullWidth ? double.infinity : null,
        height: 48,
        child: ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            btn.onTap();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: child,
        ),
      );
    }

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: 48,
      child: TextButton(
        onPressed: () {
          Navigator.pop(context);
          btn.onTap();
        },
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FullScreenState — used for Kill Switch and Forced Update screens
// ─────────────────────────────────────────────────────────────────────────────
class _FullScreenState extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onButton;
  final String? secondaryLabel;

  const _FullScreenState({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onButton,
    this.secondaryLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1547),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(36),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: iconColor.withOpacity(0.12),
                    border: Border.all(
                      color: iconColor.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(icon, size: 50, color: iconColor),
                ),
                const SizedBox(height: 32),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: onButton,
                    icon: const Icon(Icons.open_in_new_rounded, size: 20),
                    label: Text(
                      buttonLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: iconColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
                if (secondaryLabel != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    secondaryLabel!,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
