class JsonNode {
  String key;
  dynamic value;
  bool expanded;
  JsonNode({required this.key, required this.value, this.expanded = false});

  bool get isLeaf => value is! Map && value is! List;
  Map<String, dynamic> toJson() => {key: value};
}
