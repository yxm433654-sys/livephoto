import 'package:vox_flutter/state/app_state.dart';
import 'package:vox_flutter/ui/screens/session_list_screen.dart';
import 'package:vox_flutter/ui/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: 'Vox',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home:
          state.session == null ? const LoginScreen() : const SessionListScreen(),
    );
  }
}



