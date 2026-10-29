import 'package:flutter/material.dart';

/// Lets code show a SnackBar even after the widget that started the work
/// has been disposed (e.g. Register is replaced by the home screen).
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
