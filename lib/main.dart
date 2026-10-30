import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:product_inventory/model/user.dart';
import 'package:product_inventory/screen/wrapper.dart';
import 'package:product_inventory/service/auth_service.dart';
import 'package:product_inventory/service/order_notifier.dart';
import 'package:product_inventory/service/payment_link_service.dart';
import 'package:product_inventory/shared/app_theme.dart';
import 'package:product_inventory/shared/messenger.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (error) {
    debugPrint('Firebase initialization failed: $error');
  }

  try {
    await OrderNotifier.instance.initialize();
  } catch (error) {
    debugPrint('Local notification initialization failed: $error');
  }
  await PaymentLinkService.instance.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    late final Stream<UserId?> userStream;
    late final UserId? initialUser;

    try {
      final AuthService auth = AuthService();
      userStream = auth.userStream;
      initialUser = auth.currentUser;
    } catch (_) {
      userStream = const Stream<UserId?>.empty();
      initialUser = null;
    }

    return StreamProvider<UserId?>.value(
      value: userStream,
      // Seed with the current user so signed-in users never flash the login screen.
      initialData: initialUser,
      child: MaterialApp(
        scaffoldMessengerKey: rootMessengerKey,
        theme: buildAppTheme(),
        home: const Wrapper(),
      ),
    );
  }
}
