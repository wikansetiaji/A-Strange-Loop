import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:provider/provider.dart';
import 'package:a_strange_loop/providers/chat_state.dart';
import 'package:a_strange_loop/models/model_settings.dart';
import 'package:a_strange_loop/theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  bool _apiKeyVisible = false;
  bool _syncInProgress = false;
  String? _syncResult;

  String _selectedModel = ModelSettings.defaultModel;
  String _selectedThinking = ModelSettings.defaultThinking;

  @override
  void initState() {
    super.initState();
    final cs = context.read<ChatState>();
    _selectedModel = cs.modelSettings.model;
    _selectedThinking = cs.modelSettings.thinkingEffort;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _triggerManualSync() async {
    setState(() {
      _syncInProgress = true;
      _syncResult = null;
    });
    try {
      final cs = context.read<ChatState>();
      await cs.reconcileHardcover();
      setState(() => _syncResult = 'Reconciliation complete.');
    } catch (e) {
      setState(() => _syncResult = 'Sync error: $e');
    } finally {
      setState(() => _syncInProgress = false);
    }
  }

  void _saveSettings() {
    context.read<ChatState>().updateModelSettings(ModelSettings(
          model: _selectedModel,
          thinkingEffort: _selectedThinking,
        ));
  }

  Widget _buildDropdown<T>({
    required BuildContext context,
    required T value,
    required List<T> items,
    required String Function(T) labelBuilder,
    required ValueChanged<T> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.expand_more, size: 18, color: cs.onSurface.withAlpha(120)),
          style: AppTextStyles.chatBody(context).copyWith(fontSize: 13),
          dropdownColor: cs.surface,
          items: items.map((item) {
            return DropdownMenuItem<T>(
              value: item,
              child: Text(labelBuilder(item)),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: cs.surface,
        title: Text(
          'SETTINGS',
          style: AppTextStyles.display(context).copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Hardcover Integration',
                style: AppTextStyles.display(context).copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sync your reading activity between your Reading Brain and Hardcover.app. Your brain is the source of truth — Hardcover is a best-effort mirror.',
                style: AppTextStyles.chatBody(context).copyWith(
                  color: cs.onSurface.withAlpha(160),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'API Key',
                style: AppTextStyles.display(context).copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outline, width: 1),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _apiKeyController,
                        obscureText: !_apiKeyVisible,
                        style: AppTextStyles.chatBody(context).copyWith(
                          fontSize: 13,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Paste your Hardcover API key...',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _apiKeyVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: cs.onSurface.withAlpha(120),
                      ),
                      onPressed: () => setState(
                          () => _apiKeyVisible = !_apiKeyVisible),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Get your API key from hardcover.app/account/api',
                style: AppTextStyles.chatCaption(context).copyWith(
                  color: cs.onSurface.withAlpha(100),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Sync',
                style: AppTextStyles.display(context).copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _syncInProgress ? null : _triggerManualSync,
                  icon: _syncInProgress
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.primary,
                          ),
                        )
                      : Icon(Icons.sync, size: 16, color: cs.primary),
                  label: Text(
                    _syncInProgress
                        ? 'Syncing...'
                        : 'Reconcile with Hardcover',
                    style: AppTextStyles.chatBody(context).copyWith(
                      color: cs.primary,
                      fontSize: 13,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: cs.outline),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              if (_syncResult != null) ...[
                const SizedBox(height: 12),
                Text(
                  _syncResult!,
                  style: AppTextStyles.chatCaption(context).copyWith(
                    color: cs.onSurface.withAlpha(120),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              Divider(color: cs.outline),
              const SizedBox(height: 16),
              Text(
                'Model',
                style: AppTextStyles.display(context).copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose the AI model and thinking mode for chat responses. Title generation never uses thinking.',
                style: AppTextStyles.chatBody(context).copyWith(
                  color: cs.onSurface.withAlpha(160),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'AI Model',
                style: AppTextStyles.display(context).copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              _buildDropdown<String>(
                context: context,
                value: _selectedModel,
                items: ModelSettings.modelOptions,
                labelBuilder: (v) => v == 'deepseek-v4-flash'
                    ? 'DeepSeek V4 Flash (fast)'
                    : 'DeepSeek V4 Pro (powerful)',
                onChanged: (v) {
                  setState(() => _selectedModel = v);
                  _saveSettings();
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Thinking Mode',
                style: AppTextStyles.display(context).copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              _buildDropdown<String>(
                context: context,
                value: _selectedThinking,
                items: ModelSettings.thinkingOptions,
                labelBuilder: (v) {
                  switch (v) {
                    case 'disabled':
                      return 'Disabled';
                    case 'low':
                      return 'Low';
                    case 'high':
                      return 'High';
                    case 'max':
                      return 'Max';
                    default:
                      return v;
                  }
                },
                onChanged: (v) {
                  setState(() => _selectedThinking = v);
                  _saveSettings();
                },
              ),
              const SizedBox(height: 32),
              Divider(color: cs.outline),
              const SizedBox(height: 16),
              Text(
                'Account',
                style: AppTextStyles.display(context).copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              if (kDebugMode)
                Text(
                  'Debug mode — auth bypassed',
                  style: AppTextStyles.chatBody(context).copyWith(
                    color: cs.primary,
                    fontSize: 13,
                  ),
                )
              else ...[
                Text(
                  'Signed in as ${FirebaseAuth.instance.currentUser?.email ?? "Unknown"}',
                  style: AppTextStyles.chatBody(context).copyWith(
                    color: cs.onSurface.withAlpha(160),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    icon: Icon(Icons.logout_sharp, size: 16,
                        color: cs.onSurface.withAlpha(140)),
                    label: Text(
                      'Sign Out',
                      style: AppTextStyles.chatBody(context).copyWith(
                        color: cs.onSurface.withAlpha(140),
                        fontSize: 13,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: cs.outline),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
