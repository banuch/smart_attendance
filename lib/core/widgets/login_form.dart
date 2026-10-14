import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Email / password sign-in used by both the employee app and admin panel.
class LoginForm extends StatefulWidget {
  const LoginForm({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email first.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        setState(() => _error = 'Password reset email sent to $email.');
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _message(e));
    }
  }

  String _message(FirebaseAuthException e) => switch (e.code) {
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' => 'Incorrect email or password.',
    'user-disabled' => 'This account has been disabled.',
    'too-many-requests' => 'Too many attempts. Try again later.',
    'network-request-failed' => 'No internet connection.',
    _ => e.message ?? 'Sign-in failed.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.fingerprint,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.subtitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) =>
                      (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter your password' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign in'),
                ),
                TextButton(
                  onPressed: _busy ? null : _forgotPassword,
                  child: const Text('Forgot password?'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen message with an optional sign-out button.
class BlockedScreen extends StatelessWidget {
  const BlockedScreen({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => FirebaseAuth.instance.signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
