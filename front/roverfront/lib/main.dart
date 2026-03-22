// main.dart
//
// Fixes applied in this revision:
//   M-1 — Cold-start deep link race: _initDeepLinks() is awaited before
//          _checkSession() so the token is always stored before routing.
//   M-2 — Deep link token persisted to SharedPreferences so it survives
//          app kills (e.g. email confirmation flow).
//   L-4 — Social login buttons removed (were permanently "coming soon").
//   L-5 — "Remember me" checkbox removed (was a rendered no-op).

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';

import 'constants.dart';
import 'services/auth_service.dart';
import 'screens/welcome_page.dart';
import 'screens/forgot_password_page.dart';
import 'screens/reset_password_page.dart';
import 'screens/org_setup_page.dart';
import 'screens/user_home_page.dart';
import 'screens/driver_home_page.dart';
import 'screens/admin_home_page.dart';
import 'screens/user_guide_page.dart';
import 'widgets/auth_dialog.dart';

// ─────────────────────────────────────────────────────────────
// Global Supabase client accessor.
// ─────────────────────────────────────────────────────────────
final supabase = Supabase.instance.client;

// SharedPreferences key for the persisted deep-link org token
const _kPendingTokenKey = 'pending_org_token';

// ─────────────────────────────────────────────────────────────
// PendingLink — stores org token from a deep link until consumed.
// Token is also persisted to SharedPreferences so it survives
// an app kill between registration and email confirmation.
// ─────────────────────────────────────────────────────────────
class PendingLink {
  static String? orgToken;
  static String? orgName;

  /// Save token in memory AND to disk.
  static Future<void> setToken(String token) async {
    orgToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPendingTokenKey, token);
  }

  /// Load token from disk into memory (called at startup before routing).
  static Future<void> loadFromDisk() async {
    if (orgToken != null) return; // already in memory
    final prefs = await SharedPreferences.getInstance();
    orgToken = prefs.getString(_kPendingTokenKey);
  }

  /// Consume token — removes from memory and disk.
  static Future<void> clear() async {
    orgToken = null;
    orgName  = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPendingTokenKey);
  }
}

// ─────────────────────────────────────────────────────────────
// Maps a role string returned by login() to the correct screen.
// ─────────────────────────────────────────────────────────────
Widget destinationForRole(String role, {String? orgToken, String? orgName}) {
  switch (role) {
    case 'no_org':
      return OrgSetupPage(
        initialRole: 'user',
        orgToken:    orgToken,
        orgName:     orgName,
      );
    case 'admin':   return const AdminHomePage();
    case 'driver':  return const DriverHomePage();
    default:        return const UserHomePage();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'https://adswkssbhlqeuewxijep.supabase.co',
    ),
    anonKey: const String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFkc3drc3NiaGxxZXVld3hpamVwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwOTcyNTMsImV4cCI6MjA4ODY3MzI1M30.ciU00N7aQDF1hdsVOiEl1yBrD7R6IeV4qZ8cKPtEY2Q',
    ),
  );

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init skipped (run flutterfire configure): $e');
  }

  runApp(const RoverApp());
}

class RoverApp extends StatelessWidget {
  const RoverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rover',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSwatch().copyWith(secondary: Colors.blueAccent),
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const AuthGate(),
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// AuthGate — checks session on startup and handles deep links.
//
// Fix M-1: _initDeepLinks() is now awaited before _checkSession()
// so the cold-start token is always in PendingLink before routing.
// ─────────────────────────────────────────────────────────────
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checking        = true;
  bool _recoveryHandled = false;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<Uri>?       _linkSub;

  @override
  void initState() {
    super.initState();
    _authSub = supabase.auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      if (state.event == AuthChangeEvent.passwordRecovery &&
          !_recoveryHandled) {
        _recoveryHandled = true;
        setState(() => _checking = false);
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ResetPasswordPage()),
        );
      }
    });
    // Fix M-1: await deep links first so the token is in place
    // before _checkSession() makes routing decisions.
    _initDeepLinks().then((_) => _checkSession());
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _linkSub?.cancel();
    super.dispose();
  }

  // ── Deep link initialisation ───────────────────────────────
  Future<void> _initDeepLinks() async {
    final appLinks = AppLinks();

    // Fix M-2: load any token persisted from a previous session
    await PendingLink.loadFromDisk();

    // Cold-start deep link (app launched via rover.app/join/TOKEN tap)
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null) await _storeToken(initial);
    } catch (_) {}

    // Warm link (app already running, another link tapped)
    _linkSub = appLinks.uriLinkStream.listen((uri) async {
      await _storeToken(uri);
      _handleLinkWhileRunning(uri);
    });
  }

  Future<void> _storeToken(Uri uri) async {
    final token = _extractToken(uri);
    if (token != null) await PendingLink.setToken(token);
  }

  String? _extractToken(Uri uri) {
    final segments = uri.pathSegments;
    final joinIdx  = segments.indexOf('join');
    if (joinIdx >= 0 && joinIdx + 1 < segments.length) {
      return segments[joinIdx + 1];
    }
    return null;
  }

  void _handleLinkWhileRunning(Uri uri) {
    final token = _extractToken(uri);
    if (token == null || !mounted) return;

    final user = supabase.auth.currentUser;
    if (user == null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WelcomePage(orgToken: token),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "You're already in an organisation. Sign out to join a different one.",
          ),
          duration: Duration(seconds: 4),
          backgroundColor: Color(0xFF398AE5),
        ),
      );
    }
  }

  // ── Session check ──────────────────────────────────────────
  Future<void> _checkSession() async {
    if (!mounted || _recoveryHandled) return;

    // Web recovery-link detection
    final fragment = Uri.base.fragment;
    if (fragment.isNotEmpty) {
      final params = Uri.splitQueryString(fragment);
      if (params['type'] == 'recovery') {
        _recoveryHandled = true;
        if (mounted) setState(() => _checking = false);
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ResetPasswordPage()),
        );
        return;
      }
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _checking = false);
      return;
    }

    try {
      final profile = await supabase
          .from('profiles')
          .select('role, org_id')
          .eq('id', user.id)
          .single();

      if (!mounted || _recoveryHandled) return;
      final role = profile['org_id'] == null
          ? 'no_org'
          : profile['role'] as String;

      _navigateByRole(role);
    } catch (_) {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _navigateByRole(String role) {
    final token = PendingLink.orgToken;
    final name  = PendingLink.orgName;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            destinationForRole(role, orgToken: token, orgName: name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return const LoginPage(title: 'Rover Login Page');
  }
}

// ═════════════════════════════════════════════════════════════
// LoginPage
// Fixes L-4, L-5: social login buttons and "Remember me"
// checkbox removed — both were non-functional no-ops.
// ═════════════════════════════════════════════════════════════
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.title});
  final String title;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading  = false;
  final TextEditingController _emailController    = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email    = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
      _showError('Please enter a valid email address.');
      return;
    }
    if (password.length < 8) {
      _showError('Password must be at least 8 characters.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final role = await AuthService.login(email: email, password: password);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => destinationForRole(
            role,
            orgToken: PendingLink.orgToken,
            orgName:  PendingLink.orgName,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        _showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) => showErrorDialog(context, message);

  Widget _buildEmailTF() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Email', style: kLabelStyle),
        const SizedBox(height: 10.0),
        Container(
          alignment: Alignment.centerLeft,
          decoration: kBoxDecorationStyle,
          height: 60.0,
          child: TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(
                color: Colors.white, fontFamily: 'OpenSans'),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.only(top: 14.0),
              prefixIcon: Icon(Icons.email, color: Colors.white),
              hintText: 'Enter your Email',
              hintStyle: kHintTextStyle,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordTF() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Password', style: kLabelStyle),
        const SizedBox(height: 10.0),
        Container(
          alignment: Alignment.centerLeft,
          decoration: kBoxDecorationStyle,
          height: 60.0,
          child: TextField(
            controller: _passwordController,
            obscureText: true,
            style: const TextStyle(
                color: Colors.white, fontFamily: 'OpenSans'),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.only(top: 14.0),
              prefixIcon: Icon(Icons.lock, color: Colors.white),
              hintText: 'Enter your Password',
              hintStyle: kHintTextStyle,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForgotPasswordBtn() {
    return Container(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
        ),
        child: const Text('Forgot Password?', style: kLabelStyle),
      ),
    );
  }

  Widget _buildLoginBtn() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 25.0),
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          elevation: 5.0,
          padding: const EdgeInsets.all(15.0),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30.0)),
        ),
        child: _isLoading
            ? const CircularProgressIndicator(color: Color(0xFF527DAA))
            : const Text(
                'LOGIN',
                style: TextStyle(
                  color: Color(0xFF527DAA),
                  letterSpacing: 1.5,
                  fontSize: 18.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'OpenSans',
                ),
              ),
      ),
    );
  }

  Widget _buildSignupBtn() {
    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          children: const [
            Expanded(child: Divider(color: Colors.white54, thickness: 0.8)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'NEW HERE?',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Expanded(child: Divider(color: Colors.white54, thickness: 0.8)),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WelcomePage(
                  orgToken: PendingLink.orgToken,
                  orgName:  PendingLink.orgName,
                ),
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white, width: 2),
              padding: const EdgeInsets.all(15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
            child: const Text(
              'CREATE AN ACCOUNT',
              style: TextStyle(
                color: Colors.white,
                letterSpacing: 1.5,
                fontSize: 16.0,
                fontWeight: FontWeight.bold,
                fontFamily: 'OpenSans',
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Stack(
            children: <Widget>[
              Container(
                height: double.infinity,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF73AEF5),
                      Color(0xFF61A4F1),
                      Color(0xFF478DE0),
                      Color(0xFF398AE5),
                    ],
                    stops: [0.1, 0.4, 0.7, 0.9],
                  ),
                ),
              ),
              Positioned(
                top: 40,
                right: 12,
                child: SafeArea(
                  child: IconButton(
                    icon: const Icon(Icons.help_outline, color: Colors.white70),
                    tooltip: 'Help',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const UserGuidePage(),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: double.infinity,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40.0,
                    vertical: 120.0,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Text(
                        'Sign In',
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'OpenSans',
                          fontSize: 30.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 30.0),
                      _buildEmailTF(),
                      const SizedBox(height: 30.0),
                      _buildPasswordTF(),
                      _buildForgotPasswordBtn(),
                      _buildLoginBtn(),
                      _buildSignupBtn(),
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
