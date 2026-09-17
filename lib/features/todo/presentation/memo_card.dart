import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/page_reload.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../../core/widgets/loading_error_view.dart';
import '../../../core/widgets/signed_out_placeholder.dart';
import '../application/todo_provider.dart';
import 'memo_section.dart';
import 'todo_error.dart';

class MemoCard extends ConsumerStatefulWidget {
  const MemoCard({super.key});

  @override
  ConsumerState<MemoCard> createState() => _MemoCardState();
}

class _MemoCardState extends ConsumerState<MemoCard> {
  final TextEditingController _memoTitleController = TextEditingController();
  final TextEditingController _memoContentController = TextEditingController();
  bool _memoInitialized = false;
  String? _selectedMemoId;

  @override
  void dispose() {
    _memoTitleController.dispose();
    _memoContentController.dispose();
    super.dispose();
  }

  Future<void> _selectMemo(String id) async {
    // cancelPendingEdits()는 예약된 저장을 버리기만 해서, 입력 직후(디바운스 500ms 안)
    // 다른 메모로 바로 전환하면 방금 입력한 내용이 저장 없이 사라졌다 — flushPending()으로
    // 바꿔 전환 전에 먼저 저장한다.
    await ref.read(todoMemoProvider.notifier).flushPending();
    if (!mounted) return;
    final memos = ref.read(todoMemoProvider).value ?? [];
    final index = memos.indexWhere((memo) => memo.id == id);
    if (index == -1) return;
    final memo = memos[index];
    setState(() {
      _selectedMemoId = memo.id;
      _memoTitleController.text = memo.title;
      _memoContentController.text = memo.content;
    });
  }

  Future<void> _addMemo() async {
    final memo = await ref.read(todoMemoProvider.notifier).addMemo();
    if (!mounted) return;
    if (memo != null) {
      _selectMemo(memo.id);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('메모는 최대 $maxMemoCount개까지 만들 수 있습니다.')));
    }
  }

  Future<void> _moveSelectedMemo(int delta) async {
    final id = _selectedMemoId;
    if (id == null) return;
    await ref.read(todoMemoProvider.notifier).moveMemo(id, delta);
  }

  Future<void> _deleteSelectedMemo() async {
    final id = _selectedMemoId;
    if (id == null) return;
    await ref.read(todoMemoProvider.notifier).removeMemo(id);
    final remaining = ref.read(todoMemoProvider).value ?? [];
    if (remaining.isEmpty) {
      setState(() {
        _selectedMemoId = null;
        _memoTitleController.clear();
        _memoContentController.clear();
      });
    } else {
      _selectMemo(remaining.first.id);
    }
  }

  void _onMemoTitleChanged(String value) {
    final id = _selectedMemoId;
    if (id == null) return;
    ref.read(todoMemoProvider.notifier).scheduleRename(id, value);
  }

  void _onMemoContentChanged(String value) {
    final id = _selectedMemoId;
    if (id == null) return;
    ref.read(todoMemoProvider.notifier).scheduleContent(id, value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authUidProvider);

    // 로그아웃(uid가 null이 됨)하면 이전 세션의 메모 선택 상태가 다음 로그인 때
    // 잘못 남아있지 않도록 초기화한다.
    ref.listen(authUidProvider, (previous, next) {
      if (next.value == null) {
        _selectedMemoId = null;
        _memoInitialized = false;
        _memoTitleController.clear();
        _memoContentController.clear();
      }
    });

    return DashboardCard(
      title: '메모',
      icon: Icons.sticky_note_2_outlined,
      accentColor: theme.extension<AppAccentColors>()?.memo,
      child: authState.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(message: error.toString(), onRetry: reloadPage),
        data: (uid) => uid == null ? const SignedOutPlaceholder() : _buildSignedInContent(),
      ),
    );
  }

  Widget _buildSignedInContent() {
    final memosAsync = ref.watch(todoMemoProvider);

    return memosAsync.when(
      loading: () => const LoadingView(),
      error: (error, _) => ErrorView(message: describeTodoDataError(error), onRetry: reloadPage),
      data: (memos) {
        // 메모 목록이 처음 도착했을 때 한 번만 첫 메모를 선택해 채운다(그 이후엔 사용자가
        // 선택/입력 중인 내용을 덮어쓰면 안 되므로). build() 안에서 직접 확인해야
        // 안전하다 — ref.listen은 리스너 등록 시점에 이미 있던 값에는 반응하지 않아서,
        // provider가 이미 데이터를 갖고 있는 상태로 이 State가 새로 생기면(예: 리사이즈로
        // 카드가 재마운트될 때) 영영 초기 선택이 안 채워지는 문제가 있었다.
        if (!_memoInitialized) {
          _memoInitialized = true;
          if (memos.isNotEmpty) {
            _selectedMemoId = memos.first.id;
            _memoTitleController.text = memos.first.title;
            _memoContentController.text = memos.first.content;
          }
        }
        return MemoSection(
          memos: memos,
          selectedMemoId: _selectedMemoId,
          titleController: _memoTitleController,
          contentController: _memoContentController,
          onSelect: _selectMemo,
          onAdd: _addMemo,
          onDelete: _deleteSelectedMemo,
          onMove: _moveSelectedMemo,
          onTitleChanged: _onMemoTitleChanged,
          onContentChanged: _onMemoContentChanged,
        );
      },
    );
  }
}
