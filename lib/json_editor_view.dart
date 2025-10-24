import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/json.dart';
import 'package:flutter_highlight/themes/github.dart';

class JsonEditorView extends StatefulWidget {
  final String initialJson;
  final void Function(String updatedJson)? onChanged;
  const JsonEditorView({super.key, required this.initialJson, this.onChanged});

  @override
  State<JsonEditorView> createState() => _JsonEditorViewState();
}

class _JsonEditorViewState extends State<JsonEditorView> {
  late CodeController _codeController;

  @override
  void initState() {
    super.initState();
    _codeController = CodeController(
      text: widget.initialJson,
      language: json,
    );

    // Listen for changes
    _codeController.addListener(() {
      widget.onChanged?.call(_codeController.text);
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
      child: CodeTheme(
        data: CodeThemeData(styles: githubTheme),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: CodeField(
            controller: _codeController,
            textStyle: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}
