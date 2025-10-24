// lib/stage26_page.dart
// Extracted from main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'dart:async';
import 'dart:html' as html;
import 'json_navigator.dart';
import 'json_editor_view.dart';

class Stage26Page extends StatefulWidget {
  const Stage26Page({super.key});
  @override
  State<Stage26Page> createState() => _Stage26PageState();
}

class _Stage26PageState extends State<Stage26Page>
    with TickerProviderStateMixin {
  Map<String, dynamic> _root = {};
  String? _selectedPath; // sidebar focus
  String? _editorPath; // visual editor context (breadcrumbs)
  final Map<String, GlobalKey> _tileKeys = {};
  final Map<String, GlobalKey> _titleKeys = {};
  final ScrollController _sidebarScroll = ScrollController();
  final GlobalKey _sidebarRootKey = GlobalKey();

  // inspector controllers
  final TextEditingController _rawEditorController = TextEditingController();
  final FocusNode _rawEditorFocus = FocusNode();
  bool _inspectorEditable = false;
  bool _rawEditorDirty = false;

  // Inspector scroll controllers
  final ScrollController _inspectorH = ScrollController();
  final ScrollController _inspectorV = ScrollController();

  // history
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  static const int _historyLimit = 100;

  // json-editor local history (undo/redo)
  final List<String> _jsonEditHistory = [];
  int _jsonEditIndex = -1;

  @override
  void initState() {
    super.initState();
    // load a sample automatically (small sample)
    _loadSample();
    _rawEditorController.addListener(() {
      // mark dirty when user edits and only if inspector is editable
      if (!_inspectorEditable) return;
      _rawEditorDirty = true;
    });
    _rawEditorFocus.addListener(() {
      if (!_rawEditorFocus.hasFocus) {
        // when focus lost we DO NOT auto-apply (apply is manual)
        // but ensure editor text stored in local json history
        _pushJsonEditorHistory(_rawEditorController.text);
      }
    });
  }

  @override
  void dispose() {
    _rawEditorController.dispose();
    _rawEditorFocus.dispose();
    _sidebarScroll.dispose();
    _inspectorH.dispose();
    _inspectorV.dispose();
    super.dispose();
  }

  // ---------- helpers ----------
  void _pushSnapshot() {
    try {
      final snap = const JsonEncoder.withIndent('  ').convert(_root);
      if (_undoStack.isEmpty || _undoStack.last != snap) {
        _undoStack.add(snap);
        if (_undoStack.length > _historyLimit) _undoStack.removeAt(0);
        _redoStack.clear();
      }
    } catch (_) {}
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final cur = const JsonEncoder.withIndent('  ').convert(_root);
    _redoStack.add(cur);
    final prev = _undoStack.removeLast();
    try {
      final parsed = jsonDecode(prev) as Map<String, dynamic>;
      setState(() {
        _root = parsed;
        _selectedPath = null;
        _editorPath = null;
        _syncInspectorToEditorPath();
      });
    } catch (e) {
      _showSnack('Undo failed: $e');
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
        _selectedPath = null;
        _editorPath = null;
        _syncInspectorToEditorPath();
      });
    } catch (e) {
      _showSnack('Redo failed: $e');
    }
  }

  void _pushJsonEditorHistory(String txt) {
    if (txt.isEmpty && _jsonEditHistory.isEmpty) return;
    if (_jsonEditIndex >= 0 &&
        _jsonEditIndex < _jsonEditHistory.length &&
        _jsonEditHistory[_jsonEditIndex] == txt)
      return;
    // drop any redo branch
    if (_jsonEditIndex < _jsonEditHistory.length - 1) {
      _jsonEditHistory.removeRange(_jsonEditIndex + 1, _jsonEditHistory.length);
    }
    _jsonEditHistory.add(txt);
    if (_jsonEditHistory.length > 200) _jsonEditHistory.removeAt(0);
    _jsonEditIndex = _jsonEditHistory.length - 1;
  }

  void _jsonEditorUndo() {
    if (_jsonEditIndex <= 0) return;
    _jsonEditIndex--;
    _setInspectorTextProgrammatic(_jsonEditHistory[_jsonEditIndex]);
  }

  void _jsonEditorRedo() {
    if (_jsonEditIndex < 0 || _jsonEditIndex >= _jsonEditHistory.length - 1)
      return;
    _jsonEditIndex++;
    _setInspectorTextProgrammatic(_jsonEditHistory[_jsonEditIndex]);
  }

  void _setInspectorTextProgrammatic(String txt) {
    //debugPrint('setInspectorTextProgrammatic');
    final hadFocus = _rawEditorFocus.hasFocus;
    _rawEditorFocus.canRequestFocus = false;
    _rawEditorController.text = txt;
    _rawEditorDirty = false;
    _pushJsonEditorHistory(txt);
    _rawEditorFocus.canRequestFocus = true;
    if (hadFocus) _rawEditorFocus.requestFocus();
  }

  void _showSnack(String msg) {
    // safe call in build context
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    });
  }

  // ---------- IO ----------
  Future<String?> _pasteDialog() {
    final ctrl = TextEditingController();
    return showDialog<String?>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Paste JSON'),
            content: SizedBox(
              height: 260,
              child: TextField(controller: ctrl, maxLines: null),
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

  Future<void> _pasteAndLoad() async {
    final txt = await _pasteDialog();
    if (txt == null || txt.trim().isEmpty) return;
    _loadJsonString(txt);
  }

  void _loadJsonString(String txt, {bool pushHistory = true}) {
    try {
      final parsed = jsonDecode(txt);
      if (parsed is Map<String, dynamic>) {
        if (pushHistory) _pushSnapshot();
        setState(() {
          _root = parsed;
          _selectedPath = null;
          _editorPath = null;
          _syncInspectorToEditorPath();
        });
        _showSnack('JSON loaded');
      } else {
        _showSnack('Root must be an object');
      }
    } catch (e) {
      _showSnack('Invalid JSON: $e');
    }
  }

  void _loadSample() {
    const sample = '''
{
  "globalVariable": {
    "selectedCategoryOnCategoryPage": {"type": "String", "defaultValue": ""},
    "selectedLocation": {"type": "String", "defaultValue": ""}
  },
  "pages": [
    {"pageName": "home"},
    {"pageName": "category"}
  ]
}
''';
    _loadJsonString(sample, pushHistory: false);
  }

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(_root)),
    );
    _showSnack('Copied to clipboard');
  }

  void _downloadWeb() {
    if (!kIsWeb) return;
    try {
      final str = const JsonEncoder.withIndent('  ').convert(_root);
      final bytes = utf8.encode(str);
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final a =
          html.document.createElement('a') as html.AnchorElement
            ..href = url
            ..download = 'bdui-config.json';
      html.document.body?.append(a);
      a.click();
      a.remove();
      html.Url.revokeObjectUrl(url);
      _showSnack('Download started');
    } catch (e) {
      _showSnack('Download failed: $e');
    }
  }

  // ---------- selection & sidebar scrolling ----------
  void _selectPath(String path, {bool ensureCenter = true}) {
    final nav = JsonNavigator(_root);
    final val = nav.getNode(path);
    setState(() {
      _selectedPath = path;
      _editorPath = path;
      // inspector must always sync to model per your request:
      final txt =
          val == null ? '{}' : const JsonEncoder.withIndent('  ').convert(val);
      _setInspectorTextProgrammatic(txt);
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
  Widget _buildTreeWidgets(Map<String, dynamic> map, [String parent = '']) {
    final List<Widget> items = [];
    map.forEach((k, v) {
      final path = parent.isEmpty ? k : '$parent/$k';
      items.add(_buildNodeWidget(k, path, v));
    });
    return Column(children: items);
  }

  Widget _buildNodeWidget(String label, String path, dynamic value) {
    final tileKey = _tileKeys.putIfAbsent(path, () => GlobalKey());
    final titleKey = _titleKeys.putIfAbsent(path, () => GlobalKey());
    if (value is Map<String, dynamic>) {
      return ExpansionTile(
        key: PageStorageKey(path),
        onExpansionChanged: (expanded) {
          if (expanded)
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _selectPath(path),
            );
        },
        title: GestureDetector(
          key: titleKey,
          onTap: () => _selectPath(path),
          child: _tileTitle(label, path, isContainer: true),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: _buildTreeWidgets(value, path),
          ),
        ],
      );
    } else if (value is List) {
      final children = <Widget>[];
      for (int i = 0; i < value.length; i++) {
        final childPath = '$path/$i';
        children.add(_buildNodeWidget('$label[$i]', childPath, value[i]));
      }
      return ExpansionTile(
        key: PageStorageKey(path),
        onExpansionChanged: (expanded) {
          if (expanded)
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _selectPath(path),
            );
        },
        title: GestureDetector(
          key: titleKey,
          onTap: () => _selectPath(path),
          child: _tileTitle('$label [List]', path, isContainer: true),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(children: children),
          ),
        ],
      );
    } else {
      return ListTile(
        key: tileKey,
        title: GestureDetector(
          key: titleKey,
          onTap: () => _selectPath(path),
          child: _tileTitle(label, path, value: value),
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
    final sel = _selectedPath == path;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: sel ? Colors.blue.shade50 : Colors.transparent,
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
                    color: sel ? Colors.blue.shade700 : Colors.grey,
                  ),
                if (isContainer) const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                      color: sel ? Colors.blue.shade900 : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (value != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 120),
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
    final crumbs = _editorPath!.split('/');
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
        Expanded(child: _buildImmediateEditor(_editorPath!, node)),
      ],
    );
  }

  Widget _buildImmediateEditor(String path, dynamic node) {
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
                  Tooltip(
                    message: 'More actions',
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (v) => _handleMapNodeMenu(node, path, v),
                      itemBuilder:
                          (ctx) => const [
                            PopupMenuItem(
                              value: 'duplicate',
                              child: Text('Duplicate'),
                            ),
                            PopupMenuItem(
                              value: 'moveUp',
                              child: Text('Move Up'),
                            ),
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
    } else if (node is List) {
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
                      onSelected: (v) => _handleListNodeMenu(list, -1, path, v),
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
    } else {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Value at $path'),
            const SizedBox(height: 8),
            _primitiveEditor(path, node),
          ],
        ),
      );
    }
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
              Expanded(child: _primitiveEditor(childPath, value)),
              Tooltip(
                message: 'More actions',
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected:
                      (v) => _handleMapChildMenu(
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
                (v) => _handleMapChildMenu(parentMap, key, index, childPath, v),
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
              Expanded(child: _primitiveEditor(childPath, value)),
              Tooltip(
                message: 'More actions',
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected:
                      (v) =>
                          _handleListChildMenu(parentList, idx, childPath, v),
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
                (v) => _handleListChildMenu(parentList, idx, childPath, v),
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

  // primitive editor: int/double/bool/string/null
  Widget _primitiveEditor(String path, dynamic value) {
    if (value is bool) {
      return Switch(
        value: value,
        onChanged: (v) {
          _pushSnapshot();
          JsonNavigator(_root).setNode(path, v);
          setState(() {
            _syncInspectorToEditorPath();
          });
        },
      );
    } else if (value is int) {
      final ctrl = TextEditingController(text: value.toString());
      return Row(
        children: [
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: () {
              _pushSnapshot();
              JsonNavigator(_root).setNode(path, value - 1);
              setState(() => _syncInspectorToEditorPath());
            },
          ),
          SizedBox(
            width: 120,
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              onSubmitted: (s) {
                final n = int.tryParse(s);
                if (n != null) {
                  _pushSnapshot();
                  JsonNavigator(_root).setNode(path, n);
                  setState(() => _syncInspectorToEditorPath());
                }
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              _pushSnapshot();
              JsonNavigator(_root).setNode(path, value + 1);
              setState(() => _syncInspectorToEditorPath());
            },
          ),
        ],
      );
    } else if (value is double) {
      final ctrl = TextEditingController(text: value.toString());
      return Row(
        children: [
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: () {
              _pushSnapshot();
              JsonNavigator(_root).setNode(path, (value - 0.1));
              setState(() => _syncInspectorToEditorPath());
            },
          ),
          SizedBox(
            width: 140,
            child: TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onSubmitted: (s) {
                final n = double.tryParse(s);
                if (n != null) {
                  _pushSnapshot();
                  JsonNavigator(_root).setNode(path, n);
                  setState(() => _syncInspectorToEditorPath());
                }
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              _pushSnapshot();
              JsonNavigator(_root).setNode(path, (value + 0.1));
              setState(() => _syncInspectorToEditorPath());
            },
          ),
        ],
      );
    } else {
      // string or null
      final ctrl = TextEditingController(text: value?.toString() ?? '');
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              onSubmitted: (s) {
                _pushSnapshot();
                JsonNavigator(_root).setNode(path, s);
                setState(() => _syncInspectorToEditorPath());
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _pushSnapshot();
              JsonNavigator(_root).setNode(path, '');
              setState(() => _syncInspectorToEditorPath());
            },
          ),
        ],
      );
    }
  }

  // ---------- node menus handlers ----------
  void _handleMapNodeMenu(Map node, String mapPath, String action) {
    // map-level actions: duplicate entire map node, move up/down map within parent, delete
    switch (action) {
      case 'duplicate':
        _pushSnapshot();
        JsonNavigator(_root).duplicateNode(mapPath);
        setState(() => _syncInspectorToEditorPath());
        break;
      case 'moveUp':
        // find parent and index of this map key
        final parentPath = _parentPath(mapPath);
        if (parentPath == null || parentPath.isEmpty) break;
        final parent = JsonNavigator(_root).getNode(parentPath);
        if (parent is Map<String, dynamic>) {
          final key = mapPath.substring(mapPath.lastIndexOf('/') + 1);
          final idx = parent.keys.toList().indexOf(key);
          if (idx > 0) {
            _pushSnapshot();
            JsonNavigator(_root).moveMapKey(parentPath, idx, idx - 1);
            setState(() => _syncInspectorToEditorPath());
          }
        } else if (parent is List) {
          final idx = int.tryParse(mapPath.split('/').last) ?? -1;
          if (idx > 0) {
            _pushSnapshot();
            final list = parent;
            final tmp = list[idx - 1];
            list[idx - 1] = list[idx];
            list[idx] = tmp;
            setState(() => _syncInspectorToEditorPath());
          }
        }
        break;
      case 'moveDown':
        final parentPath = _parentPath(mapPath);
        if (parentPath == null || parentPath.isEmpty) break;
        final parent = JsonNavigator(_root).getNode(parentPath);
        if (parent is Map<String, dynamic>) {
          final key = mapPath.substring(mapPath.lastIndexOf('/') + 1);
          final keys = parent.keys.toList();
          final idx = keys.indexOf(key);
          if (idx >= 0 && idx < keys.length - 1) {
            _pushSnapshot();
            JsonNavigator(_root).moveMapKey(parentPath, idx, idx + 1);
            setState(() => _syncInspectorToEditorPath());
          }
        } else if (parent is List) {
          final idx = int.tryParse(mapPath.split('/').last) ?? -1;
          final list = parent;
          if (idx >= 0 && idx < list.length - 1) {
            _pushSnapshot();
            final tmp = list[idx + 1];
            list[idx + 1] = list[idx];
            list[idx] = tmp;
            setState(() => _syncInspectorToEditorPath());
          }
        }
        break;
      case 'delete':
        _deleteNodeConfirm(mapPath);
        break;
    }
  }

  void _handleMapChildMenu(
    Map parentMap,
    String key,
    int idx,
    String childPath,
    String action,
  ) async {
    switch (action) {
      case 'open':
        setState(() => _editorPath = childPath);
        break;
      case 'duplicate':
        _pushSnapshot();
        final val = parentMap[key];
        // insert copy directly after this key (rebuild order)
        var newKey = '${key}_copy';
        var i = 1;
        while (parentMap.containsKey(newKey)) {
          newKey = '${key}_copy$i';
          i++;
        }
        final newMap = <String, dynamic>{};
        parentMap.forEach((k, v) {
          newMap[k] = v;
          if (k == key) newMap[newKey] = jsonDecode(jsonEncode(val));
        });
        parentMap
          ..clear()
          ..addAll(newMap);
        setState(() => _syncInspectorToEditorPath());
        break;
      case 'moveUp':
        // move key up within parentMap
        final keys = parentMap.keys.toList();
        final pos = keys.indexOf(key);
        if (pos > 0) {
          _pushSnapshot();
          JsonNavigator(
            _root,
          ).moveMapKey(_parentPathForKey(parentMap) ?? '', pos, pos - 1);
          setState(() => _syncInspectorToEditorPath());
        }
        break;
      case 'moveDown':
        final keys = parentMap.keys.toList();
        final pos = keys.indexOf(key);
        if (pos >= 0 && pos < keys.length - 1) {
          _pushSnapshot();
          JsonNavigator(
            _root,
          ).moveMapKey(_parentPathForKey(parentMap) ?? '', pos, pos + 1);
          setState(() => _syncInspectorToEditorPath());
        }
        break;
      case 'rename':
        final newK = await _promptRenameKey(key);
        if (newK != null && newK.isNotEmpty && newK != key) {
          if (parentMap.containsKey(newK)) return _showSnack('Key exists');
          _pushSnapshot();
          final val = parentMap.remove(key);
          parentMap[newK] = val;
          setState(() => _syncInspectorToEditorPath());
        }
        break;
      case 'delete':
        final ok = await showDialog<bool?>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Delete'),
                content: Text('Delete "$key"?'),
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
          _pushSnapshot();
          parentMap.remove(key);
          setState(() => _syncInspectorToEditorPath());
        }
        break;
    }
  }

  void _handleListNodeMenu(
    List parentList,
    int idx,
    String path,
    String action,
  ) async {
    switch (action) {
      case 'duplicate':
        _pushSnapshot();
        if (idx == -1) {
          // duplicate entire list node
          JsonNavigator(_root).duplicateNode(path);
        } else {
          final val = parentList[idx];
          parentList.insert(idx + 1, jsonDecode(jsonEncode(val)));
        }
        setState(() => _syncInspectorToEditorPath());
        break;
      case 'delete':
        if (idx == -1) {
          // delete entire list node
          _deleteNodeConfirm(path);
        }
        break;
    }
  }

  void _handleListChildMenu(
    List parentList,
    int idx,
    String childPath,
    String action,
  ) async {
    switch (action) {
      case 'open':
        setState(() => _editorPath = childPath);
        break;
      case 'duplicate':
        _pushSnapshot();
        final val = parentList[idx];
        parentList.insert(idx + 1, jsonDecode(jsonEncode(val)));
        setState(() => _syncInspectorToEditorPath());
        break;
      case 'moveUp':
        if (idx > 0) {
          _pushSnapshot();
          final tmp = parentList[idx - 1];
          parentList[idx - 1] = parentList[idx];
          parentList[idx] = tmp;
          setState(() => _syncInspectorToEditorPath());
        }
        break;
      case 'moveDown':
        if (idx < parentList.length - 1) {
          _pushSnapshot();
          final tmp = parentList[idx + 1];
          parentList[idx + 1] = parentList[idx];
          parentList[idx] = tmp;
          setState(() => _syncInspectorToEditorPath());
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
          _pushSnapshot();
          parentList.removeAt(idx);
          setState(() => _syncInspectorToEditorPath());
        }
        break;
    }
  }

  // helper: find parent path for a given map reference - not perfect, best effort
  String? _parentPathForKey(Map mapRef) {
    // traverse tree to find parent path where identical map instance is located
    String? found;
    void walk(dynamic node, String path) {
      if (found != null) return;
      if (identical(node, mapRef)) {
        found = path;
        return;
      }
      if (node is Map<String, dynamic>) {
        node.forEach((k, v) {
          walk(v, path.isEmpty ? k : '$path/$k');
        });
      } else if (node is List) {
        for (int i = 0; i < node.length; i++) {
          walk(node[i], path.isEmpty ? '$i' : '$path/$i');
        }
      }
    }

    walk(_root, '');
    return found;
  }

  Future<String?> _promptRenameKey(String oldKey) {
    final ctrl = TextEditingController(text: oldKey);
    return showDialog<String?>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Rename key'),
            content: TextField(controller: ctrl),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Rename'),
              ),
            ],
          ),
    );
  }

  // ---------- add dialogs ----------
  Future<void> _addMapKeyDialog(String mapPath) async {
    final keyCtrl = TextEditingController();
    var type = 'string';
    final valueCtrl = TextEditingController();
    final ok = await showDialog<bool?>(
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
                  onChanged: (v) => type = v ?? 'string',
                ),
                TextField(
                  controller: valueCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Value (primitives only)',
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
    if (ok != true) return;
    final key = keyCtrl.text.trim();
    if (key.isEmpty) return _showSnack('Key required');
    dynamic val;
    if (type == 'int')
      val = int.tryParse(valueCtrl.text) ?? 0;
    else if (type == 'double')
      val = double.tryParse(valueCtrl.text) ?? 0.0;
    else if (type == 'bool')
      val = (valueCtrl.text.toLowerCase() == 'true');
    else if (type == 'map')
      val = <String, dynamic>{};
    else if (type == 'list')
      val = <dynamic>[];
    else
      val = valueCtrl.text;
    final nav = JsonNavigator(_root);
    final map = nav.getNode(mapPath);
    if (map is Map<String, dynamic>) {
      if (map.containsKey(key)) return _showSnack('Key exists');
      _pushSnapshot();
      // insert at end (or we could attempt to place near selection)
      map[key] = val;
      setState(() => _syncInspectorToEditorPath());
    } else {
      _showSnack('Target not a map');
    }
  }

  Future<void> _addListItemDialog(String listPath) async {
    var type = 'string';
    final valueCtrl = TextEditingController();
    final ok = await showDialog<bool?>(
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
                  onChanged: (v) => type = v ?? 'string',
                ),
                TextField(
                  controller: valueCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Value (primitives only)',
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
    if (ok != true) return;
    dynamic val;
    if (type == 'int')
      val = int.tryParse(valueCtrl.text) ?? 0;
    else if (type == 'double')
      val = double.tryParse(valueCtrl.text) ?? 0.0;
    else if (type == 'bool')
      val = (valueCtrl.text.toLowerCase() == 'true');
    else if (type == 'map')
      val = <String, dynamic>{};
    else if (type == 'list')
      val = <dynamic>[];
    else
      val = valueCtrl.text;
    final nav = JsonNavigator(_root);
    final ok2 = nav.insertIntoList(listPath, val);
    if (!ok2)
      _showSnack('Target not a list');
    else {
      _pushSnapshot();
      setState(() => _syncInspectorToEditorPath());
    }
  }

  // ---------- delete/rename/duplicate helpers ----------
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
    if (!success) return _showSnack('Delete failed');
    _pushSnapshot();
    setState(() {
      final p = _parentPath(path) ?? '';
      _selectedPath = p.isEmpty ? null : p;
      _editorPath = _selectedPath;
      _syncInspectorToEditorPath();
    });
  }

  Future<void> _promptRenameNode(String path) async {
    final parts = path.split('/');
    final old = parts.isNotEmpty ? parts.last : '';
    final ctrl = TextEditingController(text: old);
    final newName = await showDialog<String?>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Rename'),
            content: TextField(controller: ctrl),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Rename'),
              ),
            ],
          ),
    );
    if (newName == null || newName.isEmpty || newName == old) return;
    final nav = JsonNavigator(_root);
    final ok = nav.renameNode(path, newName);
    if (!ok) return _showSnack('Rename failed or key exists');
    _pushSnapshot();
    setState(() => _syncInspectorToEditorPath());
  }

  // ---------- inspector sync & editor apply/reset ----------
  void _syncInspectorToEditorPath() {
    final nav = JsonNavigator(_root);
    final node = _editorPath == null ? _root : nav.getNode(_editorPath!);
    final txt =
        node == null ? '{}' : const JsonEncoder.withIndent('  ').convert(node);
    // Per your requirement: inspector JSON must always sync with visual editor.
    // That means we update the inspector text programmatically whenever model changes.
    // This will overwrite unsaved edits in the inspector. This follows your instruction.
    _setInspectorTextProgrammatic(txt);
  }

  void _applyRawEditor() {
    // Manual apply only when user clicks Apply
    if (_editorPath == null) return;
    try {
      final parsed = jsonDecode(_rawEditorController.text);
      final nav = JsonNavigator(_root);
      _pushSnapshot();
      final ok = nav.setNode(_editorPath!, parsed);
      if (!ok) throw Exception('Set failed');
      setState(() {
        _rawEditorDirty = false;
        _syncInspectorToEditorPath();
        _showSnack('Applied JSON to model');
      });
    } catch (e) {
      _showSnack('Invalid JSON: $e');
    }
  }

  void _resetInspectorToEditorPath() {
    _syncInspectorToEditorPath();
    _rawEditorDirty = false;
    _showSnack('Inspector reset to model');
  }

  // helper: parent path substring
  String? _parentPath(String path) {
    if (!path.contains('/')) return '';
    final idx = path.lastIndexOf('/');
    return path.substring(0, idx);
  }

  // ---------- UI building ----------
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
                    Tooltip(message: 'Undo'),
                    IconButton(onPressed: _undo, icon: const Icon(Icons.undo)),
                    Tooltip(message: 'Redo'),
                    IconButton(onPressed: _redo, icon: const Icon(Icons.redo)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child:
                _root.isEmpty
                    ? const Center(child: Text('No document loaded'))
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

  TextSpan _syntaxHighlightJson(String src) {
    // lightweight JSON highlighter for SelectableText.rich
    final List<TextSpan> spans = [];
    final reg = RegExp(
      r'(\"(\\.|[^"\\])*")|(\b(true|false|null)\b)|(-?\d+(\.\d+)?([eE][+-]?\d+)?)|[{}\[\],:]',
    );
    int last = 0;
    for (final m in reg.allMatches(src)) {
      if (m.start > last)
        spans.add(
          TextSpan(
            text: src.substring(last, m.start),
            style: const TextStyle(color: Colors.black),
          ),
        );
      final tok = m.group(0)!;
      TextStyle style;
      if (tok.startsWith('"'))
        style = const TextStyle(color: Color(0xFF6A8759)); // string
      else if (tok == 'true' || tok == 'false' || tok == 'null')
        style = const TextStyle(color: Color(0xFF9876AA)); // keyword
      else if (RegExp(r'^-?\d').hasMatch(tok))
        style = const TextStyle(color: Color(0xFF6897BB)); // number
      else
        style = const TextStyle(
          color: Color(0xFFCC7832),
          fontWeight: FontWeight.bold,
        ); // braces/punct
      spans.add(TextSpan(text: tok, style: style));
      last = m.end;
    }
    if (last < src.length)
      spans.add(
        TextSpan(
          text: src.substring(last),
          style: const TextStyle(color: Colors.black),
        ),
      );
    return TextSpan(
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      children: spans,
    );
  }

  Widget _buildInspector() {
    debugPrint('Rebuilding inspector for path: $_editorPath');
    final nav = JsonNavigator(_root);
    final node = _editorPath == null ? _root : nav.getNode(_editorPath!);
    final display =
        node == null ? '{}' : const JsonEncoder.withIndent('  ').convert(node);
    // inspectorHeader with toggle and actions
    return Container(
      color: Colors.grey.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                const Text(
                  'Inspector',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Tooltip(
                  message:
                      _inspectorEditable
                          ? 'Switch to read-only'
                          : 'Switch to editable',
                  child: IconButton(
                    icon: Icon(
                      _inspectorEditable ? Icons.lock_open : Icons.lock,
                    ),
                    onPressed: () {
                      setState(() {
                        _inspectorEditable = !_inspectorEditable;
                        // when switching to editable, ensure the text is up-to-date
                        _setInspectorTextProgrammatic(
                          const JsonEncoder.withIndent(
                            '  ',
                          ).convert(node ?? {}),
                        );
                      });
                    },
                  ),
                ),

                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (v) {
                    switch (v) {
                      case 'duplicate':
                        if (_editorPath != null) {
                          _pushSnapshot();
                          JsonNavigator(_root).duplicateNode(_editorPath!);
                          setState(() => _syncInspectorToEditorPath());
                        }
                        break;
                      case 'rename':
                        if (_editorPath != null)
                          _promptRenameNode(_editorPath!);
                        break;
                      case 'delete':
                        if (_editorPath != null)
                          _deleteNodeConfirm(_editorPath!);
                        break;
                    }
                  },
                  itemBuilder:
                      (ctx) => const [
                        PopupMenuItem(
                          value: 'duplicate',
                          child: Text('Duplicate'),
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
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  // JSON view or editable field (single view toggled)
                  Expanded(
                    child: Scrollbar(
                      controller: _inspectorV,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _inspectorV,
                        child: Scrollbar(
                          controller: _inspectorH,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _inspectorH,
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: 600),
                              child:
                                  _inspectorEditable
                                      ? SizedBox(
                                        height:
                                            MediaQuery.of(context).size.height -
                                            200,
                                        width: 1000,
                                        child: JsonEditorView(
                                          key: Key(display),
                                          initialJson: display,
                                          onChanged: (updated) {
                                            _rawEditorController.text = updated;
                                            _rawEditorDirty = true;
                                          },
                                        ),
                                      )
                                      : SelectableText.rich(
                                        _syntaxHighlightJson(display),
                                      ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    /*const SizedBox(height: 8)*/
                  ),
                  // Apply/Reset below the editor as requested
                  Row(
                    children: [
                      Tooltip(message: 'Apply manual JSON changes to model'),
                      ElevatedButton(
                        onPressed: _inspectorEditable ? _applyRawEditor : null,
                        child: const Text('Apply'),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(message: 'Reset inspector JSON to model'),
                      ElevatedButton(
                        onPressed: _resetInspectorToEditorPath,
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

  // ---------- utility used by many widgets ----------
  void _setInspectorFromRoot() {
    _syncInspectorToEditorPath();
  }

  void _setInspectorTextProgrammaticNoHistory(String txt) {
    final hadFocus = _rawEditorFocus.hasFocus;
    _rawEditorFocus.canRequestFocus = false;
    _rawEditorController.text = txt;
    _rawEditorDirty = false;
    _rawEditorFocus.canRequestFocus = true;
    if (hadFocus) _rawEditorFocus.requestFocus();
  }

  // alias to match earlier naming
  //void _setInspectorTextProgrammatic(String txt) => _setInspectorTextProgrammaticNoHistory(txt);

  void _setInspectorToEditorPath() => _resetInspectorToEditorPath();

  // ---------- UI composition ----------
  @override
  Widget build(BuildContext context) {
    final leftWidth = (MediaQuery.of(context).size.width * 0.28).clamp(
      240.0,
      520.0,
    );
    final rightWidth = (MediaQuery.of(context).size.width * 0.34).clamp(
      280.0,
      680.0,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('BDUI Builder - Stage2.6'),
        actions: [
          IconButton(
            onPressed: _pasteAndLoad,
            tooltip: 'Paste JSON',
            icon: const Icon(Icons.paste),
          ),
          IconButton(
            onPressed: _loadSample,
            tooltip: 'Load sample',
            icon: const Icon(Icons.playlist_add_check),
          ),
          IconButton(
            onPressed: _copyToClipboard,
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
          ),
          IconButton(
            onPressed: _undo,
            tooltip: 'Undo',
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            onPressed: _redo,
            tooltip: 'Redo',
            icon: const Icon(Icons.redo),
          ),
          if (kIsWeb)
            IconButton(
              onPressed: _downloadWeb,
              tooltip: 'Download',
              icon: const Icon(Icons.download),
            ),
        ],
      ),
      body: Row(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints.tightFor(width: leftWidth),
            child: _buildSidebar(),
          ),
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
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'Selected: ${_selectedPath ?? "<none>"}',
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed:
                              () => _showSnack(
                                'Validation performed (placeholder)',
                              ),
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
                                ],
                              ),
                            ),
                  ),
                ],
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints.tightFor(width: rightWidth),
            child: _buildInspector(),
          ),
        ],
      ),
    );
  }
}
