import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:a_strange_loop/providers/chat_state.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

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
    context.read<ChatState>().sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: _buildAppBar(),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 768),
          child: Column(
            children: [
              Expanded(child: _buildMessageList()),
              _buildErrorBanner(),
              _buildTokenFooter(),
              _buildInputBar(),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Consumer<ChatState>(
        builder: (context, state, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('A Strange Loop',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              if (state.currentBookTitle != null)
                Text(
                  'Reading: ${state.currentBookTitle}'
                  '${state.currentBookProgress != null ? ' · ${state.currentBookProgress}' : ''}',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withAlpha(150)),
                ),
            ],
          );
        },
      ),
      centerTitle: false,
      titleSpacing: 16,
      actions: [
        IconButton(
          icon: const Icon(Icons.logout, size: 20),
          tooltip: 'Sign out',
          onPressed: () => FirebaseAuth.instance.signOut(),
        ),
      ],
    );
  }

  Widget _buildMessageList() {
    return Consumer<ChatState>(
      builder: (context, state, _) {
        if (state.messages.isEmpty && state.streamingContent == null) {
          return _buildEmptyState();
        }
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _scrollToBottom());
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: state.messages.length +
              (state.streamingContent != null ? 1 : 0),
          itemBuilder: (context, index) {
            if (state.streamingContent != null &&
                index == state.messages.length) {
              if (state.streamingContent!.isEmpty) {
                return _buildTypingIndicator();
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome,
                size: 48,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const Text(
              "I'm A Strange Loop. I am your reading brain. Ask me "
              'anything; what to read next, how your taste has evolved, '
              'or just talk about books.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, height: 1.5),
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
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(content,
            style: const TextStyle(fontSize: 15, height: 1.5)),
      ),
    );
  }

  Widget _buildAssistantText(String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withAlpha(60),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MarkdownBody(
                data: content,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(fontSize: 15, height: 1.6),
                  h1: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface),
                  h2: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface),
                  h3: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface),
                  blockquoteDecoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withAlpha(80),
                        width: 2,
                      ),
                    ),
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Consumer<ChatState>(
        builder: (context, state, _) {
          final label = state.isCompressing
              ? 'Compressing conversation history...'
              : 'Thinking...';
          return Row(
            children: [
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withAlpha(60),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withAlpha(120),
                    fontStyle: FontStyle.italic,
                  )),
            ],
          );
        },
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
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            '${state.messages.length} messages$suffix · ${state.formattedSessionTokens}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withAlpha(100),
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
          content:
              Text(state.error!, style: const TextStyle(fontSize: 13)),
          backgroundColor:
              Theme.of(context).colorScheme.errorContainer,
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
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      
      child: Row(
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): _sendMessage,
              },
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: 'Ask me anything, friend...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none),
                  filled: true,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
                textInputAction: TextInputAction.newline,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Consumer<ChatState>(
            builder: (context, state, _) {
              return IconButton.filled(
                onPressed: state.isLoading ? null : _sendMessage,
                icon: const Icon(Icons.arrow_upward),
              );
            },
          ),
        ],
      ),
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }
}
