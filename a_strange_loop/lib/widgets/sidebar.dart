import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:a_strange_loop/providers/chat_state.dart';
import 'package:a_strange_loop/models/session.dart';
import 'package:a_strange_loop/widgets/session_tile.dart';

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

    final pinnedSessions =
        cs.sessions.where((s) => s.pinned).toList();
    final unpinnedSessions =
        cs.sessions.where((s) => !s.pinned).toList();

    return Container(
      width: widget.width ?? 300,
      color: colorScheme.surfaceContainerLow,
      child: Column(
        children: [
           Padding(
             padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
             child: SizedBox(
               width: double.infinity,
               child: Text('A Strange Loop',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface)),
             ),
           ),
          _buildNewChatButton(context, cs),
          _buildSearchField(context, colorScheme, cs),
          _buildBrainButton(context, colorScheme, cs),
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
                  _buildSectionHeader(context, 'Pinned'),
                  ...pinnedSessions.map(
                      (s) => _buildSessionTile(cs, s, colorScheme)),
                ],
                if (unpinnedSessions.isNotEmpty) ...[
                  _buildSectionHeader(context, 'Recent'),
                  ...unpinnedSessions.map(
                      (s) => _buildSessionTile(cs, s, colorScheme)),
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => cs.createNewSession(),
          icon: const Icon(Icons.edit_square, size: 18),
          label: const Text('New Chat'),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildBrainButton(
      BuildContext context, ColorScheme colorScheme, ChatState cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _showBrain(context, cs),
          icon: const Icon(Icons.psychology, size: 16),
          label: const Text('Reading Brain'),
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.secondary,
            side: BorderSide(color: colorScheme.outline.withAlpha(80)),
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  void _showBrain(BuildContext ctx, ChatState cs) {
    final brain = cs.brainContent;
    showDialog(
      context: ctx,
      builder: (dCtx) {
        if (brain != null) {
          return _buildBrainDialog(dCtx, brain);
        }
        return FutureBuilder<String>(
          future: cs.loadBrain(),
          builder: (_, snapshot) {
            if (snapshot.hasData) {
              return _buildBrainDialog(dCtx, snapshot.data!);
            }
            return const Dialog(
              child: SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBrainDialog(BuildContext ctx, String brain) {
    final colorScheme = Theme.of(ctx).colorScheme;
    return Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                child: Row(
                  children: [
                    const Icon(Icons.psychology, size: 18),
                    const SizedBox(width: 8),
                    const Text('Reading Brain',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        )),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: MarkdownBody(
                    data: brain,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(fontSize: 14, height: 1.6),
                      h1: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface),
                      h2: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface),
                      h3: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface),
                      blockquoteDecoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: colorScheme.primary.withAlpha(80),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildSearchField(
      BuildContext context, ColorScheme colorScheme, ChatState cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        controller: _searchController,
        onChanged: (q) => cs.searchSessions(q),
        decoration: InputDecoration(
          hintText: 'Search sessions...',
          hintStyle: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurface.withAlpha(100),
          ),
          prefixIcon: Icon(Icons.search,
              size: 18, color: colorScheme.onSurface.withAlpha(120)),
          suffixIcon: cs.isSearching
              ? IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    _searchController.clear();
                    cs.clearSearch();
                  },
                )
              : null,
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          isDense: true,
        ),
        style: const TextStyle(fontSize: 13),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: colorScheme.onSurface.withAlpha(100),
        ),
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
            Icon(Icons.chat_bubble_outline,
                size: 40, color: colorScheme.onSurface.withAlpha(80)),
            const SizedBox(height: 12),
            Text(
              'No conversations yet.\nStart a new chat!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withAlpha(120),
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
            Icon(Icons.search_off,
                size: 40, color: colorScheme.onSurface.withAlpha(80)),
            const SizedBox(height: 12),
            Text(
              'No sessions found.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withAlpha(120),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, ChatState cs, Session session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text(
          'This will permanently delete "${session.displayTitle}" '
          'and all its messages.',
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
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
