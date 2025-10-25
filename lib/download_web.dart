// Only compiled for web
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

void downloadConfigWeb(Map<String, dynamic> data) {
  if (!kIsWeb) return;
  final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
  final bytes = utf8.encode(jsonStr);
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = 'bdui-config.json'
    ..click();
  html.Url.revokeObjectUrl(url);
}
