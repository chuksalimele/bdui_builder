import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_json_viewer/flutter_json_viewer.dart';
import '../providers/json_provider.dart';

class BDUIStage2Page extends StatefulWidget {
  const BDUIStage2Page({super.key});

  @override
  State<BDUIStage2Page> createState() => _BDUIStage2PageState();
}

class _BDUIStage2PageState extends State<BDUIStage2Page> {
  late Map<String, dynamic> _tempJson;
  final TextEditingController _rawEditorController = TextEditingController();
  final FocusNode _rawEditorFocus = FocusNode();

  // local undo/redo for raw editor
  final List<String> _jsonHistory = [];
  int _jsonHistoryIndex = -1;
  static const int _kJsonHistoryLimit = 100;

  bool _rawEditorDirty = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _tempJson = {};

    // when raw editor loses focus, auto-save if dirty
    _rawEditorFocus.addListener(() {
      if (!_rawEditorFocus.hasFocus) {
        _saveRawEditorIfDirty();
      }
    });

    // track user edits into history (debounced)
    _rawEditorController.addListener(() {
      if (!_rawEditorFocus.hasFocus) return; // programmatic updates shouldn't push
      _rawEditorDirty = true;
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        _pushJsonHistory(_rawEditorController.text);
      });
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _rawEditorController.dispose();
    _rawEditorFocus.dispose();
    super.dispose();
  }

  // ---------- history ----------
  void _pushJsonHistory(String txt) {
    if (_jsonHistoryIndex >= 0 &&
        _jsonHistoryIndex < _jsonHistory.length &&
        _jsonHistory[_jsonHistoryIndex] == txt) {
      return;
    }
    // drop forward history if any
    if (_jsonHistoryIndex < _jsonHistory.length - 1) {
      _jsonHistory.removeRange(_jsonHistoryIndex + 1, _jsonHistory.length);
    }
    _jsonHistory.add(txt);
    if (_jsonHistory.length > _kJsonHistoryLimit) _jsonHistory.removeAt(0);
    _jsonHistoryIndex = _jsonHistory.length - 1;
  }

  void _jsonUndo() {
    if (_jsonHistoryIndex <= 0) return;
    _jsonHistoryIndex--;
    _setRawEditorTextProgrammatic(_jsonHistory[_jsonHistoryIndex]);
  }

  void _jsonRedo() {
    if (_jsonHistoryIndex < 0 || _jsonHistoryIndex >= _jsonHistory.length - 1)
      return;
    _jsonHistoryIndex++;
    _setRawEditorTextProgrammatic(_jsonHistory[_jsonHistoryIndex]);
  }

  void _setRawEditorTextProgrammatic(String txt) {
    // programmatic set without marking dirty or adding history
    final hadFocus = _rawEditorFocus.hasFocus;
    _rawEditorFocus.canRequestFocus = false;
    _rawEditorController.text = txt;
    _rawEditorDirty = false;
    // restore focus ability
    _rawEditorFocus.canRequestFocus = true;
    if (hadFocus) _rawEditorFocus.requestFocus();
  }

  // ---------- I/O helpers ----------
  void _loadFromProvider(JsonProvider provider, {bool pushHistory = false}) {
    final Map<String, dynamic> data = Map<String, dynamic>.from(provider.data);
    if (pushHistory) {
      try {
        final snap = const JsonEncoder.withIndent('  ').convert(data);
        _pushJsonHistory(snap);
      } catch (_) {}
    }
    setState(() {
      _tempJson = data;
      final pretty = const JsonEncoder.withIndent('  ').convert(_tempJson);
      _setRawEditorTextProgrammatic(pretty);
      _jsonHistory.clear();
      _jsonHistory.add(pretty);
      _jsonHistoryIndex = 0;
      _rawEditorDirty = false;
    });
  }

  Future<void> _saveRawEditorIfDirty() async {
    if (!_rawEditorDirty) return;
    final provider = context.read<JsonProvider>();
    final text = _rawEditorController.text;
    try {
      final parsed = jsonDecode(text);
      if (parsed is Map<String, dynamic>) {
        provider.update(parsed);
        _loadFromProvider(provider, pushHistory: true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Saved JSON to model'),
          duration: Duration(milliseconds: 1000),
        ));
      } else {
        _showError('Top-level JSON must be an object/map');
      }
    } catch (e) {
      _showError('Invalid JSON: $e');
    }
  }

  void _applySave() {
    _saveRawEditorIfDirty();
  }

  void _resetToProvider() {
    final provider = context.read<JsonProvider>();
    _loadFromProvider(provider, pushHistory: false);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<JsonProvider>();
    // ensure editor content follows provider when not dirty
    if (!_rawEditorDirty) {
      // do not call setState here. Just update controller programmatically.
      final pretty = const JsonEncoder.withIndent('  ').convert(provider.data);
      // only update controller if differs (avoid cursor jump)
      if (_rawEditorController.text != pretty) {
        _setRawEditorTextProgrammatic(pretty);
        // initialize history
        if (_jsonHistory.isEmpty) {
          _jsonHistory.add(pretty);
          _jsonHistoryIndex = 0;
        }
      }
      _tempJson = Map<String, dynamic>.from(provider.data);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('BDUI Builder – Stage 2.5 (Text editor)'),
        actions: [
          Tooltip(message: 'Undo (editor)'),
          IconButton(
            onPressed: _jsonUndo,
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
          ),
          Tooltip(message: 'Redo (editor)'),
          IconButton(
            onPressed: _jsonRedo,
            icon: const Icon(Icons.redo),
            tooltip: 'Redo',
          ),
          const SizedBox(width: 8),
          Tooltip(message: 'Save JSON to model'),
          IconButton(
            onPressed: _applySave,
            icon: const Icon(Icons.save),
            tooltip: 'Save',
          ),
          Tooltip(message: 'Reset editor to last saved model'),
          IconButton(
            onPressed: _resetToProvider,
            icon: const Icon(Icons.restore),
            tooltip: 'Reset',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final leftWidth = (maxWidth * 0.34).clamp(260.0, 620.0);
        final rightWidth = (maxWidth * 0.36).clamp(320.0, 720.0);

        return Row(children: [
          // Sidebar / Inspector tree
          ConstrainedBox(
            constraints: BoxConstraints.tightFor(width: leftWidth),
            child: _buildInspector(provider),
          ),

          // Center visual area (placeholder for visual editor)
          Expanded(
            child: Container(
              color: Colors.white,
              child: Column(children: [
                Container(
                  height: 56,
                  color: Colors.grey.shade50,
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Text('Selected node editor (visual)', style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      TextButton(onPressed: () => _showValidation(provider), child: const Text('Validate')),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(child: Text('Visual Inspector / Form goes here', style: Theme.of(context).textTheme.bodyLarge)),
                ),
              ]),
            ),
          ),

          // Right: Raw JSON inspector / editor
          ConstrainedBox(
            constraints: BoxConstraints.tightFor(width: rightWidth),
            child: _buildRawInspector(),
          ),
        ]);
      }),
    );
  }

  Widget _buildInspector(JsonProvider provider) {
    return Container(
      color: Colors.grey.shade100,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Inspector', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(children: [
              Tooltip(message: 'Copy config to clipboard'),
              IconButton(
                onPressed: () async {
                  final text = const JsonEncoder.withIndent('  ').convert(provider.data);
                  await Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                },
                icon: const Icon(Icons.copy),
              ),
            ]),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: JsonViewer(provider.data),
          ),
        ),
      ]),
    );
  }

  Widget _buildRawInspector() {
    return Container(
      color: Colors.grey.shade50,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.all(12.0),
          child: Text('JSON Inspector / Editor', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const Divider(height: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(children: [
              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    child: SelectableText(_rawEditorController.text, style: const TextStyle(fontFamily: 'monospace')),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Actual editable textfield (hidden below the selectable text for read-only view experience)
              Expanded(
                child: Focus(
                  focusNode: _rawEditorFocus,
                  child: TextField(
                    controller: _rawEditorController,
                    focusNode: _rawEditorFocus,
                    maxLines: null,
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Edit JSON here'),
                    style: const TextStyle(fontFamily: 'monospace'),
                    keyboardType: TextInputType.multiline,
                    onSubmitted: (_) => _saveRawEditorIfDirty(),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  void _showValidation(JsonProvider provider) {
    // quick validation example
    try {
      const JsonEncoder.withIndent('  ').convert(provider.data);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document valid JSON')));
    } catch (e) {
      _showError('Validation failed: $e');
    }
  }
}
