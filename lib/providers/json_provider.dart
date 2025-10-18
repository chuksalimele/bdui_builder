import 'package:flutter/foundation.dart';
import '../models/json_node.dart';

class JsonProvider extends ChangeNotifier {
  Map<String, dynamic> _data = {
    "container": {"type": "Column", "children": []}
  };

  Map<String, dynamic> get data => _data;

  void update(Map<String, dynamic> newData) {
    _data = newData;
    notifyListeners();
  }

  void updateNode(String path, dynamic newValue) {
    final keys = path.split('.');
    Map<String, dynamic> ref = _data;
    for (int i = 0; i < keys.length - 1; i++) {
      ref = ref[keys[i]];
    }
    ref[keys.last] = newValue;
    notifyListeners();
  }

  void deleteNode(String path) {
    final keys = path.split('.');
    Map<String, dynamic> ref = _data;
    for (int i = 0; i < keys.length - 1; i++) {
      ref = ref[keys[i]];
    }
    ref.remove(keys.last);
    notifyListeners();
  }

  void duplicateNode(String path) {
    final keys = path.split('.');
    Map<String, dynamic> ref = _data;
    for (int i = 0; i < keys.length - 1; i++) {
      ref = ref[keys[i]];
    }
    final last = keys.last;
    final node = ref[last];
    ref["${last}_copy"] = node is Map ? {...node} : node;
    notifyListeners();
  }
}
