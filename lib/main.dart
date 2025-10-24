
import 'package:bdui_builder/stage26_page.dart';
import 'package:flutter/material.dart';
// web-only download
// ignore: avoid_web_libraries_in_flutter

void main() {
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


