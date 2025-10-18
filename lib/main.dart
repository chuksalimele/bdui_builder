// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html; // only used if kIsWeb for download

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
      home: const BDUIStage2Page(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Simple navigator to get/set/delete nodes inside a nested Map/List structure
class JsonNavigator {
  Map<String, dynamic> root;
  JsonNavigator(this.root);

  dynamic getNode(String? path) {
    if (path == null || path.isEmpty) return root;
    final parts = path.split('/');
    dynamic cur = root;
    for (final p in parts) {
      if (cur == null) return null;
      if (cur is Map<String, dynamic>) {
        cur = cur[p];
      } else if (cur is List) {
        final idx = int.tryParse(p);
        if (idx == null || idx < 0 || idx >= cur.length) return null;
        cur = cur[idx];
      } else {
        return null;
      }
    }
    return cur;
  }

  bool setNode(String path, dynamic value) {
    if (path.isEmpty) return false;
    final parts = path.split('/');
    dynamic cur = root;
    for (int i = 0; i < parts.length - 1; i++) {
      final p = parts[i];
      if (cur is Map<String, dynamic>)
        cur = cur[p];
      else if (cur is List) {
        final idx = int.tryParse(p);
        if (idx == null) return false;
        cur = cur[idx];
      } else
        return false;
    }
    final last = parts.last;
    if (cur is Map<String, dynamic>) {
      cur[last] = value;
      return true;
    } else if (cur is List) {
      final idx = int.tryParse(last);
      if (idx == null || idx < 0 || idx >= cur.length) return false;
      cur[idx] = value;
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
    dynamic cur = root;
    for (int i = 0; i < parts.length - 1; i++) {
      final p = parts[i];
      if (cur is Map<String, dynamic>)
        cur = cur[p];
      else if (cur is List)
        cur = cur[int.parse(p)];
      else
        return false;
    }
    final last = parts.last;
    if (cur is Map<String, dynamic>) {
      return cur.remove(last) != null;
    } else if (cur is List) {
      final idx = int.tryParse(last);
      if (idx == null || idx < 0 || idx >= cur.length) return false;
      cur.removeAt(idx);
      return true;
    }
    return false;
  }

  bool renameNode(String path, String newKey) {
    final parts = path.split('/');
    if (parts.length < 2) return false;
    final key = parts.last;
    final parentPath = parts.sublist(0, parts.length - 1).join('/');
    final parent = getNode(parentPath);
    if (parent is! Map<String, dynamic>) return false;
    final val = parent.remove(key);
    if (val == null) return false;
    parent[newKey] = val;
    return true;
  }

  bool duplicateNode(String path) {
    final node = getNode(path);
    if (node == null) return false;
    final parts = path.split('/');
    dynamic parent = root;
    for (int i = 0; i < parts.length - 1; i++) {
      final p = parts[i];
      if (parent is Map<String, dynamic>)
        parent = parent[p];
      else if (parent is List)
        parent = parent[int.parse(p)];
      else
        return false;
    }
    final last = parts.last;
    if (parent is Map<String, dynamic>) {
      // insert duplicate directly after original key
      final entries = parent.entries.toList();
      final idx = entries.indexWhere((e) => e.key == last);
      if (idx == -1) return false;
      final copyVal = jsonDecode(jsonEncode(node));
      // find unique new key
      var base = '${last}_copy';
      var i = 1;
      while (parent.containsKey(base)) {
        base = '${last}_copy$i';
        i++;
      }
      entries.insert(idx + 1, MapEntry(base, copyVal));
      parent
        ..clear()
        ..addEntries(entries);
      return true;
    } else if (parent is List) {
      final idx = int.tryParse(last);
      if (idx == null || idx < 0 || idx >= parent.length) return false;
      final copyVal = jsonDecode(jsonEncode(node));
      parent.insert(idx + 1, copyVal);
      return true;
    }
    return false;
  }

  /// Move a map child up or down by key order
  bool moveMapEntryUp(String mapPath, String key) {
    final node = getNode(mapPath);
    if (node is! Map<String, dynamic>) return false;
    final entries = node.entries.toList();
    final idx = entries.indexWhere((e) => e.key == key);
    if (idx > 0) {
      final tmp = entries[idx - 1];
      entries[idx - 1] = entries[idx];
      entries[idx] = tmp;
      node
        ..clear()
        ..addEntries(entries);
      return true;
    }
    return false;
  }

  bool moveMapEntryDown(String mapPath, String key) {
    final node = getNode(mapPath);
    if (node is! Map<String, dynamic>) return false;
    final entries = node.entries.toList();
    final idx = entries.indexWhere((e) => e.key == key);
    if (idx >= 0 && idx < entries.length - 1) {
      final tmp = entries[idx + 1];
      entries[idx + 1] = entries[idx];
      entries[idx] = tmp;
      node
        ..clear()
        ..addEntries(entries);
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
  String? _editorPath; // node shown in visual editor

  // controllers
  final TextEditingController _rawEditorController = TextEditingController();
  final FocusNode _rawEditorFocusNode = FocusNode();
  final Map<String, TextEditingController> _valueControllers = {};
  final Map<String, Timer?> _debounceTimers = {};

  // history
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  static const int _kHistoryLimit = 100;

  // json editor local history (undo/redo inside inspector JSON)
  final List<String> _jsonEditHistory = [];
  int _jsonEditIndex = -1;
  bool _rawEditorDirty = false; // user changed JSON but not saved

  // UI keys and controllers
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

    // sample small root to start with
    _root = {
      "globalVariable": {
        "x": {"type": "String", "defaultValue": ""},
      },
      "pages": [
        {"pageName": "home"},
      ],
    };
    // initialize raw editor to selected editor node (root initially)
    _editorPath = null;
    _setRawEditorFromEditorPath();

    _rawEditorController.addListener(() {
      // only mark dirty when user types (has focus)
      if (_rawEditorFocusNode.hasFocus) {
        _rawEditorDirty = true;
        // push local history for JSON editor
        final txt = _rawEditorController.text;
        if (_jsonEditIndex < 0 ||
            _jsonEditHistory.isEmpty ||
            _jsonEditHistory[_jsonEditIndex] != txt) {
          // trim forward history
          if (_jsonEditIndex < _jsonEditHistory.length - 1) {
            _jsonEditHistory.removeRange(
              _jsonEditIndex + 1,
              _jsonEditHistory.length,
            );
          }
          _jsonEditHistory.add(txt);
          if (_jsonEditHistory.length > 200) _jsonEditHistory.removeAt(0);
          _jsonEditIndex = _jsonEditHistory.length - 1;
        }
      }
    });

    _rawEditorFocusNode.addListener(() {
      if (!_rawEditorFocusNode.hasFocus) {
        // when focus leaves, we do NOT auto-apply. only save if user pressed Save/Apply.
        // keep rawEditorDirty as-is
      }
    });
  }

  @override
  void dispose() {
    _inspectorTabController.dispose();
    for (final c in _valueControllers.values) c.dispose();
    for (final t in _debounceTimers.values) t?.cancel();
    _valueControllers.clear();
    _debounceTimers.clear();
    _rawEditorController.dispose();
    _rawEditorFocusNode.dispose();
    _inspectorHController.dispose();
    _inspectorVController.dispose();
    _sidebarScroll.dispose();
    super.dispose();
  }

  // ---------- history ----------
  void _pushHistory() {
    try {
      final snap = const JsonEncoder.withIndent('  ').convert(_root);
      if (_undoStack.isEmpty || _undoStack.last != snap) {
        _undoStack.add(snap);
        if (_undoStack.length > _kHistoryLimit) _undoStack.removeAt(0);
        _redoStack.clear();
      }
    } catch (_) {}
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final current = const JsonEncoder.withIndent('  ').convert(_root);
    _redoStack.add(current);
    final prev = _undoStack.removeLast();
    try {
      final parsed = jsonDecode(prev) as Map<String, dynamic>;
      setState(() {
        _root = parsed;
        _editorPath = null;
        _selectedPath = null;
        _selectedValue = null;
        _setRawEditorFromEditorPath();
        _valueControllers.clear();
      });
    } catch (e) {
      _showError('Undo failed: $e');
    }
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final next = _redoStack.removeLast();
    _undoStack.add(const JsonEncoder.withIndent('  ').convert(_root));
    try {
      final parsed = jsonDecode(next) as Map<String, dynamic>;
      setState(() {
        _root = parsed;
        _editorPath = null;
        _selectedPath = null;
        _selectedValue = null;
        _setRawEditorFromEditorPath();
        _valueControllers.clear();
      });
    } catch (e) {
      _showError('Redo failed: $e');
    }
  }

  // ---------- IO ----------
  void _loadJsonString(String txt, {bool pushHistory = true}) {
    try {
      final dynamic parsed = jsonDecode(txt);
      if (parsed is Map<String, dynamic>) {
        if (pushHistory) _pushHistory();
        setState(() {
          _root = parsed;
          _selectedPath = null;
          _selectedValue = null;
          _editorPath = null;
          _valueControllers.clear();
          _tileKeys.clear();
          _titleKeys.clear();
          _setRawEditorFromEditorPath();
          _rawEditorDirty = false;
          _jsonEditHistory.clear();
          _jsonEditIndex = -1;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('JSON loaded')));
      } else {
        _showError('Root JSON must be an object');
      }
    } catch (e) {
      _showError('JSON parse error: $e');
    }
  }

  Future<void> _pasteAndLoadJson() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String?>(
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
      _showError('Download failed: $e');
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
      _setRawEditorFromEditorPath(); // always sync JSON editor with selected editor node
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
    final children = <Widget>[];
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

  // ---------- visual inspector ----------
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
              onPressed: () => setState(() => _editorPath = null),
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
                  Tooltip(
                    message: 'Add key to map',
                    child: IconButton(
                      onPressed: () => _addMapKeyDialog(path),
                      icon: const Icon(Icons.add),
                    ),
                  ),
                  // replace delete icon with popup in header actions too
                  Tooltip(
                    message: 'More actions',
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (v) => _handleMapHeaderAction(path, v),
                      itemBuilder:
                          (ctx) => const [
                            PopupMenuItem(
                              value: 'duplicate',
                              child: Text('Duplicate'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                'Delete',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                    ),
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
                return _immediateChildTileMapEntry(k, childPath, v, node, k, i);
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
                  Tooltip(
                    message: 'Add item to list',
                    child: IconButton(
                      onPressed: () => _addListItemDialog(path),
                      icon: const Icon(Icons.add),
                    ),
                  ),
                  Tooltip(
                    message: 'More actions',
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (v) => _handleListHeaderAction(path, v),
                      itemBuilder:
                          (ctx) => const [
                            PopupMenuItem(
                              value: 'duplicate',
                              child: Text('Duplicate'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                'Delete',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                    ),
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
                return _immediateChildTileListEntry(
                  '[$i]',
                  childPath,
                  v,
                  list,
                  i,
                );
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

  Widget _immediateChildTileMapEntry(
    String label,
    String childPath,
    dynamic value,
    Map parentMap,
    String key,
    int index,
  ) {
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
              Tooltip(
                message: 'More actions',
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected:
                      (v) => _handleNodeMenuMap(
                        parentMap,
                        key,
                        index,
                        childPath,
                        v,
                      ),
                  itemBuilder:
                      (ctx) => const [
                        PopupMenuItem(
                          value: 'duplicate',
                          child: Text('Duplicate'),
                        ),
                        PopupMenuItem(value: 'moveUp', child: Text('Move Up')),
                        PopupMenuItem(
                          value: 'moveDown',
                          child: Text('Move Down'),
                        ),
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                ),
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
        trailing: Tooltip(
          message: 'More actions',
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected:
                (v) => _handleNodeMenuMap(parentMap, key, index, childPath, v),
            itemBuilder:
                (ctx) => const [
                  PopupMenuItem(value: 'open', child: Text('Open')),
                  PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                  PopupMenuItem(value: 'moveUp', child: Text('Move Up')),
                  PopupMenuItem(value: 'moveDown', child: Text('Move Down')),
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ],
          ),
        ),
      ),
    );
  }

  Widget _immediateChildTileListEntry(
    String label,
    String childPath,
    dynamic value,
    List parentList,
    int idx,
  ) {
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
              Tooltip(
                message: 'More actions',
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected:
                      (v) => _handleNodeMenuList(parentList, idx, childPath, v),
                  itemBuilder:
                      (ctx) => const [
                        PopupMenuItem(
                          value: 'duplicate',
                          child: Text('Duplicate'),
                        ),
                        PopupMenuItem(value: 'moveUp', child: Text('Move Up')),
                        PopupMenuItem(
                          value: 'moveDown',
                          child: Text('Move Down'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                ),
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
        trailing: Tooltip(
          message: 'More actions',
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected:
                (v) => _handleNodeMenuList(parentList, idx, childPath, v),
            itemBuilder:
                (ctx) => const [
                  PopupMenuItem(value: 'open', child: Text('Open')),
                  PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                  PopupMenuItem(value: 'moveUp', child: Text('Move Up')),
                  PopupMenuItem(value: 'moveDown', child: Text('Move Down')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ],
          ),
        ),
      ),
    );
  }

  // ---------- editors for primitive values ----------
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
    ctrl.addListener(() {
      _debounceTimers[path]?.cancel();
      _debounceTimers[path] = Timer(const Duration(milliseconds: 300), () {
        _pushHistory();
        onChanged(ctrl.text);
        // always sync inspector JSON view after a primitive change
        _setRawEditorFromEditorPath(); // editor node changed -> update raw editor content immediately
      });
    });
    return ctrl;
  }

  Widget _buildEditorForPrimitive(String path, dynamic value) {
    if (value is bool)
      return Tooltip(
        message: 'Toggle boolean',
        child: Switch(
          value: value,
          onChanged: (v) {
            _pushHistory();
            _updatePrimitive(path, v);
          },
        ),
      );
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
          Tooltip(
            message: 'Decrease',
            child: IconButton(
              onPressed: () {
                _pushHistory();
                _updatePrimitive(path, value - 1);
              },
              icon: const Icon(Icons.remove),
            ),
          ),
          SizedBox(
            width: 120,
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
            ),
          ),
          Tooltip(
            message: 'Increase',
            child: IconButton(
              onPressed: () {
                _pushHistory();
                _updatePrimitive(path, value + 1);
              },
              icon: const Icon(Icons.add),
            ),
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
          Tooltip(
            message: 'Decrease',
            child: IconButton(
              onPressed: () {
                _pushHistory();
                _updatePrimitive(path, (value - 0.1));
              },
              icon: const Icon(Icons.remove),
            ),
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
          Tooltip(
            message: 'Increase',
            child: IconButton(
              onPressed: () {
                _pushHistory();
                _updatePrimitive(path, (value + 0.1));
              },
              icon: const Icon(Icons.add),
            ),
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
        Tooltip(
          message: 'Clear',
          child: IconButton(
            onPressed: () {
              ctrl.clear();
              _pushHistory();
              _updatePrimitive(path, '');
            },
            icon: const Icon(Icons.clear),
          ),
        ),
      ],
    );
  }

  void _updatePrimitive(String path, dynamic newValue) {
    final nav = JsonNavigator(_root);
    final ok = nav.setNode(path, newValue);
    if (!ok) {
      _showError('Failed to update value');
      return;
    }
    setState(() {
      // Update selected value if relevant
      if (_editorPath != null) {
        final current = nav.getNode(_editorPath!);
        // always update raw editor content to reflect model changes
        _setRawEditorTextProgrammatic(
          const JsonEncoder.withIndent('  ').convert(current),
        );
      }
      if (_selectedPath != null) _selectedValue = nav.getNode(_selectedPath!);
    });
  }

  // ---------- dialogs / add helpers ----------
  Future<void> _addMapKeyDialog(String mapPath) async {
    final keyCtrl = TextEditingController();
    final typeCtrl = ValueNotifier<String>('string');
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
                ValueListenableBuilder<String>(
                  valueListenable: typeCtrl,
                  builder:
                      (_, v, __) => DropdownButtonFormField<String>(
                        value: v,
                        items: const [
                          DropdownMenuItem(
                            value: 'string',
                            child: Text('String'),
                          ),
                          DropdownMenuItem(value: 'int', child: Text('Int')),
                          DropdownMenuItem(
                            value: 'double',
                            child: Text('Double'),
                          ),
                          DropdownMenuItem(value: 'bool', child: Text('Bool')),
                          DropdownMenuItem(value: 'map', child: Text('Map')),
                          DropdownMenuItem(value: 'list', child: Text('List')),
                        ],
                        onChanged: (vv) => typeCtrl.value = vv ?? 'string',
                      ),
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
    final t = typeCtrl.value;
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
      _pushHistory();
      map[k] = val;
      setState(() {
        _setRawEditorFromEditorPath();
        _valueControllers.removeWhere((p, c) => p.startsWith(mapPath));
      });
    } else {
      _showError('Target not map');
    }
  }

  Future<void> _addListItemDialog(String listPath) async {
    final typeCtrl = ValueNotifier<String>('string');
    final valueCtrl = TextEditingController();
    final res = await showDialog<bool?>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Add list item'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: typeCtrl,
                  builder:
                      (_, v, __) => DropdownButtonFormField<String>(
                        value: v,
                        items: const [
                          DropdownMenuItem(
                            value: 'string',
                            child: Text('String'),
                          ),
                          DropdownMenuItem(value: 'int', child: Text('Int')),
                          DropdownMenuItem(
                            value: 'double',
                            child: Text('Double'),
                          ),
                          DropdownMenuItem(value: 'bool', child: Text('Bool')),
                          DropdownMenuItem(value: 'map', child: Text('Map')),
                          DropdownMenuItem(value: 'list', child: Text('List')),
                        ],
                        onChanged: (vv) => typeCtrl.value = vv ?? 'string',
                      ),
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
    final t = typeCtrl.value;
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
    else {
      _pushHistory();
      setState(() {
        _setRawEditorFromEditorPath();
        _valueControllers.removeWhere((p, c) => p.startsWith(listPath));
      });
    }
  }

  void _moveListItemUp(String listPath, int idx) {
    final nav = JsonNavigator(_root);
    final list = nav.getNode(listPath);
    if (list is List && idx > 0) {
      _pushHistory();
      final tmp = list[idx - 1];
      list[idx - 1] = list[idx];
      list[idx] = tmp;
      setState(() {
        _setRawEditorFromEditorPath();
        _valueControllers.removeWhere((p, c) => p.startsWith(listPath));
      });
    }
  }

  void _moveListItemDown(String listPath, int idx) {
    final nav = JsonNavigator(_root);
    final list = nav.getNode(listPath);
    if (list is List && idx < list.length - 1) {
      _pushHistory();
      final tmp = list[idx + 1];
      list[idx + 1] = list[idx];
      list[idx] = tmp;
      setState(() {
        _setRawEditorFromEditorPath();
        _valueControllers.removeWhere((p, c) => p.startsWith(listPath));
      });
    }
  }

  // ---------- delete/rename/duplicate handlers for map & list ----------
  Future<void> _handleNodeMenuMap(
    Map parentMap,
    String key,
    int index,
    String path,
    String action,
  ) async {
    switch (action) {
      case 'open':
        setState(() => _editorPath = path);
        _setRawEditorFromEditorPath();
        break;
      case 'duplicate':
        _pushHistory();
        // duplicate directly below
        final nav = JsonNavigator(_root);
        final mapPath = _parentPath(path) ?? '';
        nav.duplicateNode(path);
        setState(() {
          _setRawEditorFromEditorPath();
        });
        break;
      case 'moveUp':
        _pushHistory();
        final mapPath = _parentPath(path) ?? '';
        final nav2 = JsonNavigator(_root);
        if (nav2.moveMapEntryUp(mapPath, key)) {
          setState(() {
            _setRawEditorFromEditorPath();
          });
        }
        break;
      case 'moveDown':
        _pushHistory();
        final mapPath2 = _parentPath(path) ?? '';
        final nav3 = JsonNavigator(_root);
        if (nav3.moveMapEntryDown(mapPath2, key)) {
          setState(() {
            _setRawEditorFromEditorPath();
          });
        }
        break;
      case 'rename':
        final ctrl = TextEditingController(text: key);
        final res = await showDialog<bool?>(
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
        if (res == true) {
          final newKey = ctrl.text.trim();
          if (newKey.isEmpty) return _showError('Key required');
          final nav4 = JsonNavigator(_root);
          final parentPath = _parentPath(path) ?? '';
          final ok = nav4.renameNode(
            parentPath,
            newKey,
          ); // rename inside parent map
          // but renameNode takes full path - construct full path:
          // Actually implement rename via map modification directly:
          final parent = nav4.getNode(parentPath);
          if (parent is Map<String, dynamic>) {
            if (parent.containsKey(newKey)) return _showError('Key exists');
            final val = parent.remove(key);
            _pushHistory();
            parent[newKey] = val;
            setState(() {
              _setRawEditorFromEditorPath();
            });
          } else {
            _showError('Rename failed');
          }
        }
        break;
      case 'delete':
        final ok = await showDialog<bool?>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Delete'),
                content: Text('Delete $key?'),
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
        if (ok == true) {
          _pushHistory();
          parentMap.remove(key);
          setState(() {
            _setRawEditorFromEditorPath();
          });
        }
        break;
    }
  }

  Future<void> _handleNodeMenuList(
    List parentList,
    int idx,
    String path,
    String action,
  ) async {
    switch (action) {
      case 'open':
        setState(() => _editorPath = path);
        _setRawEditorFromEditorPath();
        break;
      case 'duplicate':
        _pushHistory();
        final val = parentList[idx];
        parentList.insert(idx + 1, jsonDecode(jsonEncode(val)));
        setState(() {
          _setRawEditorFromEditorPath();
        });
        break;
      case 'moveUp':
        if (idx > 0) {
          _pushHistory();
          final tmp = parentList[idx - 1];
          parentList[idx - 1] = parentList[idx];
          parentList[idx] = tmp;
          setState(() {
            _setRawEditorFromEditorPath();
          });
        }
        break;
      case 'moveDown':
        if (idx < parentList.length - 1) {
          _pushHistory();
          final tmp = parentList[idx + 1];
          parentList[idx + 1] = parentList[idx];
          parentList[idx] = tmp;
          setState(() {
            _setRawEditorFromEditorPath();
          });
        }
        break;
      case 'delete':
        final ok = await showDialog<bool?>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Delete'),
                content: Text('Delete item $idx?'),
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
        if (ok == true) {
          _pushHistory();
          parentList.removeAt(idx);
          setState(() {
            _setRawEditorFromEditorPath();
          });
        }
        break;
    }
  }

  void _handleMapHeaderAction(String path, String action) {
    final nav = JsonNavigator(_root);
    if (action == 'duplicate') {
      _pushHistory();
      nav.duplicateNode(path);
      setState(() {
        _setRawEditorFromEditorPath();
      });
      return;
    }
    if (action == 'delete') {
      _deleteNodeConfirm(path);
      return;
    }
  }

  void _handleListHeaderAction(String path, String action) {
    final nav = JsonNavigator(_root);
    if (action == 'duplicate') {
      _pushHistory();
      nav.duplicateNode(path);
      setState(() {
        _setRawEditorFromEditorPath();
      });
      return;
    }
    if (action == 'delete') {
      _deleteNodeConfirm(path);
      return;
    }
  }

  Future<void> _deleteNodeConfirm(String path) async {
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
    _pushHistory();
    setState(() {
      _selectedPath = p.isEmpty ? null : p;
      _selectedValue = p.isEmpty ? null : nav.getNode(p);
      _editorPath = _selectedPath;
      _setRawEditorFromEditorPath();
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
      _pushHistory();
      map[newKey] = val;
      setState(() {
        _setRawEditorFromEditorPath();
      });
    }
  }

  String? _parentPath(String path) {
    if (!path.contains('/')) return '';
    final idx = path.lastIndexOf('/');
    return path.substring(0, idx);
  }

  // ---------- raw editor apply/save ----------
  Future<void> _saveRawEditorIfDirty() async {
    if (!_rawEditorDirty) return;
    if (_editorPath == null) return;
    final text = _rawEditorController.text;
    try {
      final parsed = jsonDecode(text);
      final nav = JsonNavigator(_root);
      _pushHistory();
      final ok = nav.setNode(_editorPath!, parsed);
      if (!ok) throw Exception('Apply failed');
      setState(() {
        // after applying, update raw editor to canonical formatting
        final current = nav.getNode(_editorPath!);
        final newText = const JsonEncoder.withIndent('  ').convert(current);
        _setRawEditorTextProgrammatic(newText);
        _jsonEditHistory.clear();
        _jsonEditHistory.add(newText);
        _jsonEditIndex = 0;
        _rawEditorDirty = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved JSON to model')));
    } catch (e) {
      _showError('Invalid JSON: $e');
    }
  }

  void _applyRawEditor() {
    // Only apply when button is pressed
    _saveRawEditorIfDirty();
  }

  void _setRawEditorTextProgrammatic(String txt) {
    final hadFocus = _rawEditorFocusNode.hasFocus;
    _rawEditorFocusNode.canRequestFocus = false;
    _rawEditorController.text = txt;
    _rawEditorDirty = false;
    _rawEditorFocusNode.canRequestFocus = true;
    if (hadFocus) _rawEditorFocusNode.requestFocus();
  }

  void _setRawEditorFromEditorPath() {
    final nav = JsonNavigator(_root);
    final node = _editorPath == null ? _root : nav.getNode(_editorPath!);
    final display =
        node == null ? '{}' : const JsonEncoder.withIndent('  ').convert(node);
    // Always set the raw editor to model state (no guard). This ensures perfect sync.
    _setRawEditorTextProgrammatic(display);
    // also reset local json edit history to the current model
    _jsonEditHistory.clear();
    _jsonEditHistory.add(display);
    _jsonEditIndex = 0;
  }

  // ---------- syntax highlighter for inspector view (readonly) ----------
  TextSpan _highlightJson(String src) {
    final children = <TextSpan>[];
    final reg = RegExp(
      r'(\"(\\\\.|[^\\\\\"])*\")|\b(-?\d+\.?\d*(?:[eE][+-]?\d+)?)\b|\b(true|false|null)\b|[{}\[\],:]',
      multiLine: true,
    );
    int last = 0;
    for (final m in reg.allMatches(src)) {
      if (m.start > last)
        children.add(
          TextSpan(
            text: src.substring(last, m.start),
            style: const TextStyle(color: Colors.black),
          ),
        );
      final tok = m.group(0)!;
      if (tok.startsWith('"'))
        children.add(
          TextSpan(text: tok, style: const TextStyle(color: Color(0xFF6A8759))),
        );
      else if (tok == 'true' || tok == 'false' || tok == 'null')
        children.add(
          TextSpan(text: tok, style: const TextStyle(color: Color(0xFF9876AA))),
        );
      else if (RegExp(r'^-?\d').hasMatch(tok))
        children.add(
          TextSpan(text: tok, style: const TextStyle(color: Color(0xFF6897BB))),
        );
      else
        children.add(
          TextSpan(
            text: tok,
            style: const TextStyle(
              color: Color(0xFFCC7832),
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      last = m.end;
    }
    if (last < src.length)
      children.add(
        TextSpan(
          text: src.substring(last),
          style: const TextStyle(color: Colors.black),
        ),
      );
    return TextSpan(
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      children: children,
    );
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
                Row(
                  children: [
                    Tooltip(
                      message: 'Undo last change',
                      child: IconButton(
                        onPressed: _undo,
                        icon: const Icon(Icons.undo),
                      ),
                    ),
                    Tooltip(
                      message: 'Redo',
                      child: IconButton(
                        onPressed: _redo,
                        icon: const Icon(Icons.redo),
                      ),
                    ),
                    Tooltip(
                      message: 'Clear document',
                      child: TextButton(
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
                            _jsonEditHistory.clear();
                            _jsonEditIndex = -1;
                            _rawEditorDirty = false;
                            _undoStack.clear();
                            _redoStack.clear();
                          });
                        },
                        child: const Text('Clear'),
                      ),
                    ),
                  ],
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
                Tooltip(
                  message: 'Validate document',
                  child: TextButton(
                    onPressed: _validateDocument,
                    child: const Text('Validate'),
                  ),
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
                              Tooltip(
                                message: 'Apply JSON from editor',
                                child: ElevatedButton(
                                  onPressed: _applyRawEditor,
                                  child: const Text('Apply'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Tooltip(
                                message: 'Reset JSON editor to model',
                                child: ElevatedButton(
                                  onPressed: () {
                                    _setRawEditorFromEditorPath();
                                    _jsonEditHistory.clear();
                                    _jsonEditHistory.add(
                                      _rawEditorController.text,
                                    );
                                    _jsonEditIndex = 0;
                                    _rawEditorDirty = false;
                                  },
                                  child: const Text('Reset'),
                                ),
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

  void _validateDocument() {
    try {
      jsonDecode(_rawEditorController.text);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Valid JSON')));
    } catch (e) {
      _showError('Invalid JSON: $e');
    }
  }

  Widget _buildInspector() {
    final nav = JsonNavigator(_root);
    final node = _editorPath == null ? _root : nav.getNode(_editorPath);
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
              child: Column(
                children: [
                  TabBar(
                    controller: _inspectorTabController,
                    tabs: const [Tab(text: 'View'), Tab(text: 'JSON')],
                    labelColor: Colors.black,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TabBarView(
                      controller: _inspectorTabController,
                      children: [
                        // View: readonly pretty syntax highlighted
                        Scrollbar(
                          controller: _inspectorVController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _inspectorVController,
                            child: Scrollbar(
                              controller: _inspectorHController,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: _inspectorHController,
                                scrollDirection: Axis.horizontal,
                                child: SelectableText.rich(
                                  _highlightJson(display),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // JSON Editor
                        Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Tooltip(message: 'JSON undo'),
                                IconButton(
                                  onPressed: _jsonUndo,
                                  icon: const Icon(Icons.undo),
                                ),
                                Tooltip(message: 'JSON redo'),
                                IconButton(
                                  onPressed: _jsonRedo,
                                  icon: const Icon(Icons.redo),
                                ),
                                Tooltip(message: 'Save JSON to model'),
                                IconButton(
                                  onPressed: _saveRawEditorIfDirty,
                                  icon: const Icon(Icons.save),
                                ),
                                PopupMenuButton<String>(
                                  tooltip: 'More actions',
                                  icon: const Icon(Icons.more_vert),
                                  onSelected: (v) {
                                    if (v == 'duplicate')
                                      _handleDuplicateNode();
                                    else if (v == 'rename')
                                      _handleRenameNode();
                                    else if (v == 'delete')
                                      _handleDeleteNode();
                                  },
                                  itemBuilder:
                                      (ctx) => const [
                                        PopupMenuItem(
                                          value: 'duplicate',
                                          child: Text('Duplicate'),
                                        ),
                                        PopupMenuItem(
                                          value: 'rename',
                                          child: Text('Rename'),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text(
                                            'Delete',
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        ),
                                      ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Focus(
                                onFocusChange: (hasFocus) {
                                  if (!hasFocus) {
                                    /* do nothing, apply only when requested */
                                  }
                                },
                                child: TextField(
                                  controller: _rawEditorController,
                                  focusNode: _rawEditorFocusNode,
                                  maxLines: null,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                  ),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                  ),
                                  onChanged: (v) {
                                    _rawEditorDirty =
                                        true; /* do not auto-apply to model */
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Tooltip(message: 'Apply raw JSON to model now'),
                                ElevatedButton(
                                  onPressed: _applyRawEditor,
                                  child: const Text('Apply JSON'),
                                ),
                                const SizedBox(width: 8),
                                Tooltip(
                                  message: 'Reset JSON editor to model state',
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    _setRawEditorFromEditorPath();
                                    _jsonEditHistory.clear();
                                    _jsonEditHistory.add(
                                      _rawEditorController.text,
                                    );
                                    _jsonEditIndex = 0;
                                    _rawEditorDirty = false;
                                  },
                                  child: const Text('Reset'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _jsonUndo() {
    if (_jsonEditIndex <= 0) return;
    _jsonEditIndex--;
    final txt = _jsonEditHistory[_jsonEditIndex];
    _setRawEditorTextProgrammatic(txt);
  }

  void _jsonRedo() {
    if (_jsonEditIndex < 0 || _jsonEditIndex >= _jsonEditHistory.length - 1)
      return;
    _jsonEditIndex++;
    final txt = _jsonEditHistory[_jsonEditIndex];
    _setRawEditorTextProgrammatic(txt);
  }

  void _handleDeleteNode() {
    if (_editorPath == null) return;
    _deleteNodeConfirm(_editorPath!);
  }

  void _handleDuplicateNode() {
    if (_editorPath == null) return;
    _pushHistory();
    final nav = JsonNavigator(_root);
    nav.duplicateNode(_editorPath!);
    setState(() {
      _setRawEditorFromEditorPath();
    });
  }

  void _handleRenameNode() {
    if (_editorPath == null) return;
    _promptRenameNode(_editorPath!);
  }

  Future<void> _promptRenameNode(String path) async {
    final parts = path.split('/');
    final oldName = parts.isNotEmpty ? parts.last : '';
    final controller = TextEditingController(text: oldName);
    final newName = await showDialog<String?>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Rename Node'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'New name'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('Rename'),
              ),
            ],
          ),
    );
    if (newName != null && newName.isNotEmpty && newName != oldName) {
      final parentPath = _parentPath(path) ?? '';
      final parent = JsonNavigator(_root).getNode(parentPath);
      if (parent is Map<String, dynamic>) {
        if (parent.containsKey(newName)) return _showError('Key exists');
        final val = parent.remove(oldName);
        _pushHistory();
        parent[newName] = val;
        setState(() {
          _setRawEditorFromEditorPath();
        });
      } else {
        _showError('Rename target is not a map');
      }
    }
  }

  // ---------- helpers ----------
  void _showError(String msg) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BDUI Builder - Stage2.6'),
        actions: [
          Tooltip(message: 'Paste BDUI JSON'),
          IconButton(
            onPressed: _pasteAndLoadJson,
            icon: const Icon(Icons.paste),
            tooltip: 'Paste JSON',
          ),
          Tooltip(message: 'Load sample config'),
          IconButton(
            onPressed: _loadSample,
            icon: const Icon(Icons.playlist_add_check),
            tooltip: 'Load sample',
          ),
          Tooltip(message: 'Copy config to clipboard'),
          IconButton(
            onPressed: _copyToClipboard,
            icon: const Icon(Icons.copy),
            tooltip: 'Copy',
          ),
          Tooltip(message: 'Undo'),
          IconButton(
            onPressed: _undo,
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
          ),
          Tooltip(message: 'Redo'),
          IconButton(
            onPressed: _redo,
            icon: const Icon(Icons.redo),
            tooltip: 'Redo',
          ),
          if (kIsWeb) Tooltip(message: 'Download JSON'),
          if (kIsWeb)
            IconButton(
              onPressed: _downloadJsonWeb,
              icon: const Icon(Icons.download),
              tooltip: 'Download',
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
