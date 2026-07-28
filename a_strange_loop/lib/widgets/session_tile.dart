import 'package:flutter/material.dart';
import 'package:a_strange_loop/models/session.dart';
import 'package:a_strange_loop/theme/app_theme.dart';

class SessionTile extends StatelessWidget {
  final Session session;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  const SessionTile({
    super.key,
    required this.session,
    required this.isActive,
    required this.onTap,
    required this.onPin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color:
            isActive ? colorScheme.surfaceContainerHighest : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isActive)
                  Container(
                    width: 3,
                    margin:
                        const EdgeInsets.only(right: 8, top: 3, bottom: 2),
                    color: colorScheme.primary,
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.sidebarTitle(context).copyWith(
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.w500,
                          letterSpacing: 0.2,
                          color: isActive
                              ? colorScheme.onSurface
                              : colorScheme.onSurface.withAlpha(190),
                        ),
                      ),
                      if (session.lastMessage.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          session.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.sidebarSubtitle(context)
                              .copyWith(
                            color: colorScheme.onSurface.withAlpha(110),
                          ),
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        _formatDate(session.updatedAt),
                        style: AppTextStyles.sidebarDate(context).copyWith(
                          color: colorScheme.onSurface.withAlpha(60),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    session.pinned
                        ? Icons.push_pin_sharp
                        : Icons.push_pin_outlined,
                    size: 15,
                    color: session.pinned
                        ? colorScheme.primary
                        : colorScheme.onSurface.withAlpha(90),
                  ),
                  onPressed: onPin,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline_sharp,
                      size: 15,
                      color: colorScheme.onSurface.withAlpha(90)),
                  onPressed: onDelete,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}
