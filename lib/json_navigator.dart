// lib/json_navigator.dart
// Extracted from main.dart
import 'dart:convert';

/// Small navigator utility for JSON tree (map/list)
class JsonNavigator {
  Map<String, dynamic> root;
  JsonNavigator(this.root);

  dynamic getNode(String? path) {
    if (path == null || path.isEmpty) return root;
    final parts = path.split('/');
    dynamic cur = root;
    for (final p in parts) {
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
      else if (cur is List)
        cur = cur[int.parse(p)];
      else
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
      if (atIndex == null || atIndex < 0 || atIndex > list.length) {
        list.add(value);
      } else {
        list.insert(atIndex, value);
      }
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

  /// duplicate node and place duplicate directly below original
  bool duplicateNode(String path) {
    final node = getNode(path);
    if (node == null) return false;
    final parts = path.split('/');
    if (parts.isEmpty) return false;
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
    final copy = jsonDecode(jsonEncode(node)); // deep-copy
    if (parent is Map<String, dynamic>) {
      // place directly below: insert with a key like original_copy or original_copyN
      var newKey = '${last}_copy';
      var c = 1;
      while (parent.containsKey(newKey)) {
        newKey = '${last}_copy$c';
        c++;
      }
      // to place "below" in Map we rebuild map with insertion after key
      final newMap = <String, dynamic>{};
      parent.forEach((k, v) {
        newMap[k] = v;
        if (k == last) newMap[newKey] = copy;
      });
      parent
        ..clear()
        ..addAll(newMap);
      return true;
    } else if (parent is List) {
      final idx = int.tryParse(last);
      if (idx == null) return false;
      parent.insert(idx + 1, copy);
      return true;
    }
    return false;
  }

  /// rename a key inside a map (path must refer to a child key of a map)
  bool renameNode(String path, String newKey) {
    if (!path.contains('/')) return false;
    final parentPath = path.substring(0, path.lastIndexOf('/'));
    final oldKey = path.substring(path.lastIndexOf('/') + 1);
    final parent = getNode(parentPath);
    if (parent is Map<String, dynamic>) {
      if (!parent.containsKey(oldKey)) return false;
      if (parent.containsKey(newKey)) return false;
      final val = parent.remove(oldKey);
      parent[newKey] = val;
      return true;
    }
    return false;
  }

  /// move key up/down within a Map. index must be valid and newPos computed.
  bool moveMapKey(String mapPath, int index, int newPos) {
    final node = getNode(mapPath);
    if (node is Map<String, dynamic>) {
      final entries = node.entries.toList();
      if (index < 0 || index >= entries.length) return false;
      if (newPos < 0 || newPos >= entries.length) return false;
      final kv = entries.removeAt(index);
      entries.insert(newPos, kv);
      node
        ..clear()
        ..addEntries(entries);
      return true;
    }
    return false;
  }
}
