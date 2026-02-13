import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../auth/presentation/auth_provider.dart';
import '../../transcription/presentation/transcription_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(historyProvider.notifier).loadHistory());
  }

  void _showUserMenu() {
    final authState = ref.read(authProvider);
    final isGuest = ref.read(guestModeProvider);

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 用戶頭像
              CircleAvatar(
                radius: 32,
                child: Text(
                  authState.isAuthenticated
                      ? (authState.displayName?.isNotEmpty == true
                          ? authState.displayName![0].toUpperCase()
                          : authState.email?[0].toUpperCase() ?? '?')
                      : '訪',
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                authState.isAuthenticated
                    ? (authState.displayName ?? authState.email ?? '使用者')
                    : '訪客模式',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (authState.email != null)
                Text(
                  authState.email!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const Divider(height: 24),

              // 訂閱狀態
              if (authState.isAuthenticated)
                ListTile(
                  leading: Icon(
                    authState.isPro ? Icons.star : Icons.star_border,
                    color: authState.isPro ? Colors.amber : null,
                  ),
                  title: Text(authState.isPro ? 'Pro 會員' : '免費方案'),
                  subtitle: Text(
                    '本月已轉譜 ${authState.monthlyConversionsUsed} 次',
                  ),
                  trailing: authState.isPro
                      ? null
                      : TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            context.push('/paywall');
                          },
                          child: const Text('升級'),
                        ),
                ),

              // 登入/登出
              if (authState.isAuthenticated)
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('登出'),
                  onTap: () {
                    Navigator.pop(context);
                    ref.read(authProvider.notifier).signOut();
                  },
                )
              else if (isGuest)
                ListTile(
                  leading: const Icon(Icons.login),
                  title: const Text('登入帳號'),
                  subtitle: const Text('登入後可同步轉譜記錄'),
                  onTap: () {
                    Navigator.pop(context);
                    ref.read(guestModeProvider.notifier).state = false;
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_selectedIds.length == 1 ? '刪除轉譜' : '刪除轉譜'),
        content: Text(
          _selectedIds.length == 1
              ? '確定要刪除此轉譜記錄嗎？相關檔案也會一併刪除。'
              : '確定要刪除選中的 ${_selectedIds.length} 項轉譜記錄嗎？相關檔案也會一併刪除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteSelected();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
  }

  void _showClearAllDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除所有歷史'),
        content: const Text('確定要清除所有轉譜歷史記錄嗎？此操作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _clearAllHistory();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('清除全部'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSelected() async {
    final notifier = ref.read(historyProvider.notifier);
    await notifier.deleteSelectedTranscriptions(_selectedIds.toList());
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已刪除選中的轉譜')),
      );
    }
  }

  Future<void> _clearAllHistory() async {
    final notifier = ref.read(historyProvider.notifier);
    await notifier.deleteAllTranscriptions();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清除所有轉譜歷史')),
      );
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedIds.clear();
      }
    });
  }

  void _toggleItemSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    final history = ref.read(historyProvider);
    setState(() {
      if (_selectedIds.length == history.items.length) {
        _selectedIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedIds.clear();
        _selectedIds.addAll(history.items.map((e) => e.id));
        _isSelectionMode = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);
    final historyNotifier = ref.read(historyProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
            ? Text('已選擇 ${_selectedIds.length} 項')
            : const Text('NoteFlow'),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectionMode,
              )
            : null,
        actions: [
          if (_isSelectionMode) ...[
            // 選擇模式：全選 + 刪除
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: _selectAll,
              tooltip: '全選/取消全選',
            ),
            if (_selectedIds.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: _showDeleteDialog,
                tooltip: '刪除',
              ),
          ] else ...[
            // 一般模式：管理 + 用戶選單
            if (history.items.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.checklist),
                onPressed: _toggleSelectionMode,
                tooltip: '管理',
              ),
            IconButton(
              icon: CircleAvatar(
                radius: 14,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  authState.isAuthenticated
                      ? (authState.displayName?.isNotEmpty == true
                          ? authState.displayName![0].toUpperCase()
                          : '?')
                      : '訪',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              onPressed: _showUserMenu,
            ),
          ],
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顯示正在處理的轉譜（如果有）
            if (history.items.any((item) => item.isProcessing))
              Card(
                color: theme.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.hourglass_top,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '轉譜處理中',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...history.items
                          .where((item) => item.isProcessing)
                          .map((item) => Padding(
                                padding: const EdgeInsets.only(left: 24, bottom: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: theme.colorScheme.onPrimaryContainer,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${item.progress}%',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.music_note,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '將音樂轉為鋼琴樂譜',
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '上傳音樂檔案或即時錄音',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => context.push('/transcribe'),
                      icon: const Icon(Icons.add),
                      label: const Text('開始轉譜'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('轉換歷史', style: theme.textTheme.titleMedium),
                if (history.items.isNotEmpty && !_isSelectionMode)
                  TextButton.icon(
                    onPressed: () => _showClearAllDialog(),
                    icon: const Icon(Icons.delete_sweep, size: 16),
                    label: const Text('清除全部'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: history.items.isEmpty
                  ? _EmptyHistory()
                  : _HistoryList(
                      // 處理中的項目排在最前面
                      items: [...history.items]
                        ..sort((a, b) {
                          // 先按狀態排序（處理中在前）
                          if (a.isProcessing && !b.isProcessing) return -1;
                          if (!a.isProcessing && b.isProcessing) return 1;
                          // 再按時間排序（新的在前）
                          return b.createdAt.compareTo(a.createdAt);
                        }),
                      isSelectionMode: _isSelectionMode,
                      selectedIds: _selectedIds,
                      onToggleSelection: _toggleItemSelection,
                      onRefresh: () => historyNotifier.loadHistory(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}


class _EmptyHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_music_outlined,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 8),
          Text(
            '尚無轉換記錄',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  final List items;
  final bool isSelectionMode;
  final Set<String> selectedIds;
  final Function(String) onToggleSelection;
  final VoidCallback onRefresh;

  const _HistoryList({
    required this.items,
    required this.isSelectionMode,
    required this.selectedIds,
    required this.onToggleSelection,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _HistoryCard(
          item: item,
          isSelectionMode: isSelectionMode,
          isSelected: selectedIds.contains(item.id),
          onToggleSelection: () => onToggleSelection(item.id),
          onRefresh: onRefresh,
        );
      },
    );
  }
}

class _HistoryCard extends ConsumerWidget {
  final item;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onToggleSelection;
  final VoidCallback onRefresh;

  const _HistoryCard({
    required this.item,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onToggleSelection,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // 根據狀態顯示不同圖標和顏色
    IconData leadingIcon;
    Color leadingColor;
    String statusText;

    if (item.isCompleted) {
      leadingIcon = Icons.music_note;
      leadingColor = theme.colorScheme.primary;
      statusText = '已完成';
    } else if (item.isProcessing) {
      leadingIcon = Icons.hourglass_top;
      leadingColor = theme.colorScheme.tertiary;
      statusText = '處理中';
    } else if (item.isFailed) {
      leadingIcon = Icons.error_outline;
      leadingColor = theme.colorScheme.error;
      statusText = '失敗';
    } else {
      leadingIcon = Icons.pending;
      leadingColor = theme.colorScheme.outline;
      statusText = '待處理';
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      color: isSelected ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
      child: InkWell(
        onTap: isSelectionMode
            ? onToggleSelection
            : () {
                if (item.isCompleted || item.isProcessing) {
                  context.push('/sheet/${item.id}');
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('轉譜失敗，請重新嘗試'),
                      backgroundColor: theme.colorScheme.error,
                    ),
                  );
                }
              },
        onLongPress: onToggleSelection,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 選擇模式下的複選框
              if (isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outline,
                  ),
                ),
              // 狀態圖標
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: leadingColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(leadingIcon, color: leadingColor),
              ),
              const SizedBox(width: 12),
              // 標題和狀態
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // 狀態文字
                    Text(
                      item.isProcessing
                          ? '${item.progressMessage ?? "處理中"} (${item.progress}%)'
                          : statusText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: leadingColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // 處理中顯示進度條
                    if (item.isProcessing) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: item.progress / 100,
                          minHeight: 3,
                          backgroundColor: leadingColor.withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(leadingColor),
                        ),
                      ),
                    ],
                    // 日期
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(item.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              // 處理中顯示刷新按鈕
              if (item.isProcessing && !isSelectionMode)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: onRefresh,
                  tooltip: '檢查進度',
                )
              else if (!isSelectionMode)
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
