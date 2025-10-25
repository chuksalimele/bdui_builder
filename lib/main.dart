import 'dart:io';

import 'package:bdui_builder/stage26_page.dart';
import 'package:flutter/material.dart';
import 'package:window_size/window_size.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    final screen = await getCurrentScreen();
    if (screen != null) {
      final frame = screen.visibleFrame;
      final width = frame.width * 0.95;
      final height = frame.height * 0.95;
      final left = frame.left + (frame.width - width) / 2;
      final top = frame.top + (frame.height - height) / 2;

      setWindowFrame(Rect.fromLTWH(left, top, width, height));
      setWindowMinSize(Size(width * 0.5, height * 0.5));
      setWindowTitle('BDUI Builder');
    }
  }
  runApp(const BDUIApp());
}

class BDUIApp extends StatelessWidget {
  const BDUIApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BDUI Builder - Stage2.6',
      theme: ThemeData(useMaterial3: true),
      home: const Stage26Page(),
      debugShowCheckedModeBanner: false,
    );
  }
}
