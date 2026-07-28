import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:a_strange_loop/providers/chat_state.dart';
import 'package:a_strange_loop/widgets/sidebar.dart';
import 'package:a_strange_loop/widgets/animations.dart';
import 'package:a_strange_loop/theme/app_theme.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _initialized = false;
  MarkdownStyleSheet? _markdownStyleSheet;
  bool _scrollRequested = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final cs = context.read<ChatState>();
    try {
      await cs.initializeSessions();
    } catch (_) {
      try {
        await cs.fallbackToEmptySession();
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatState>().sendMessage(text);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Center(
          child: BlockLoader(color: Theme.of(context).colorScheme.primary),
        ),
      );
    }

    final isWide = MediaQuery.of(context).size.width >= 840;

    return Scaffold(
      key: _scaffoldKey,
      appBar: _buildHeader(isWide),
      drawer: isWide ? null : const Sidebar(),
      body: isWide
          ? Row(
              children: [
                const Sidebar(width: 300),
                Container(
                    width: 1, color: Theme.of(context).colorScheme.outline),
                Expanded(child: _buildChatArea()),
              ],
            )
          : _buildChatArea(),
    );
  }

  PreferredSizeWidget _buildHeader(bool isWide) {
    final cs = Theme.of(context).colorScheme;

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: cs.surface,
      leading: isWide
          ? null
          : IconButton(
              icon: const Icon(Icons.menu_sharp, size: 20),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
      title: Consumer<ChatState>(
        builder: (context, state, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PulsingLoop(size: 18, color: cs.primary),
              const SizedBox(width: 10),
              Text(
                'A STRANGE LOOP',
                style: AppTextStyles.display(context).copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              if (state.currentBookTitle != null) ...[
                const SizedBox(width: 12),
                Container(width: 1, height: 14, color: cs.outline),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    '${state.currentBookTitle}'
                    '${state.currentBookProgress != null ? ' \u00b7 ${state.currentBookProgress}' : ''}',
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.chatCaption(context).copyWith(
                      color: cs.onSurface.withAlpha(120),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
      centerTitle: false,
      titleSpacing: isWide ? 20 : 0,
      actions: [
        if (!isWide)
          IconButton(
            icon: Icon(Icons.edit_sharp, size: 18, color: cs.primary),
            tooltip: 'New Chat',
            onPressed: () {
              _scaffoldKey.currentState?.closeDrawer();
              context.read<ChatState>().createNewSession();
            },
          ),
        IconButton(
          icon: Icon(Icons.logout_sharp, size: 18,
              color: cs.onSurface.withAlpha(120)),
          tooltip: 'Sign out',
          onPressed: () => FirebaseAuth.instance.signOut(),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: cs.outline),
      ),
    );
  }

  Widget _buildChatArea() {
    return FloatingDust(
      particleCount: 12,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 768),
          child: Column(
            children: [
              Expanded(child: _buildMessageList()),
              _buildErrorBanner(),
              _buildTokenFooter(),
              Container(
                  height: 1, color: Theme.of(context).colorScheme.outline),
              _buildInputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    return Consumer<ChatState>(
      builder: (context, state, _) {
        if (state.messages.isEmpty && state.streamingContent == null) {
          return _buildEmptyState();
        }
        if (!_scrollRequested) {
          _scrollRequested = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom();
            _scrollRequested = false;
          });
        }
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          itemCount: state.messages.length +
              (state.streamingContent != null ? 1 : 0),
          itemBuilder: (context, index) {
            if (state.streamingContent != null &&
                index == state.messages.length) {
              if (state.streamingContent!.isEmpty) {
                return TypingBubble(
                  color: Theme.of(context).colorScheme.primary,
                );
              }
              return _buildAssistantText(state.streamingContent!);
            }
            return _buildMessage(state.messages[index]);
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PulsingLoop(size: 48, color: cs.primary),
            const SizedBox(height: 28),
            Container(width: 32, height: 2, color: cs.primary),
            const SizedBox(height: 20),
            Text(
              "I'm A Strange Loop. I am your reading brain.\nAsk me anything — what to read next, how your taste has evolved, or just talk about books.",
              textAlign: TextAlign.center,
              style: AppTextStyles.chatBody(context).copyWith(
                color: cs.onSurface.withAlpha(160),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(dynamic msg) {
    final isUser = msg.role == 'user';
    if (isUser) {
      return _buildUserBubble(msg.content);
    }
    return _buildAssistantText(msg.content);
  }

  Widget _buildUserBubble(String content) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outline, width: 1),
        ),
        child: Text(
          content,
          style: AppTextStyles.chatBody(context),
        ),
      ),
    );
  }

  Widget _buildAssistantText(String content) {
    final cs = Theme.of(context).colorScheme;
    _markdownStyleSheet ??= MarkdownStyleSheet(
      p: AppTextStyles.chatBody(context),
      h1: AppTextStyles.display(context).copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: cs.onSurface,
        letterSpacing: 0.5,
      ),
      h2: AppTextStyles.display(context).copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
      ),
      h3: AppTextStyles.display(context).copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: cs.secondary, width: 2),
        ),
      ),
      codeblockDecoration: BoxDecoration(
        border: Border.all(color: cs.outline, width: 1),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: cs.primary, width: 3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 14, top: 4, bottom: 4, right: 8),
          child: MarkdownBody(
            data: content,
            selectable: true,
            styleSheet: _markdownStyleSheet,
          ),
        ),
      ),
    );
  }

  Widget _buildTokenFooter() {
    return Consumer<ChatState>(
      builder: (context, state, _) {
        if (state.messages.isEmpty) return const SizedBox.shrink();

        final suffix = state.isSummaryActive ? ' (summarized)' : '';

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(
            '${state.messages.length} messages$suffix \u00b7 ${state.formattedSessionTokens}',
            textAlign: TextAlign.center,
            style: AppTextStyles.chatCaption(context).copyWith(
              color: Theme.of(context).colorScheme.onSurface.withAlpha(70),
              letterSpacing: 0.5,
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorBanner() {
    return Consumer<ChatState>(
      builder: (context, state, _) {
        if (state.error == null) return const SizedBox.shrink();
        return MaterialBanner(
          content: Text(state.error!, style: const TextStyle(fontSize: 12)),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          actions: [
            TextButton(
              onPressed: () => state.clearError(),
              child: const Text('Dismiss'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInputBar() {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): _sendMessage,
              },
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outline, width: 1.5),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: AppTextStyles.chatBody(context),
                  decoration: InputDecoration(
                    hintText: 'Ask me anything, friend...',
                    hintStyle: AppTextStyles.inputHint(context).copyWith(
                      fontSize: 14,
                      letterSpacing: 0.2,
                    ),
                    border: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  textInputAction: TextInputAction.newline,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Consumer<ChatState>(
            builder: (context, state, _) {
              return MorphingSendButton(
                loading: state.isLoading,
                onSend: _sendMessage,
              );
            },
          ),
        ],
      ),
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(
        _scrollController.position.maxScrollExtent,
      );
    }
  }
}
