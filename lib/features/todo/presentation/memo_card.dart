import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../../core/widgets/loading_error_view.dart';
import '../../../core/widgets/signed_out_placeholder.dart';
import '../application/todo_provider.dart';
import '../data/memo_item.dart';
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
  bool _retryingSave = false;

  // 편집창에 마지막으로 채워 넣은 서버 값. 편집창이 이 값과 같으면 "그 뒤로 사용자가 고치지
  // 않았다"는 뜻이라, 다른 기기에서 바뀐 값이 스트림으로 오면 편집창도 따라가도 안전하다
  // ([_syncSelectedMemoFromServer] 참고).
  String? _syncedTitle;
  String? _syncedContent;

  void _fillEditor(MemoItem memo) {
    _selectedMemoId = memo.id;
    _memoTitleController.text = memo.title;
    _memoContentController.text = memo.content;
    _syncedTitle = memo.title;
    _syncedContent = memo.content;
  }

  void _clearEditor() {
    _selectedMemoId = null;
    _memoTitleController.clear();
    _memoContentController.clear();
    _syncedTitle = null;
    _syncedContent = null;
  }

  /// 선택된 메모가 다른 기기(또는 다른 탭)에서 바뀌었을 때 편집창을 최신 값으로 맞춘다.
  ///
  /// 예전엔 편집창이 처음 불러올 때와 메모를 고를 때만 채워져서, 탭을 오래 켜두거나 안드로이드
  /// 앱을 백그라운드에서 다시 연 뒤 한 글자만 쳐도 옛 전체 내용이 저장돼 다른 기기에서 고친
  /// 내용이 조용히 사라졌다. 포커스 여부가 아니라 "마지막으로 채운 뒤 사용자가 고쳤는지"로
  /// 판단한다 — 앱을 다시 열면 입력창에 포커스가 남아 있을 수 있어 포커스 기준으로는 정작 이
  /// 경우를 놓친다. 제목/내용은 따로 판단해서, 한쪽을 입력 중이어도 다른 쪽은 따라간다.
  void _syncSelectedMemoFromServer(List<MemoItem> memos) {
    final id = _selectedMemoId;
    if (id == null) return;
    final index = memos.indexWhere((memo) => memo.id == id);
    if (index == -1) return;
    final memo = memos[index];
    final notifier = ref.read(todoMemoProvider.notifier);
    _syncedTitle = _syncField(
      _memoTitleController,
      synced: _syncedTitle,
      server: memo.title,
      hasPendingEdit: notifier.hasPendingTitleFor(id),
    );
    _syncedContent = _syncField(
      _memoContentController,
      synced: _syncedContent,
      server: memo.content,
      hasPendingEdit: notifier.hasPendingContentFor(id),
    );
  }

  /// 편집창 하나를 서버 값에 맞추고, 새로 기억할 "마지막으로 채운 값"을 돌려준다.
  String? _syncField(
    TextEditingController controller, {
    required String? synced,
    required String server,
    required bool hasPendingEdit,
  }) {
    // 이미 같음 — 내 저장이 반영돼 돌아온 경우 등. 기준값만 맞춘다.
    if (controller.text == server) return server;
    // 사용자가 고친 뒤 아직 저장 중/저장 실패로 남은 값이 있거나, 마지막으로 채운 뒤 직접
    // 고쳤으면 입력 중인 글을 덮어쓰지 않는다(동시 편집은 나중 저장이 이기는 알려진 한계).
    // 대기 값을 같이 보는 이유: 쳤다가 지워 원래대로 돌아온 경우 편집창은 기준값과 같지만
    // 디바운스 타이머가 살아 있어, 지금 바꾸면 곧 옛 값이 저장돼 원격 변경을 되덮는다.
    if (hasPendingEdit || controller.text != synced) return synced;
    // .text로 바꾸면 커서가 끝으로 튄다 — 입력창에 포커스가 있을 수 있어 위치를 유지한다.
    final selection = controller.selection;
    int clamp(int offset) => offset.clamp(0, server.length);
    controller.value = TextEditingValue(
      text: server,
      selection: selection.isValid
          ? TextSelection(
              baseOffset: clamp(selection.baseOffset),
              extentOffset: clamp(selection.extentOffset),
            )
          : TextSelection.collapsed(offset: server.length),
    );
    return server;
  }

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
    setState(() => _fillEditor(memo));
  }

  Future<void> _addMemo() async {
    MemoItem? memo;
    final saved = await runTodoWrite(context, () async {
      memo = await ref.read(todoMemoProvider.notifier).addMemo();
    });
    if (!saved || !mounted) return;
    if (memo != null) {
      _selectMemo(memo!.id);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('메모는 최대 $maxMemoCount개까지 만들 수 있습니다.')));
    }
  }

  Future<void> _moveSelectedMemo(int delta) async {
    final id = _selectedMemoId;
    if (id == null) return;
    await runTodoWrite(context, () => ref.read(todoMemoProvider.notifier).moveMemo(id, delta));
  }

  Future<void> _deleteSelectedMemo() async {
    final id = _selectedMemoId;
    if (id == null) return;
    final saved = await runTodoWrite(
      context,
      () => ref.read(todoMemoProvider.notifier).removeMemo(id),
    );
    // 삭제 저장에 실패하면 이미 안내했고 메모도 그대로 남아 있으므로 선택 상태를 건드리지
    // 않는다. 삭제 확인 다이얼로그·네트워크 왕복 중 카드가 사라졌을 수도 있어 mounted도 확인한다.
    if (!saved || !mounted) return;
    final remaining = ref.read(todoMemoProvider).value ?? [];
    if (remaining.isEmpty) {
      setState(_clearEditor);
    } else {
      _selectMemo(remaining.first.id);
    }
  }

  Future<void> _retrySave() async {
    if (_retryingSave) return;
    setState(() => _retryingSave = true);
    final notifier = ref.read(todoMemoProvider.notifier);
    await notifier.flushPending();
    if (!mounted) return;
    setState(() => _retryingSave = false);
    // 계속 실패하면 memoSaveFailureProvider는 이미 실패 상태라 다시 안내하지 않으므로, 사용자가
    // 누른 버튼의 결과는 여기서 직접 알려준다.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            notifier.hasUnsavedEdits ? '아직 저장하지 못했습니다. 네트워크 연결을 확인해주세요.' : '메모를 저장했습니다.',
          ),
        ),
      );
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

    // 디바운스 자동저장은 타이머 콜백에서 실행돼 예외를 화면까지 전달할 수 없어, 실패하면
    // 이 카운터가 올라간다 — 입력한 내용은 화면에 그대로 남아 있고, 이후 메모 전환/로그아웃
    // 때 한 번 더 저장을 시도한다.
    ref.listen(memoSaveFailureProvider, (previous, next) {
      if (next > (previous ?? 0)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('메모를 저장하지 못했습니다. 네트워크 연결을 확인해주세요.')),
          );
      }
    });

    // 로그아웃(uid가 null이 됨)하면 이전 세션의 메모 선택 상태가 다음 로그인 때
    // 잘못 남아있지 않도록 초기화한다.
    ref.listen(authUidProvider, (previous, next) {
      if (next.value == null) {
        _memoInitialized = false;
        _clearEditor();
      }
    });

    return DashboardCard(
      title: '메모',
      icon: Icons.sticky_note_2_outlined,
      accentColor: theme.extension<AppAccentColors>()?.memo,
      child: authState.when(
        loading: () => const LoadingView(),
        // 예전엔 웹의 페이지 새로고침(reloadPage)에 기댔는데, 안드로이드는 이 함수가
        // 빈 구현이라 버튼을 눌러도 아무 반응이 없었다 — authServiceProvider를
        // invalidate하면 인증 스트림 구독 자체를 다시 만들어서 두 플랫폼 모두에서 동작한다.
        error: (error, _) => ErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(authServiceProvider),
        ),
        data: (uid) => uid == null ? const SignedOutPlaceholder() : _buildSignedInContent(),
      ),
    );
  }

  Widget _buildSignedInContent() {
    final memosAsync = ref.watch(todoMemoProvider);

    // 처음 도착한 값은 아래 data 분기의 초기화 블록이 채운다. 여기서는 그 뒤 "바뀐" 값만
    // 반영하면 되므로 ref.listen으로 충분하다(ref.listen이 등록 시점의 값엔 반응하지 않는 건
    // 여기선 문제가 안 됨).
    ref.listen(todoMemoProvider, (previous, next) {
      final memos = next.value;
      if (_memoInitialized && memos != null) _syncSelectedMemoFromServer(memos);
    });

    return memosAsync.when(
      loading: () => const LoadingView(),
      // 같은 이유로 todoMemoProvider만 다시 구독하도록 invalidate한다 — 전체 페이지를
      // 새로고침하지 않아도 되고 안드로이드에서도 동일하게 동작한다.
      error: (error, _) => ErrorView(
        message: describeTodoDataError(error),
        onRetry: () => ref.invalidate(todoMemoProvider),
      ),
      data: (memos) {
        // 메모 목록이 처음 도착했을 때 한 번만 첫 메모를 선택해 채운다(그 이후엔 사용자가
        // 선택/입력 중인 내용을 덮어쓰면 안 되므로). build() 안에서 직접 확인해야
        // 안전하다 — ref.listen은 리스너 등록 시점에 이미 있던 값에는 반응하지 않아서,
        // provider가 이미 데이터를 갖고 있는 상태로 이 State가 새로 생기면(예: 리사이즈로
        // 카드가 재마운트될 때) 영영 초기 선택이 안 채워지는 문제가 있었다.
        if (!_memoInitialized) {
          _memoInitialized = true;
          if (memos.isNotEmpty) _fillEditor(memos.first);
        }
        final hasUnsavedEdits = ref.watch(memoUnsavedEditsProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasUnsavedEdits) ...[
              _UnsavedEditsBanner(retrying: _retryingSave, onRetry: _retrySave),
              const SizedBox(height: 12),
            ],
            MemoSection(
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
            ),
          ],
        );
      },
    );
  }
}

/// 자동저장에 실패한 편집이 남아 있는 동안 계속 보이는 안내. 스낵바는 몇 초 뒤 사라져서, 그걸
/// 놓치고 탭을 닫으면 저장 안 된 내용을 모른 채 잃게 된다.
class _UnsavedEditsBanner extends StatelessWidget {
  const _UnsavedEditsBanner({required this.retrying, required this.onRetry});

  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: colors.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '저장되지 않은 메모 변경 사항이 있습니다.',
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
          TextButton(
            onPressed: retrying ? null : onRetry,
            style: TextButton.styleFrom(foregroundColor: colors.onErrorContainer),
            child: const Text('다시 저장'),
          ),
        ],
      ),
    );
  }
}
