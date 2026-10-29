import 'package:flutter/material.dart';
import 'package:product_inventory/service/auth_service.dart';
import 'package:product_inventory/shared/app_theme.dart';
import 'package:product_inventory/shared/loading.dart';
import 'package:product_inventory/shared/messenger.dart';

class SignIn extends StatefulWidget {
  const SignIn({super.key, required this.toggleView});

  final VoidCallback toggleView;

  @override
  State<SignIn> createState() => _SignInState();
}

class _SignInState extends State<SignIn> {
  final AuthService _auth = AuthService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _loading = false;
  bool _hidePassword = true;
  String _error = '';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final result = await _auth.signIn(
        _emailController.text,
        _passwordController.text,
      );
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _error = 'Invalid email or password.';
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyAuthError(error);
        _loading = false;
      });
    }
  }

  Future<void> _forgotPassword() async {
    final TextEditingController emailController = TextEditingController(
      text: _emailController.text.trim(),
    );
    final String? email = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Reset password'),
        content: TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(emailController.text.trim()),
            child: const Text('Send reset link'),
          ),
        ],
      ),
    );
    emailController.dispose();
    if (!mounted || email == null || email.isEmpty) return;

    try {
      await _auth.sendPasswordResetEmail(email);
    } catch (error) {
      debugPrint('Password reset request failed: $error');
    }
    if (!mounted) return;
    rootMessengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Text(
          'If an account exists for that email, a password reset link has been sent.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Loading();

    return Scaffold(
      appBar: AppBar(title: const Text(kShopName)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Login / Signup',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text('Email'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      hintText: 'Email',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: (String? value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter an email address.';
                      }
                      if (!value.contains('@')) {
                        return 'Enter a valid email address.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  const Text('Password'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      hintText: 'Password',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                      suffixIcon: IconButton(
                        tooltip: _hidePassword
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: () {
                          setState(() => _hidePassword = !_hidePassword);
                        },
                        icon: Icon(
                          _hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    obscureText: _hidePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _signIn(),
                    validator: (String? value) => value == null || value.isEmpty
                        ? 'Enter your password.'
                        : null,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _forgotPassword,
                      child: const Text('Forgot password?'),
                    ),
                  ),
                  if (_error.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      _error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _signIn,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Login'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: widget.toggleView,
                    child: const Text('Create New Account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
