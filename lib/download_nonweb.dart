// download_stub.dart
import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';

/// Prompts the user to select where to save the JSON file.
Future<void> downloadConfigWeb(Map<String, dynamic> data) async {
  try {
    const fileName = 'bdui-config.json';
    const mimeType = 'application/json';

    // Ask user for where to save the file
    final saveLocation = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: [XTypeGroup(label: 'JSON', extensions: ['json'])],
    );

    if (saveLocation == null) {
      print('Save canceled by user.');
      return;
    }

    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    final fileData = XFile.fromData(
      utf8.encode(jsonStr),
      mimeType: mimeType,
      name: fileName,
    );
    String savePath = saveLocation.path;
    if(!savePath.endsWith(".json")){
      savePath += ".json";
    }

    await fileData.saveTo(savePath);
    print('File saved to: $savePath');
  } catch (e) {
    print('Download failed: $e');
  }
}
