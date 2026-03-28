import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dynamic_photo_chat_flutter/ui/screens/login_screen.dart';

void main() {
  testWidgets('Login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.text('登录'), findsOneWidget);
  });
}
