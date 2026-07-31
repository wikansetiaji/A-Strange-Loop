import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:a_strange_loop/providers/chat_state.dart';
import 'package:a_strange_loop/models/session.dart';
import 'package:a_strange_loop/screens/brain_screen.dart';
import 'package:a_strange_loop/widgets/session_tile.dart';
import 'package:a_strange_loop/widgets/animations.dart';
import 'package:a_strange_loop/theme/app_theme.dart';

class Sidebar extends StatefulWidget {
  final double? width;

  const Sidebar({super.key, this.width});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<ChatState>();
    final colorScheme = Theme.of(context).colorScheme;

    final pinnedSessions = cs.sessions.where((s) => s.pinned).toList();
    final unpinnedSessions = cs.sessions.where((s) => !s.pinned).toList();

    return Container(
      width: widget.width ?? 300,
      color: colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          _buildNewChatButton(context, cs),
          _buildSearchField(context, colorScheme, cs),
          _buildBrainButton(context, colorScheme),
          Expanded(child: Builder(builder: (_) {
            if (cs.sessions.isEmpty && cs.isSearching) {
              return _buildEmptySearch(context, colorScheme);
            }
            if (cs.sessions.isEmpty) {
              return _buildEmptyState(context, colorScheme);
            }
            return ListView(
              padding: const EdgeInsets.only(top: 8),
              children: [
                if (pinnedSessions.isNotEmpty) ...[
                  _buildSectionHeader(context, 'PINNED'),
                  ...pinnedSessions
                      .map((s) => _buildSessionTile(cs, s, colorScheme)),
                ],
                if (unpinnedSessions.isNotEmpty) ...[
                  _buildSectionHeader(context, 'RECENT'),
                  ...unpinnedSessions.asMap().entries.map((entry) {
                    return StaggeredEntrance(
                      index: entry.key,
                      child:
                          _buildSessionTile(cs, entry.value, colorScheme),
                    );
                  }),
                ],
              ],
            );
          })),
        ],
      ),
    );
  }

  Widget _buildNewChatButton(BuildContext context, ChatState cs) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => cs.createNewSession(),
          icon: const Icon(Icons.edit_sharp, size: 16),
          label: Text(
            'NEW CHAT',
            style: AppTextStyles.body(context).copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              letterSpacing: 1.0,
              color: colorScheme.onPrimary,
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrainButton(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SizedBox(
        width: double.infinity,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BrainScreen()),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outline, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.psychology_outlined,
                    size: 15,
                    color: colorScheme.onSurface.withAlpha(180)),
                const SizedBox(width: 8),
                Text(
                  'READING BRAIN',
                  style: AppTextStyles.body(context).copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                    color: colorScheme.onSurface.withAlpha(180),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(
      BuildContext context, ColorScheme colorScheme, ChatState cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outline, width: 1),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (q) => cs.searchSessions(q),
          decoration: InputDecoration(
            hintText: 'Search sessions...',
            hintStyle: AppTextStyles.sidebarSubtitle(context).copyWith(
              color: colorScheme.onSurface.withAlpha(80),
              letterSpacing: 0.3,
            ),
            prefixIcon: Icon(Icons.search_sharp,
                size: 16, color: colorScheme.onSurface.withAlpha(100)),
            suffixIcon: cs.isSearching
                ? IconButton(
                    icon: const Icon(Icons.close_sharp, size: 14),
                    onPressed: () {
                      _searchController.clear();
                      cs.clearSearch();
                    },
                  )
                : null,
            filled: false,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            isDense: true,
          ),
          style: AppTextStyles.sidebarSubtitle(context),
        ),
      ),
    );
  }

  Widget _buildSessionTile(
      ChatState cs, Session session, ColorScheme colorScheme) {
    final isActive = session.id == cs.currentSessionId;
    return SessionTile(
      session: session,
      isActive: isActive,
      onTap: () => cs.switchSession(session.id),
      onPin: () => cs.pinSession(session.id),
      onDelete: () => _confirmDelete(context, cs, session),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Row(
        children: [
          Container(width: 8, height: 1, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTextStyles.sectionLabel(context).copyWith(
              color: colorScheme.onSurface.withAlpha(80),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline_sharp,
                size: 28, color: colorScheme.onSurface.withAlpha(50)),
            const SizedBox(height: 12),
            Text(
              'No conversations yet.\nStart a new chat!',
              textAlign: TextAlign.center,
              style: AppTextStyles.sidebarSubtitle(context).copyWith(
                color: colorScheme.onSurface.withAlpha(100),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySearch(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_sharp,
                size: 28, color: colorScheme.onSurface.withAlpha(50)),
            const SizedBox(height: 12),
            Text(
              'No sessions found.',
              textAlign: TextAlign.center,
              style: AppTextStyles.sidebarSubtitle(context).copyWith(
                color: colorScheme.onSurface.withAlpha(100),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, ChatState cs, Session session) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
        title: Text(
          'Delete conversation?',
          style: AppTextStyles.display(context).copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        content: Text(
          'This will permanently delete "${session.displayTitle}" '
          'and all its messages.',
          style: AppTextStyles.body(context).copyWith(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              cs.deleteSession(session.id);
            },
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
