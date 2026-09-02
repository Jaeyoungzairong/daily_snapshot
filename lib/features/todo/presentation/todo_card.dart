import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_reload.dart';
import '../../../core/utils/web_url.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../../core/widgets/loading_error_view.dart';
import '../application/todo_provider.dart';
import '../data/memo_item.dart';
import '../data/todo_item.dart';

/// 실수 방지용 확인 다이얼로그. 사용자가 [confirmLabel] 버튼을 눌렀을 때만 true를 반환한다.
Future<bool> _confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '삭제',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(confirmLabel)),
      ],
    ),
  );
  return confirmed ?? false;
}

class TodoCard extends ConsumerStatefulWidget {
  const TodoCard({super.key});

  @override
  ConsumerState<TodoCard> createState() => _TodoCardState();
}

class _TodoCardState extends ConsumerState<TodoCard> {
  final TextEditingController _newItemController = TextEditingController();
  final TextEditingController _memoTitleController = TextEditingController();
  final TextEditingController _memoContentController = TextEditingController();
  Timer? _memoTitleDebounce;
  Timer? _memoContentDebounce;
  bool _memoInitialized = false;
  String? _selectedMemoId;
  bool _signingOut = false;

  @override
  void dispose() {
    _memoTitleDebounce?.cancel();
    _memoContentDebounce?.cancel();
    _newItemController.dispose();
    _memoTitleController.dispose();
    _memoContentController.dispose();
    super.dispose();
  }

  Future<void> _addItem() async {
    final text = _newItemController.text;
    if (text.trim().isEmpty) return;
    final added = await ref.read(todoListProvider.notifier).add(text);
    if (!mounted) return;
    if (added) {
      _newItemController.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('할 일은 최대 $maxTodoItems개까지 추가할 수 있습니다. 완료된 항목을 정리해주세요.')),
      );
    }
  }

  void _selectMemo(String id) {
    _memoTitleDebounce?.cancel();
    _memoContentDebounce?.cancel();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('메모는 최대 $maxMemoCount개까지 만들 수 있습니다.')),
      );
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
    _memoTitleDebounce?.cancel();
    _memoTitleDebounce = Timer(const Duration(milliseconds: 500), () {
      ref.read(todoMemoProvider.notifier).renameMemo(id, value);
    });
  }

  void _onMemoContentChanged(String value) {
    final id = _selectedMemoId;
    if (id == null) return;
    _memoContentDebounce?.cancel();
    _memoContentDebounce = Timer(const Duration(milliseconds: 500), () {
      ref.read(todoMemoProvider.notifier).updateContent(id, value);
    });
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    final confirmed = await _confirmAction(
      context,
      title: '로그아웃',
      message: '로그아웃하시겠습니까?',
      confirmLabel: '로그아웃',
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _signingOut = true);

    // 저장 타이머가 아직 안 돌았다면(로그아웃 직전에 입력한 경우), 로그인 상태가
    // 사라지기 전에 지금 즉시 저장해서 마지막 편집 내용이 유실되지 않게 한다.
    final id = _selectedMemoId;
    if (id != null) {
      if (_memoTitleDebounce?.isActive ?? false) {
        _memoTitleDebounce!.cancel();
        try {
          await ref.read(todoMemoProvider.notifier).renameMemo(id, _memoTitleController.text);
        } catch (_) {
          // 최선을 다한 저장 시도일 뿐이라, 실패해도 로그아웃은 계속 진행한다.
        }
      }
      if (_memoContentDebounce?.isActive ?? false) {
        _memoContentDebounce!.cancel();
        try {
          await ref.read(todoMemoProvider.notifier).updateContent(id, _memoContentController.text);
        } catch (_) {}
      }
    }

    if (!mounted) return;
    try {
      await ref.read(authServiceProvider).signOut();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('로그아웃에 실패했습니다. 다시 시도해주세요.')));
    }

    if (mounted) setState(() => _signingOut = false);
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
        _newItemController.clear();
        _memoTitleController.clear();
        _memoContentController.clear();
      }
    });

    return DashboardCard(
      title: '할 일',
      icon: Icons.checklist,
      accentColor: theme.extension<AppAccentColors>()?.todo,
      trailing: authState.value == null
          ? null
          : IconButton(
              onPressed: _signingOut ? null : _signOut,
              icon: const Icon(Icons.logout, size: 20),
              tooltip: '로그아웃',
              visualDensity: VisualDensity.compact,
            ),
      child: authState.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(message: error.toString(), onRetry: reloadPage),
        data: (uid) => uid == null ? const _SignInPrompt() : _buildSignedInContent(theme),
      ),
    );
  }

  Widget _buildSignedInContent(ThemeData theme) {
    final itemsAsync = ref.watch(todoListProvider);
    final memosAsync = ref.watch(todoMemoProvider);

    // 메모 목록은 비동기로 로드되므로, 처음 도착했을 때 한 번만 첫 메모를 선택해 채운다
    // (그 이후엔 사용자가 선택/입력 중인 내용을 덮어쓰면 안 되므로).
    ref.listen(todoMemoProvider, (previous, next) {
      final memos = next.value;
      if (!_memoInitialized && memos != null) {
        _memoInitialized = true;
        if (memos.isNotEmpty) {
          _selectedMemoId = memos.first.id;
          _memoTitleController.text = memos.first.title;
          _memoContentController.text = memos.first.content;
        }
      }
    });

    return itemsAsync.when(
      loading: () => const LoadingView(),
      error: (error, _) => ErrorView(
        message: _describeDataError(error),
        onRetry: reloadPage,
      ),
      data: (items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newItemController,
                  decoration: const InputDecoration(
                    labelText: '할 일 추가',
                    //hintText: '예: 3시 팀 미팅 자료 준비',
                  ),
                  onSubmitted: (_) => _addItem(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _addItem,
                icon: const Icon(Icons.add),
                tooltip: '할 일 추가',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TodoList(items: items),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text('메모', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          memosAsync.when(
            loading: () => const LoadingView(),
            error: (error, _) => ErrorView(
              message: _describeDataError(error),
              onRetry: reloadPage,
            ),
            data: (memos) => _MemoSection(
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
          ),
        ],
      ),
    );
  }
}

/// 로그인 링크 처리 중 발생한 예외를 사용자에게 보여줄 한국어 메시지로 바꾼다.
String _describeAuthError(Object error) {
  if (error is NotApprovedException) {
    return '관리자 승인이 필요한 이메일입니다. 관리자에게 계정 추가를 요청해주세요.';
  }
  if (error is PendingEmailNotFoundException) {
    return '로그인을 요청했던 기기(브라우저)에서 다시 열어주세요.';
  }
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-action-code':
        return '유효하지 않거나 이미 사용된 링크입니다. 입력한 이메일이 맞는지 확인하거나, 새 로그인 링크를 다시 요청해주세요.';
      case 'expired-action-code':
        return '로그인 링크가 만료되었습니다. 새 로그인 링크를 다시 요청해주세요.';
      case 'invalid-email':
        return '이메일 형식을 다시 확인해주세요.';
    }
  }
  return '로그인 처리 중 문제가 발생했습니다: $error';
}

/// 할일/메모 Firestore 스트림에서 발생한 에러를 사용자에게 보여줄 한국어 메시지로 바꾼다.
String _describeDataError(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return '승인이 해제되었습니다. 관리자에게 문의해주세요.';
      case 'unavailable':
        return '네트워크 연결을 확인해주세요.';
    }
  }
  return '일시적인 오류가 발생했습니다. 다시 시도해주세요.';
}

class _SignInPrompt extends ConsumerStatefulWidget {
  const _SignInPrompt();

  @override
  ConsumerState<_SignInPrompt> createState() => _SignInPromptState();
}

class _SignInPromptState extends ConsumerState<_SignInPrompt> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _manualEmailController = TextEditingController();
  bool _sending = false;
  bool _linkSent = false;
  String? _errorMessage;

  // 이메일 링크로 돌아온 경우를 위한 상태. isSignInWithEmailLink()/저장된 이메일 조회는
  // 로컬 확인일 뿐 Firebase 서버 호출이 아니므로 자동으로 미리 보여줘도 안전하다.
  // 실제 로그인(signInWithEmailLink, 서버 호출)은 사용자가 "로그인 계속하기"를 직접
  // 눌러야만 실행된다 — 그래야 메일 보안 스캐너가 링크를 미리 열어봐도 1회용 로그인
  // 코드가 그 자리에서 소모되지 않는다.
  bool _checkingLink = true;
  bool _isLinkMode = false;
  bool _confirming = false;
  String? _pendingEmail;

  @override
  void initState() {
    super.initState();
    _checkForSignInLink();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _manualEmailController.dispose();
    super.dispose();
  }

  Future<void> _checkForSignInLink() async {
    final authService = ref.read(authServiceProvider);
    final link = Uri.base.toString();
    if (!authService.isSignInLink(link)) {
      setState(() => _checkingLink = false);
      return;
    }
    final email = await authService.peekPendingEmail();
    if (!mounted) return;
    setState(() {
      _checkingLink = false;
      _isLinkMode = true;
      _pendingEmail = email;
    });
  }

  // 이 브라우저에 저장된 이메일이 없으면(다른 기기에서 링크를 열었거나, 관리자가
  // 발송 한도를 우회하려고 직접 생성한 링크를 열었을 때) 사용자가 입력한 이메일을 쓴다.
  Future<void> _confirmSignIn() async {
    if (_confirming) return;
    String? manualEmail;
    if (_pendingEmail == null) {
      manualEmail = _manualEmailController.text.trim();
      if (manualEmail.isEmpty) return;
    }
    setState(() {
      _confirming = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .completeSignInIfLink(Uri.base.toString(), emailOverride: manualEmail);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLinkMode = false;
        _errorMessage = _describeAuthError(error);
      });
    } finally {
      clearSignInLinkFromUrl();
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _sendLink() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authServiceProvider).sendSignInLink(email);
      if (!mounted) return;
      setState(() => _linkSent = true);
    } on NotApprovedException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _describeAuthError(error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = '로그인 링크 발송에 실패했습니다. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_checkingLink) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: LoadingView());
    }

    if (_isLinkMode) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(
              _pendingEmail != null
                  ? '$_pendingEmail 계정으로 로그인하시겠습니까?'
                  : '이 브라우저에서 로그인 요청 정보를 찾을 수 없습니다.\n로그인 링크를 요청했던 이메일을 입력해주세요.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (_pendingEmail == null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _manualEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: '이메일'),
                onSubmitted: (_) => _confirmSignIn(),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _confirming ? null : _confirmSignIn,
              child: _confirming
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('로그인 계속하기'),
            ),
          ],
        ),
      );
    }

    if (_linkSent) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '입력하신 이메일로 로그인 링크를 보냈습니다.\n메일함에서 링크를 확인해주세요.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Text(
            '할 일/메모는 승인된 이메일로 로그인 후 이용할 수 있습니다.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: '이메일'),
            onSubmitted: (_) => _sendLink(),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: _sending ? null : _sendLink,
            child: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('로그인 링크 받기'),
          ),
        ],
      ),
    );
  }
}

class _MemoSection extends StatelessWidget {
  const _MemoSection({
    required this.memos,
    required this.selectedMemoId,
    required this.titleController,
    required this.contentController,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
    required this.onMove,
    required this.onTitleChanged,
    required this.onContentChanged,
  });

  final List<MemoItem> memos;
  final String? selectedMemoId;
  final TextEditingController titleController;
  final TextEditingController contentController;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final VoidCallback onDelete;
  final ValueChanged<int> onMove;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onContentChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedIndex = memos.indexWhere((memo) => memo.id == selectedMemoId);
    final hasSelection = selectedIndex != -1;

    final captionStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);

    String? timelineLabel;
    if (hasSelection) {
      final createdText = Formatters.dateTime(memos[selectedIndex].createdAt);
      final updatedText = Formatters.dateTime(memos[selectedIndex].updatedAt);
      // 만든 뒤 한 번도 안 고쳤으면 생성 시각 하나만, 고쳤으면 화살표로 이어서 한 줄에.
      timelineLabel = createdText == updatedText ? '생성 $createdText' : '생성 $createdText → 수정 $updatedText';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MemoChipWrap(memos: memos, selectedMemoId: selectedMemoId, onSelect: onSelect, onAdd: onAdd),
        const SizedBox(height: 16),
        if (hasSelection) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: titleController,
                  style: theme.textTheme.titleSmall,
                  decoration: const InputDecoration(labelText: '제목', isDense: true),
                  onChanged: onTitleChanged,
                ),
              ),
              IconButton(
                onPressed: selectedIndex > 0 ? () => onMove(-1) : null,
                icon: const Icon(Icons.chevron_left, size: 18),
                tooltip: '왼쪽으로 이동',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: selectedIndex < memos.length - 1 ? () => onMove(1) : null,
                icon: const Icon(Icons.chevron_right, size: 18),
                tooltip: '오른쪽으로 이동',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: () async {
                  final confirmed = await _confirmAction(
                    context,
                    title: '메모 삭제',
                    message: '이 메모를 삭제할까요? 삭제한 내용은 복구할 수 없습니다.',
                  );
                  if (confirmed) onDelete();
                },
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: '메모 삭제',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(timelineLabel!, style: captionStyle),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: contentController,
            maxLines: 20,
            maxLength: maxMemoContentLength,
            onChanged: onContentChanged,
          ),
        ] else
          Text(
            '메모가 없습니다. + 버튼을 눌러 추가해보세요.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
      ],
    );
  }
}

class _MemoChipWrap extends StatelessWidget {
  const _MemoChipWrap({
    required this.memos,
    required this.selectedMemoId,
    required this.onSelect,
    required this.onAdd,
  });

  final List<MemoItem> memos;
  final String? selectedMemoId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.extension<AppAccentColors>()?.todo ?? theme.colorScheme.primary;
    final onAccent = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : Colors.black87;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 카드 폭에 맞춰 칩 하나의 최대 너비를 조절한다: 데스크톱 그리드(폭 넓음)에서는
        // 제목이 덜 잘리도록 더 길게, 모바일 컬럼(폭 좁음)에서는 한 줄에 과하게 크지
        // 않도록 줄인다.
        final chipMaxWidth = (constraints.maxWidth / 2).clamp(120.0, 260.0);
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final memo in memos)
              _MemoChip(
                memo: memo,
                maxWidth: chipMaxWidth,
                selected: memo.id == selectedMemoId,
                accent: accent,
                onAccent: onAccent,
                onSelected: () => onSelect(memo.id),
              ),
            IconButton(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              tooltip: '새 메모 추가',
              style: IconButton.styleFrom(
                backgroundColor: accent.withValues(alpha: 0.12),
                foregroundColor: accent,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MemoChip extends StatelessWidget {
  const _MemoChip({
    required this.memo,
    required this.maxWidth,
    required this.selected,
    required this.accent,
    required this.onAccent,
    required this.onSelected,
  });

  final MemoItem memo;
  final double maxWidth;
  final bool selected;
  final Color accent;
  final Color onAccent;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = selected ? onAccent : theme.colorScheme.onSurface;
    final isEmpty = memo.content.trim().isEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: ChoiceChip(
        avatar: Icon(Icons.sticky_note_2_outlined, size: 16, color: labelColor),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                memo.title.trim().isEmpty ? '(제목 없음)' : memo.title,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 아직 내용을 안 쓴 메모라는 걸 눈에 띄게 표시한다.
            if (isEmpty) ...[
              const SizedBox(width: 6),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: labelColor.withValues(alpha: 0.6), shape: BoxShape.circle),
              ),
            ],
          ],
        ),
        labelStyle: TextStyle(color: labelColor, fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        selected: selected,
        selectedColor: accent,
        backgroundColor: Colors.transparent,
        side: BorderSide(color: accent.withValues(alpha: selected ? 1 : 0.4)),
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _TodoList extends ConsumerWidget {
  const _TodoList({required this.items});

  final List<TodoItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (items.isEmpty) {
      return Text(
        '오늘 할 일을 추가해보세요.',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
      );
    }

    final sorted = sortedForDisplay(items);
    final hasCompleted = sorted.any((item) => item.done);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final item in sorted)
                  _TodoRow(
                    item: item,
                    onToggle: () => ref.read(todoListProvider.notifier).toggle(item.id),
                    onDelete: () => ref.read(todoListProvider.notifier).remove(item.id),
                  ),
              ],
            ),
          ),
        ),
        if (hasCompleted)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () async {
                final confirmed = await _confirmAction(
                  context,
                  title: '완료 항목 지우기',
                  message: '완료된 항목을 모두 지울까요?',
                );
                if (confirmed) ref.read(todoListProvider.notifier).clearCompleted();
              },
              child: const Text('완료 항목 지우기'),
            ),
          ),
      ],
    );
  }
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({required this.item, required this.onToggle, required this.onDelete});

  final TodoItem item;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Checkbox(value: item.done, onChanged: (_) => onToggle()),
        Expanded(
          child: Text(
            item.text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: item.done ? theme.colorScheme.outline : null,
              decoration: item.done ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        IconButton(
          onPressed: () async {
            final confirmed = await _confirmAction(
              context,
              title: '할 일 삭제',
              message: '"${item.text}" 항목을 삭제할까요?',
            );
            if (confirmed) onDelete();
          },
          icon: const Icon(Icons.delete_outline, size: 18),
          tooltip: '삭제',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}
