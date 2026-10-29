import 'package:flutter/material.dart';
import 'package:product_inventory/screen/authenticate/register.dart';
import 'package:product_inventory/screen/authenticate/sign_in.dart';

class Authenticate extends StatefulWidget {
  const Authenticate({super.key});

  @override
  State<Authenticate> createState() => _AuthenticateState();
}

class _AuthenticateState extends State<Authenticate> {
  bool _showSignIn = true;

  void _toggleView() {
    setState(() => _showSignIn = !_showSignIn);
  }

  @override
  Widget build(BuildContext context) {
    return _showSignIn
        ? SignIn(toggleView: _toggleView)
        : Register(toggleView: _toggleView);
  }
}
