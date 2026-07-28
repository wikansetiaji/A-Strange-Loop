import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:a_strange_loop/widgets/animations.dart';
import 'package:a_strange_loop/theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  String? _error;
  bool _loading = false;
  late AnimationController _entranceCtrl;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeIn = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.easeOut,
    );
    _entranceCtrl.forward();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final provider = GoogleAuthProvider();
      final cred = await _auth.signInWithPopup(provider);
      if (cred.user?.email != 'wikansetiaji@gmail.com') {
        await _auth.signOut();
        setState(() {
          _error = 'This app is private. Access is restricted to the owner.';
        });
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = e.message ?? 'Sign-in failed';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: FadeTransition(
          opacity: _fadeIn,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.outline, width: 1.5),
                    ),
                    child: Column(
                      children: [
                        PulsingLoop(
                          size: 56,
                          color: cs.primary,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'A STRANGE\nLOOP',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.appTitle(context).copyWith(
                            fontSize: 30,
                            height: 1.0,
                            letterSpacing: 1.0,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(height: 1, color: cs.primary),
                        const SizedBox(height: 12),
                        Text(
                          'Your personal reading companion',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body(context).copyWith(
                            color: cs.onSurface.withAlpha(150),
                            fontSize: 13,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _signInWithGoogle,
                    icon: _loading
                        ? BlockLoader(width: 8, height: 12, color: cs.primary)
                        : Icon(Icons.arrow_forward_sharp,
                            size: 16, color: cs.primary),
                    label: Text(
                      'SIGN IN WITH GOOGLE',
                      style: AppTextStyles.body(context).copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        letterSpacing: 1.2,
                        color: cs.onSurface,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: cs.outline, width: 1.5),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: cs.error, width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_sharp,
                              size: 16, color: cs.error),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
