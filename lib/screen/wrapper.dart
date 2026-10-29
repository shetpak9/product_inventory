import 'package:flutter/material.dart';
import 'package:product_inventory/model/user.dart';
import 'package:product_inventory/screen/authenticate/auth_screen.dart';
import 'package:product_inventory/screen/home/mainscreen.dart';
import 'package:product_inventory/screen/seller/seller_home.dart';
import 'package:product_inventory/service/auth_service.dart';
import 'package:product_inventory/service/database.dart';
import 'package:provider/provider.dart';

class Wrapper extends StatelessWidget {
  const Wrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final UserId? user = Provider.of<UserId?>(context);

    if (user == null) {
      return const Authenticate();
    }
    // Keyed by uid so switching accounts always starts from fresh state.
    return _SignedInGate(key: ValueKey<String>(user.uid), uid: user.uid);
  }
}

/// Loads the profile once, then routes by role.
class _SignedInGate extends StatefulWidget {
  const _SignedInGate({super.key, required this.uid});

  final String uid;

  @override
  State<_SignedInGate> createState() => _SignedInGateState();
}

class _SignedInGateState extends State<_SignedInGate> {
  late final Stream<UserData?> _profileStream =
      DatabaseService().userProfileStream(widget.uid);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserData?>(
      stream: _profileStream,
      builder: (BuildContext context, AsyncSnapshot<UserData?> snapshot) {
        if (snapshot.hasError) {
          return _GateMessage(
            message: 'Could not load your profile.\n${snapshot.error}',
          );
        }

        final UserData? profile = snapshot.data;
        if (profile == null) {
          // Still loading, or registration is still writing the profile.
          return const _GateMessage();
        }

        return switch (profile.role) {
          UserRole.seller => SellerHome(profile: profile),
          UserRole.customer => const MainScreen(),
        };
      },
    );
  }
}

class _GateMessage extends StatelessWidget {
  const _GateMessage({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final String? text = message;

    return Scaffold(
      backgroundColor: const Color(0xFFFDF8F0),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (text == null)
                const CircularProgressIndicator()
              else
                Text(text, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => AuthService().signOut(),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
