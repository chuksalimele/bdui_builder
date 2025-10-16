// BDUI Builder - Stage 2.3 (live sync, add/delete fields)
// Implemented:
// - Live two-way sync between visual editors and JSON via controller listeners
// - Inspector always reflects _editorPath (current visual editor context)
// - Add/Delete fields for Map and List directly in visual editor
// - Controllers are created once and reused; listeners update nodes on change

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      title: 'BDUI Builder - Stage2.3',
      theme: ThemeData(useMaterial3: true),
      home: const BDUIStage2Page(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class JsonNavigator {
  final Map<String, dynamic> root;
  JsonNavigator(this.root);

  dynamic getNode(String? path) {
    if (path == null || path.isEmpty) return root;
    final parts = path.split('/');
    dynamic cursor = root;
    for (final p in parts) {
      if (cursor == null) return null;
      if (cursor is Map<String, dynamic>)
        cursor = cursor[p];
      else if (cursor is List) {
        final idx = int.tryParse(p);
        if (idx == null) return null;
        if (idx < 0 || idx >= cursor.length) return null;
        cursor = cursor[idx];
      } else
        return null;
    }
    return cursor;
  }

  bool setNode(String path, dynamic value) {
    if (path.isEmpty) return false;
    final parts = path.split('/');
    dynamic cursor = root;
    for (int i = 0; i < parts.length - 1; i++) {
      final p = parts[i];
      if (cursor is Map<String, dynamic>)
        cursor = cursor[p];
      else if (cursor is List)
        cursor = cursor[int.parse(p)];
      else
        return false;
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

  bool insertIntoList(String listPath, dynamic value, [int? atIndex]) {
    final list = getNode(listPath);
    if (list is List) {
      if (atIndex == null)
        list.add(value);
      else
        list.insert(atIndex, value);
      return true;
    }
    return false;
  }

  bool deleteNode(String path) {
    if (path.isEmpty) return false;
    final parts = path.split('/');
    dynamic cursor = root;
    for (int i = 0; i < parts.length - 1; i++) {
      final p = parts[i];
      if (cursor is Map<String, dynamic>)
        cursor = cursor[p];
      else if (cursor is List)
        cursor = cursor[int.parse(p)];
      else
        return false;
    }
    final last = parts.last;
    if (cursor is Map<String, dynamic>) {
      cursor.remove(last);
      return true;
    } else if (cursor is List) {
      final idx = int.tryParse(last);
      if (idx == null) return false;
      if (idx < 0 || idx >= cursor.length) return false;
      cursor.removeAt(idx);
      return true;
    }
    return false;
  }
}

class BDUIStage2Page extends StatefulWidget {
  const BDUIStage2Page({super.key});
  @override
  State<BDUIStage2Page> createState() => _BDUIStage2PageState();
}

class _BDUIStage2PageState extends State<BDUIStage2Page>
    with TickerProviderStateMixin {
  Map<String, dynamic> _root = {};
  String? _selectedPath;
  dynamic _selectedValue;
  String? _editorPath; // node currently shown in visual editor

  final TextEditingController _rawEditorController = TextEditingController();
  final Map<String, TextEditingController> _valueControllers = {};
  final Map<String, Timer?> _debounceTimers = {};
  String _selectedJsonCache = '';

  final Map<String, GlobalKey> _tileKeys = {};
  final Map<String, GlobalKey> _titleKeys = {};
  final ScrollController _sidebarScroll = ScrollController();
  final GlobalKey _sidebarRootKey = GlobalKey();

  final ScrollController _inspectorHController = ScrollController();
  final ScrollController _inspectorVController = ScrollController();

  late TabController _inspectorTabController;

  @override
  void initState() {
    super.initState();
    _inspectorTabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _inspectorTabController.dispose();
    for (final c in _valueControllers.values) c.dispose();
    for (final t in _debounceTimers.values) t?.cancel();
    _valueControllers.clear();
    _debounceTimers.clear();
    _rawEditorController.dispose();
    _inspectorHController.dispose();
    _inspectorVController.dispose();
    _sidebarScroll.dispose();
    super.dispose();
  }

  // ---------- IO ----------
  void _loadJsonString(String txt) {
    try {
      final dynamic parsed = jsonDecode(txt);
      if (parsed is Map<String, dynamic>) {
        setState(() {
          _root = parsed;
          _selectedPath = null;
          _selectedValue = null;
          _editorPath = null;
          _rawEditorController.clear();
          _valueControllers.clear();
          _tileKeys.clear();
          _titleKeys.clear();
          _selectedJsonCache = '';
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('JSON loaded')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Root JSON must be an object')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('JSON parse error: $e')));
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
    const sample =
        '{"globalVariable":{"foo":{"type":"String","defaultValue":""}},"pages":[{"pageName":"home"}]}';
    _loadJsonString(sample);
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

  // ---------- selection & scrolling ----------
  void _selectPath(String path, {bool ensureCenter = true}) {
    final nav = JsonNavigator(_root);
    final val = nav.getNode(path);
    setState(() {
      _selectedPath = path;
      _selectedValue = val;
      _editorPath = path;
      _rawEditorController.text = const JsonEncoder.withIndent(
        '  ',
      ).convert(val);
      _selectedJsonCache = _rawEditorController.text;
    });

    if (!ensureCenter) return;

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
      } catch (_) {}
    }
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

  // ---------- tree building ----------
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
    final tileKey = _tileKeys.putIfAbsent(path, () => GlobalKey());
    final titleKey = _titleKeys.putIfAbsent(path, () => GlobalKey());

    if (value is Map<String, dynamic>) {
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
      final items = <Widget>[];
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

  // ---------- visual inspector (drill-down) ----------
  Widget _buildVisualInspector() {
    if (_editorPath == null)
      return const Center(child: Text('No node selected'));
    final nav = JsonNavigator(_root);
    final node = nav.getNode(_editorPath!);
    final crumbs =
        (_editorPath == null || _editorPath!.isEmpty)
            ? <String>[]
            : _editorPath!.split('/');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          children: [
            TextButton(
              onPressed: () => setState(() => _editorPath = _selectedPath),
              child: const Text('root'),
            ),
            for (int i = 0; i < crumbs.length; i++) ...[
              const Text(' / '),
              TextButton(
                onPressed:
                    () => setState(
                      () => _editorPath = crumbs.sublist(0, i + 1).join('/'),
                    ),
                child: Text(crumbs[i]),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildImmediateChildrenEditor(_editorPath!, node)),
      ],
    );
  }

  Widget _buildImmediateChildrenEditor(String path, dynamic node) {
    if (node is Map<String, dynamic>) {
      final entries = node.entries.toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Map: $path',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: () => _addMapKeyDialog(path),
                    icon: const Icon(Icons.add),
                  ),
                  IconButton(
                    onPressed: () => _deleteNodeConfirm(path),
                    icon: const Icon(Icons.delete),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: entries.length,
              itemBuilder: (ctx, i) {
                final k = entries[i].key;
                final v = entries[i].value;
                final childPath = '$path/$k';
                return _immediateChildTile(k, childPath, v);
              },
            ),
          ),
        ],
      );
    }

    if (node is List) {
      final list = node;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'List: $path',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: () => _addListItemDialog(path),
                    icon: const Icon(Icons.add),
                  ),
                  IconButton(
                    onPressed: () => _deleteNodeConfirm(path),
                    icon: const Icon(Icons.delete),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (ctx, i) {
                final v = list[i];
                final childPath = '$path/$i';
                return _immediateChildTile('[$i]', childPath, v);
              },
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Value at $path'),
          const SizedBox(height: 8),
          _buildEditorForPrimitive(path, node),
        ],
      ),
    );
  }

  Widget _immediateChildTile(String label, String childPath, dynamic value) {
    if (value is String ||
        value is int ||
        value is double ||
        value is bool ||
        value == null) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              const SizedBox(width: 12),
              Expanded(child: _buildEditorForPrimitive(childPath, value)),
              IconButton(
                onPressed: () => _deleteNodeConfirm(childPath),
                icon: const Icon(Icons.delete),
              ),
            ],
          ),
        ),
      );
    }

    final subtitle =
        value is Map
            ? 'Map (${(value as Map).length} keys)'
            : 'List (${(value as List).length} items)';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(label),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.open_in_new),
              onPressed: () => setState(() => _editorPath = childPath),
            ),
            IconButton(
              onPressed: () => _deleteNodeConfirm(childPath),
              icon: const Icon(Icons.delete),
            ),
          ],
        ),
      ),
    );
  }

  TextEditingController _attachController(
    String path,
    String initial, {
    required ValueChanged<String> onChanged,
  }) {
    final existing = _valueControllers[path];
    if (existing != null) {
      if (existing.text != initial) existing.text = initial;
      return existing;
    }
    final ctrl = TextEditingController(text: initial);
    _valueControllers[path] = ctrl;

    // debounce changes to avoid heavy setState on every keystroke
    ctrl.addListener(() {
      _debounceTimers[path]?.cancel();
      _debounceTimers[path] = Timer(const Duration(milliseconds: 300), () {
        onChanged(ctrl.text);
      });
    });

    return ctrl;
  }

  Widget _buildEditorForPrimitive(String path, dynamic value) {
    if (value is bool)
      return Switch(value: value, onChanged: (v) => _updatePrimitive(path, v));

    if (value is int) {
      final ctrl = _attachController(
        path,
        value.toString(),
        onChanged: (s) {
          final n = int.tryParse(s);
          if (n != null) _updatePrimitive(path, n);
        },
      );
      return Row(
        children: [
          IconButton(
            onPressed: () => _updatePrimitive(path, value - 1),
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 120,
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
            ),
          ),
          IconButton(
            onPressed: () => _updatePrimitive(path, value + 1),
            icon: const Icon(Icons.add),
          ),
        ],
      );
    }

    if (value is double) {
      final ctrl = _attachController(
        path,
        value.toString(),
        onChanged: (s) {
          final n = double.tryParse(s);
          if (n != null) _updatePrimitive(path, n);
        },
      );
      return Row(
        children: [
          IconButton(
            onPressed: () => _updatePrimitive(path, (value - 0.1)),
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 140,
            child: TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          ),
          IconButton(
            onPressed: () => _updatePrimitive(path, (value + 0.1)),
            icon: const Icon(Icons.add),
          ),
        ],
      );
    }

    // string or null
    final ctrl = _attachController(
      path,
      value?.toString() ?? '',
      onChanged: (s) => _updatePrimitive(path, s),
    );
    return Row(
      children: [
        Expanded(child: TextField(controller: ctrl)),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () {
            ctrl.clear();
            _updatePrimitive(path, '');
          },
          icon: const Icon(Icons.clear),
        ),
      ],
    );
  }

  void _showError(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  void _updatePrimitive(String path, dynamic newValue) {
    final nav = JsonNavigator(_root);
    final ok = nav.setNode(path, newValue);
    if (!ok) {
      _showError('Failed to update value');
      return;
    }
    // update inspector and selectedValue if relevant
    setState(() {
      if (_editorPath != null) {
        final current = nav.getNode(_editorPath!);
        _rawEditorController.text = const JsonEncoder.withIndent(
          '  ',
        ).convert(current);
        _selectedJsonCache = _rawEditorController.text;
      }
      if (_selectedPath != null) {
        _selectedValue = nav.getNode(_selectedPath!);
      }
    });
  }

  // ---------- dialogs / add helpers ----------
  Future<void> _addMapKeyDialog(String mapPath) async {
    final keyCtrl = TextEditingController();
    final typeCtrl = TextEditingController(text: 'string');
    final valueCtrl = TextEditingController();
    final res = await showDialog<bool?>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Add key'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: keyCtrl,
                  decoration: const InputDecoration(labelText: 'Key'),
                ),
                DropdownButtonFormField<String>(
                  value: 'string',
                  items: const [
                    DropdownMenuItem(value: 'string', child: Text('String')),
                    DropdownMenuItem(value: 'int', child: Text('Int')),
                    DropdownMenuItem(value: 'double', child: Text('Double')),
                    DropdownMenuItem(value: 'bool', child: Text('Bool')),
                    DropdownMenuItem(value: 'map', child: Text('Map')),
                    DropdownMenuItem(value: 'list', child: Text('List')),
                  ],
                  onChanged: (v) => typeCtrl.text = v ?? 'string',
                ),
                TextField(
                  controller: valueCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Value (for primitives)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add'),
              ),
            ],
          ),
    );
    if (res != true) return;
    final k = keyCtrl.text.trim();
    if (k.isEmpty) return _showError('Key required');
    final t = typeCtrl.text.trim();
    dynamic val;
    if (t == 'int')
      val = int.tryParse(valueCtrl.text) ?? 0;
    else if (t == 'double')
      val = double.tryParse(valueCtrl.text) ?? 0.0;
    else if (t == 'bool')
      val = (valueCtrl.text.toLowerCase() == 'true');
    else if (t == 'map')
      val = <String, dynamic>{};
    else if (t == 'list')
      val = <dynamic>[];
    else
      val = valueCtrl.text;
    final nav = JsonNavigator(_root);
    final map = nav.getNode(mapPath);
    if (map is Map<String, dynamic>) {
      if (map.containsKey(k)) return _showError('Key exists');
      map[k] = val;
      setState(() {
        _valueControllers.removeWhere((p, c) => p.startsWith(mapPath));
      });
    } else
      _showError('Target not map');
  }

  Future<void> _addListItemDialog(String listPath) async {
    final typeCtrl = TextEditingController(text: 'string');
    final valueCtrl = TextEditingController();
    final res = await showDialog<bool?>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Add list item'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: 'string',
                  items: const [
                    DropdownMenuItem(value: 'string', child: Text('String')),
                    DropdownMenuItem(value: 'int', child: Text('Int')),
                    DropdownMenuItem(value: 'double', child: Text('Double')),
                    DropdownMenuItem(value: 'bool', child: Text('Bool')),
                    DropdownMenuItem(value: 'map', child: Text('Map')),
                    DropdownMenuItem(value: 'list', child: Text('List')),
                  ],
                  onChanged: (v) => typeCtrl.text = v ?? 'string',
                ),
                TextField(
                  controller: valueCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Value (for primitives)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add'),
              ),
            ],
          ),
    );
    if (res != true) return;
    final t = typeCtrl.text.trim();
    dynamic val;
    if (t == 'int')
      val = int.tryParse(valueCtrl.text) ?? 0;
    else if (t == 'double')
      val = double.tryParse(valueCtrl.text) ?? 0.0;
    else if (t == 'bool')
      val = (valueCtrl.text.toLowerCase() == 'true');
    else if (t == 'map')
      val = <String, dynamic>{};
    else if (t == 'list')
      val = <dynamic>[];
    else
      val = valueCtrl.text;
    final nav = JsonNavigator(_root);
    final ok = nav.insertIntoList(listPath, val);
    if (!ok)
      _showError('Target is not a list');
    else
      setState(() {
        _valueControllers.removeWhere((p, c) => p.startsWith(listPath));
      });
  }

  void _moveListItemUp(String listPath, int idx) {
    final nav = JsonNavigator(_root);
    final list = nav.getNode(listPath);
    if (list is List && idx > 0) {
      final tmp = list[idx - 1];
      list[idx - 1] = list[idx];
      list[idx] = tmp;
      setState(() {
        _valueControllers.removeWhere((p, c) => p.startsWith(listPath));
      });
    }
  }

  void _moveListItemDown(String listPath, int idx) {
    final nav = JsonNavigator(_root);
    final list = nav.getNode(listPath);
    if (list is List && idx < list.length - 1) {
      final tmp = list[idx + 1];
      list[idx + 1] = list[idx];
      list[idx] = tmp;
      setState(() {
        _valueControllers.removeWhere((p, c) => p.startsWith(listPath));
      });
    }
  }

  void _deleteNodeConfirm(String path) async {
    final ok = await showDialog<bool?>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete node'),
            content: Text('Delete $path?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (ok != true) return;
    final nav = JsonNavigator(_root);
    final success = nav.deleteNode(path);
    if (!success) return _showError('Delete failed');
    final p = _parentPath(path) ?? '';
    setState(() {
      _selectedPath = p.isEmpty ? null : p;
      _selectedValue = p.isEmpty ? null : nav.getNode(p);
      _editorPath = _selectedPath;
      _rawEditorController.text =
          _selectedValue == null
              ? ''
              : const JsonEncoder.withIndent('  ').convert(_selectedValue);
      _selectedJsonCache = _rawEditorController.text;
      _valueControllers.removeWhere(
        (k, v) => k.startsWith(path) || k.startsWith(p),
      );
    });
  }

  Future<void> _renameMapKeyDialog(String mapPath, String key) async {
    final ctrl = TextEditingController(text: key);
    final ok = await showDialog<bool?>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Rename key'),
            content: TextField(controller: ctrl),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Rename'),
              ),
            ],
          ),
    );
    if (ok != true) return;
    final newKey = ctrl.text.trim();
    if (newKey.isEmpty) return _showError('Key required');
    final nav = JsonNavigator(_root);
    final map = nav.getNode(mapPath);
    if (map is Map<String, dynamic>) {
      final val = map.remove(key);
      map[newKey] = val;
      setState(() {
        _valueControllers.removeWhere((p, c) => p.startsWith(mapPath));
      });
    }
  }

  String? _parentPath(String path) {
    if (!path.contains('/')) return '';
    final idx = path.lastIndexOf('/');
    return path.substring(0, idx);
  }

  void _applyRawEditor() {
    if (_editorPath == null) return;
    try {
      final parsed = jsonDecode(_rawEditorController.text);
      final nav = JsonNavigator(_root);
      final ok = nav.setNode(_editorPath!, parsed);
      if (!ok) throw Exception('Apply failed');
      setState(() {
        if (_editorPath != null) {
          final current = nav.getNode(_editorPath!);
          _rawEditorController.text = const JsonEncoder.withIndent(
            '  ',
          ).convert(current);
          _selectedJsonCache = _rawEditorController.text;
        }
        if (_selectedPath != null) _selectedValue = nav.getNode(_selectedPath!);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Applied raw JSON')));
    } catch (e) {
      _showError('Invalid JSON: $e');
    }
  }

  // ---------- UI build ----------
  Widget _buildSidebar() {
    return Container(
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
                      _editorPath = null;
                      _rawEditorController.clear();
                      _valueControllers.clear();
                      _tileKeys.clear();
                      _titleKeys.clear();
                      _selectedJsonCache = '';
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
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: _buildTreeWidgets(_root),
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterEditor() {
    return Container(
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
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Selected: ${_selectedPath ?? "<none>"}'),
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
                _editorPath == null
                    ? const Center(child: Text('Select a node to edit'))
                    : Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          Expanded(child: _buildVisualInspector()),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: _applyRawEditor,
                                child: const Text('Apply'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () {
                                  final nav = JsonNavigator(_root);
                                  final val =
                                      _editorPath == null
                                          ? null
                                          : nav.getNode(_editorPath!);
                                  _rawEditorController.text =
                                      val == null
                                          ? ''
                                          : const JsonEncoder.withIndent(
                                            '  ',
                                          ).convert(val);
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
    );
  }

  Widget _buildInspector() {
    final nav = JsonNavigator(_root);
    final node = nav.getNode(_editorPath);
    final display =
        node == null ? '{}' : const JsonEncoder.withIndent('  ').convert(node);

    return Container(
      color: Colors.grey.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(12.0),
            child: Text(
              'Inspector',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Scrollbar(
                controller: _inspectorHController,
                thumbVisibility: true,
                interactive: true,
                child: SingleChildScrollView(
                  controller: _inspectorHController,
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 600),
                    child: SingleChildScrollView(
                      controller: _inspectorVController,
                      child: SelectableText(
                        display,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ),
              ),
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
        title: const Text('BDUI Builder - Stage2.3'),
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
          final leftWidth = (maxWidth * 0.26).clamp(240.0, 520.0);
          final rightWidth = (maxWidth * 0.32).clamp(280.0, 640.0);
          return Row(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints.tightFor(width: leftWidth),
                child: _buildSidebar(),
              ),
              Expanded(child: _buildCenterEditor()),
              ConstrainedBox(
                constraints: BoxConstraints.tightFor(width: rightWidth),
                child: _buildInspector(),
              ),
            ],
          );
        },
      ),
    );
  }
}
