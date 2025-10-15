// BDUI Builder - Stage 1 (final fixes)
// - Fixed: Inspector horizontal scrollbar interactive (desktop drag/click)
// - Fixed: auto-center when node is expanded (uses title GlobalKey + onExpansionChanged)
// - Preserves all prior functionality

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Web-only import for download. Ignore lint for non-web builds.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void main() {
  runApp(const BDUIApp());
}

class BDUIApp extends StatelessWidget {
  const BDUIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BDUI Builder - Stage1 Fixed',
      theme: ThemeData(useMaterial3: true),
      home: const BDUIStage1Page(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class JsonNavigator {
  final Map<String, dynamic> root;
  JsonNavigator(this.root);

  dynamic getNode(String path) {
    if (path.isEmpty) return root;
    final parts = path.split('/');
    dynamic cursor = root;
    for (final p in parts) {
      if (cursor == null) return null;
      if (cursor is Map<String, dynamic>) {
        cursor = cursor[p];
      } else if (cursor is List) {
        final idx = int.tryParse(p);
        if (idx == null) return null;
        if (idx < 0 || idx >= cursor.length) return null;
        cursor = cursor[idx];
      } else {
        return null;
      }
    }
    return cursor;
  }

  bool setNode(String path, dynamic value) {
    if (path.isEmpty) return false;
    final parts = path.split('/');
    dynamic cursor = root;
    for (int i = 0; i < parts.length - 1; i++) {
      final p = parts[i];
      if (cursor is Map<String, dynamic>) {
        cursor = cursor[p];
      } else if (cursor is List) {
        final idx = int.tryParse(p);
        if (idx == null) return false;
        cursor = cursor[idx];
      } else {
        return false;
      }
    }
    final last = parts.last;
    if (cursor is Map<String, dynamic>) {
      cursor[last] = value;
      return true;
    } else if (cursor is List) {
      final idx = int.tryParse(last);
      if (idx == null) return false;
      if (idx < 0 || idx >= cursor.length) return false;
      cursor[idx] = value;
      return true;
    }
    return false;
  }
}

class BDUIStage1Page extends StatefulWidget {
  const BDUIStage1Page({super.key});

  @override
  State<BDUIStage1Page> createState() => _BDUIStage1PageState();
}

class _BDUIStage1PageState extends State<BDUIStage1Page> {
  Map<String, dynamic> _root = {};
  String? _selectedPath;
  dynamic _selectedValue;
  final TextEditingController _editorController = TextEditingController();

  // keys and controllers for sidebar scrolling and ensureVisible
  final Map<String, GlobalKey> _tileKeys = {};
  final Map<String, GlobalKey> _titleKeys = {};
  final ScrollController _sidebarScroll = ScrollController();
  final GlobalKey _sidebarRootKey = GlobalKey();

  // Inspector scroll controllers (horizontal + vertical)
  final ScrollController _inspectorHController = ScrollController();
  final ScrollController _inspectorVController = ScrollController();

  // ---------------------- JSON load / apply / export ----------------------
  void _loadJsonString(String txt) {
    try {
      final dynamic parsed = jsonDecode(txt);
      if (parsed is Map<String, dynamic>) {
        setState(() {
          _root = parsed;
          _selectedPath = null;
          _selectedValue = null;
          _editorController.clear();
          _tileKeys.clear();
          _titleKeys.clear();
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('JSON loaded')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Root JSON must be an object')),
        );
      }
    } on FormatException catch (fe) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('JSON parse error: ${fe.message}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to parse JSON: $e')));
    }
  }

  Future<String?> _showPasteDialog() {
    final ctrl = TextEditingController();
    return showDialog<String?>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Paste BDUI JSON'),
            content: SizedBox(
              height: 300,
              child: TextField(
                controller: ctrl,
                maxLines: null,
                decoration: const InputDecoration(hintText: 'Paste JSON here'),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                child: const Text('Load'),
              ),
            ],
          ),
    );
  }

  Future<void> _pasteAndLoadJson() async {
    final text = await _showPasteDialog();
    if (text == null || text.trim().isEmpty) return;
    _loadJsonString(text);
  }

  void _loadSample() {
    const sample = '''
{
  "globalVariable": {
    "selectedCategoryOnCategoryPage": {
      "type": "String",
      "defaultValue": ""
    }
  },
  "widgetRegister": {
    "wrDefaultGrid": {
      "type": "defaultGrid",
      "options": {
        "limit": 12
      }
    }
  },
  "pages": [
    {
      "pageName": "home",
      "sections": [
        {
          "widgetRegister": "wrDeals"
        },
        {
          "widgetRegister": "wrFeatured"
        }
      ]
    },
    {
      "pageName": "category"
    }
  ]
}
''';
    _loadJsonString(sample);
  }

  void _applyEditorChanges() {
    if (_selectedPath == null) return;
    try {
      final parsed = jsonDecode(_editorController.text);
      final nav = JsonNavigator(_root);
      final ok = nav.setNode(_selectedPath!, parsed);
      if (!ok) throw Exception('Failed to set node');
      setState(() {
        _selectedValue = parsed;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Node updated')));
    } on FormatException catch (fe) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invalid JSON: ${fe.message}')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update node: $e')));
    }
  }

  Future<void> _copyToClipboard() async {
    final text = const JsonEncoder.withIndent('  ').convert(_root);
    await Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Config copied to clipboard')));
  }

  void _downloadJsonWeb() {
    if (!kIsWeb) return;
    try {
      final str = const JsonEncoder.withIndent('  ').convert(_root);
      final bytes = utf8.encode(str);
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor =
          html.document.createElement('a') as html.AnchorElement
            ..href = url
            ..download = 'bdui-config.json';
      html.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  // ---------------------- selection & scrolling ----------------------
  void _selectPath(String path, {bool ensureCenter = true}) {
    final nav = JsonNavigator(_root);
    final val = nav.getNode(path);
    setState(() {
      _selectedPath = path;
      _selectedValue = val;
      _editorController.text = const JsonEncoder.withIndent('  ').convert(val);
    });

    if (!ensureCenter) return;

    // try ensureVisible on title key first
    final titleKey = _titleKeys[path];
    if (titleKey != null && titleKey.currentContext != null) {
      try {
        Scrollable.ensureVisible(
          titleKey.currentContext!,
          duration: const Duration(milliseconds: 300),
          alignment: 0.5,
          curve: Curves.easeInOut,
        );
        return;
      } catch (_) {
        // fall through to manual scroll
      }
    }

    // fallback manual scroll to center
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _manualScrollToCenter(path),
    );
  }

  void _manualScrollToCenter(String path) {
    final key = _tileKeys[path];
    final sidebarCtx = _sidebarRootKey.currentContext;
    if (key == null || sidebarCtx == null) return;
    final tileCtx = key.currentContext;
    if (tileCtx == null) return;
    final tileBox = tileCtx.findRenderObject() as RenderBox?;
    final sidebarBox = sidebarCtx.findRenderObject() as RenderBox?;
    if (tileBox == null || sidebarBox == null) return;
    final tileGlobal = tileBox.localToGlobal(Offset.zero);
    final sidebarGlobal = sidebarBox.localToGlobal(Offset.zero);
    final tileCenter = tileGlobal.dy + tileBox.size.height / 2;
    final sidebarTop = sidebarGlobal.dy;
    final sidebarHeight = sidebarBox.size.height;
    final desired = tileCenter - sidebarTop - (sidebarHeight / 2);
    final target = (_sidebarScroll.offset + desired).clamp(
      0.0,
      _sidebarScroll.position.maxScrollExtent,
    );
    _sidebarScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // ---------------------- tree building ----------------------
  Widget _buildTreeWidgets(Map<String, dynamic> map, [String parentPath = '']) {
    final List<Widget> children = [];
    map.forEach((k, v) {
      final currentPath = parentPath.isEmpty ? k : '$parentPath/$k';
      children.add(_buildNodeWidgetForValue(k, currentPath, v));
    });
    return Column(children: children);
  }

  Widget _buildNodeWidgetForValue(
    String displayKey,
    String path,
    dynamic value,
  ) {
    // ensure unique keys
    final tileKey = _tileKeys.putIfAbsent(path, () => GlobalKey());
    final titleKey = _titleKeys.putIfAbsent(path, () => GlobalKey());

    if (value is Map<String, dynamic>) {
      return ExpansionTile(
        key: PageStorageKey(path),
        onExpansionChanged: (expanded) {
          if (expanded) {
            // after expansion, center the title in view
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _selectPath(path, ensureCenter: true),
            );
          }
        },
        title: GestureDetector(
          key: titleKey,
          onTap: () => _selectPath(path),
          child: _tileTitle(displayKey, path, isContainer: true),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12.0),
            child: _buildTreeWidgets(value, path),
          ),
        ],
      );
    } else if (value is List) {
      final List<Widget> items = [];
      for (int i = 0; i < value.length; i++) {
        final childPath = '$path/$i';
        final childDisplay = '$displayKey[$i]';
        items.add(_buildNodeWidgetForValue(childDisplay, childPath, value[i]));
      }
      return ExpansionTile(
        key: PageStorageKey(path),
        onExpansionChanged: (expanded) {
          if (expanded)
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _selectPath(path, ensureCenter: true),
            );
        },
        title: GestureDetector(
          key: titleKey,
          onTap: () => _selectPath(path),
          child: _tileTitle('$displayKey [List]', path, isContainer: true),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12.0),
            child: Column(children: items),
          ),
        ],
      );
    } else {
      return ListTile(
        key: tileKey,
        title: GestureDetector(
          key: titleKey,
          onTap: () => _selectPath(path),
          child: _tileTitle(displayKey, path, value: value),
        ),
        onTap: () => _selectPath(path),
      );
    }
  }

  Widget _tileTitle(
    String label,
    String path, {
    dynamic value,
    bool isContainer = false,
  }) {
    final selected = _selectedPath == path;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: selected ? Colors.blue.shade50 : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                if (isContainer)
                  Icon(
                    Icons.folder,
                    size: 16,
                    color: selected ? Colors.blue.shade700 : Colors.grey,
                  ),
                if (isContainer) const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                      color: selected ? Colors.blue.shade900 : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (value != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                value.toString(),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BDUI Builder - Stage1 Fixed'),
        actions: [
          IconButton(
            onPressed: _pasteAndLoadJson,
            icon: const Icon(Icons.paste),
          ),
          IconButton(
            onPressed: _loadSample,
            icon: const Icon(Icons.playlist_add_check),
          ),
          IconButton(onPressed: _copyToClipboard, icon: const Icon(Icons.copy)),
          if (kIsWeb)
            IconButton(
              onPressed: _downloadJsonWeb,
              icon: const Icon(Icons.download),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final leftWidth = (maxWidth * 0.28).clamp(240.0, 520.0);
          final rightWidth = (maxWidth * 0.32).clamp(260.0, 640.0);

          return Row(
            children: [
              // Sidebar
              ConstrainedBox(
                constraints: BoxConstraints.tightFor(width: leftWidth),
                child: Container(
                  key: _sidebarRootKey,
                  color: Colors.grey.shade100,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Document Tree',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _root = {};
                                  _selectedPath = null;
                                  _selectedValue = null;
                                  _editorController.clear();
                                  _tileKeys.clear();
                                  _titleKeys.clear();
                                });
                              },
                              child: const Text('Clear'),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child:
                            _root.isEmpty
                                ? const Center(
                                  child: Text(
                                    'No document loaded. Use Paste or Load Sample',
                                  ),
                                )
                                : SingleChildScrollView(
                                  controller: _sidebarScroll,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8.0,
                                    ),
                                    child: _buildTreeWidgets(_root),
                                  ),
                                ),
                      ),
                    ],
                  ),
                ),
              ),

              // Center editor
              Expanded(
                child: Container(
                  color: Colors.white,
                  child: Column(
                    children: [
                      Container(
                        height: 52,
                        color: Colors.grey.shade50,
                        child: Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  'Selected: ${_selectedPath ?? "<none>"}',
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() {}),
                              child: const Text('Validate'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child:
                            _selectedPath == null
                                ? const Center(
                                  child: Text('Select a node to edit its JSON'),
                                )
                                : Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _editorController,
                                          maxLines: null,
                                          expands: true,
                                          decoration: const InputDecoration(
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          ElevatedButton(
                                            onPressed: _applyEditorChanges,
                                            child: const Text('Apply'),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            onPressed: () {
                                              _editorController.text =
                                                  const JsonEncoder.withIndent(
                                                    '  ',
                                                  ).convert(_selectedValue);
                                            },
                                            child: const Text('Reset'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                      ),
                    ],
                  ),
                ),
              ),

              // Inspector (right) - horizontal + vertical scroll controllers with interactive scrollbar
              ConstrainedBox(
                constraints: BoxConstraints.tightFor(width: rightWidth),
                child: Container(
                  color: Colors.grey.shade50,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: const Text(
                          'Inspector',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child:
                              _selectedPath == null
                                  ? const Text('No node selected')
                                  : Scrollbar(
                                    controller: _inspectorHController,
                                    thumbVisibility: true,
                                    interactive: true,
                                    child: SingleChildScrollView(
                                      controller: _inspectorHController,
                                      scrollDirection: Axis.horizontal,
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          minWidth: 600,
                                        ),
                                        child: Scrollbar(
                                          controller: _inspectorVController,
                                          thumbVisibility: true,
                                          interactive: true,
                                          notificationPredicate:
                                              (notif) => notif.depth == 1,
                                          child: SingleChildScrollView(
                                            controller: _inspectorVController,
                                            scrollDirection: Axis.vertical,
                                            child: SelectableText(
                                              const JsonEncoder.withIndent(
                                                '  ',
                                              ).convert(_selectedValue),
                                              style: const TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
