import 'package:flutter/material.dart';
import 'package:product_inventory/model/user.dart';
import 'package:product_inventory/service/auth_service.dart';
import 'package:product_inventory/shared/constant.dart';
import 'package:product_inventory/shared/loading.dart';
import 'package:product_inventory/shared/messenger.dart';
import 'package:product_inventory/shared/app_theme.dart';

class Register extends StatefulWidget {
  const Register({super.key, required this.toggleView});

  final VoidCallback toggleView;

  @override
  State<Register> createState() => _RegisterState();
}

class _RegisterState extends State<Register> {
  final AuthService _auth = AuthService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  UserRole _role = UserRole.customer;
  bool _loading = false;
  bool _hidePassword = true;
  String _error = '';

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      await _auth.register(
        email: _emailController.text,
        password: _passwordController.text,
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        role: _role,
      );
      // Success: the auth stream moves the app on; the Wrapper waits for the
      // profile and then routes by role.
    } catch (e) {
      debugPrint('Registration failed: $e');
      final String message = friendlyAuthError(e);
      // This widget may already be gone (the auth stream fires early), so
      // report through the root messenger as well.
      rootMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(message)),
      );
      if (!mounted) return;
      setState(() {
        _error = message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Loading();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(kShopName),
        actions: <Widget>[
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.black),
            icon: const Icon(Icons.person),
            onPressed: widget.toggleView,
            label: const Text('Sign In'),
          ),
        ],
      ),
      body: Container(
        padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 24.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                Text(
                  'Create New Account',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20.0),
                SegmentedButton<UserRole>(
                  segments: const <ButtonSegment<UserRole>>[
                    ButtonSegment<UserRole>(
                      value: UserRole.customer,
                      icon: Icon(Icons.shopping_bag_outlined),
                      label: Text('I want to buy'),
                    ),
                    ButtonSegment<UserRole>(
                      value: UserRole.seller,
                      icon: Icon(Icons.storefront_outlined),
                      label: Text('I want to sell'),
                    ),
                  ],
                  selected: <UserRole>{_role},
                  onSelectionChanged: (Set<UserRole> selection) {
                    setState(() => _role = selection.first);
                  },
                ),
                const SizedBox(height: 20.0),
                TextFormField(
                  controller: _firstNameController,
                  decoration: textInputDecoration.copyWith(
                    hintText: 'First Name',
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (String? val) =>
                      (val == null || val.trim().isEmpty)
                      ? 'Enter your first name'
                      : null,
                ),
                const SizedBox(height: 20.0),
                TextFormField(
                  controller: _lastNameController,
                  decoration: textInputDecoration.copyWith(
                    hintText: 'Last Name',
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (String? val) =>
                      (val == null || val.trim().isEmpty)
                      ? 'Enter your last name'
                      : null,
                ),
                const SizedBox(height: 20.0),
                TextFormField(
                  controller: _emailController,
                  decoration: textInputDecoration.copyWith(hintText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (String? val) =>
                      (val == null || val.trim().isEmpty)
                      ? 'Enter an email'
                      : null,
                ),
                const SizedBox(height: 20.0),
                TextFormField(
                  controller: _passwordController,
                  decoration: textInputDecoration.copyWith(
                    hintText: 'Password',
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
                  validator: (String? val) => (val == null || val.length < 6)
                      ? 'Use at least 6 characters'
                      : null,
                ),
                const SizedBox(height: 20.0),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pink,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _submit,
                  child: const Text('Register'),
                ),
                const SizedBox(height: 12.0),
                Text(
                  _error,
                  style: const TextStyle(color: Colors.red, fontSize: 14.0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
