/// 오늘 할 일 항목. 지금은 단일 목록(초기화 없음)으로만 쓰이지만, 차후 "이전 기록 조회"
/// 기능을 붙일 때 날짜별로 묶어 조회할 수 있도록 [createdAt]/[completedAt]을 미리 남겨둔다.
class TodoItem {
  const TodoItem({
    required this.id,
    required this.text,
    required this.done,
    required this.createdAt,
    this.completedAt,
  });

  final String id;
  final String text;
  final bool done;
  final DateTime createdAt;
  final DateTime? completedAt;

  TodoItem copyWith({bool? done, DateTime? completedAt}) {
    return TodoItem(
      id: id,
      text: text,
      done: done ?? this.done,
      createdAt: createdAt,
      completedAt: completedAt,
    );
  }

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    return TodoItem(
      id: json['id'] as String,
      text: json['text'] as String,
      done: json['done'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      completedAt: (json['completedAt'] as String?) == null ? null : DateTime.parse(json['completedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'done': done,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
    };
  }
}
