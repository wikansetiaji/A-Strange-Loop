import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:a_strange_loop/providers/chat_state.dart';
import 'package:a_strange_loop/constants/hardcover_config.dart';
import 'package:a_strange_loop/models/brain.dart';
import 'package:a_strange_loop/theme/app_theme.dart';
import 'package:a_strange_loop/widgets/animations.dart';

class BrainScreen extends StatefulWidget {
  const BrainScreen({super.key});

  @override
  State<BrainScreen> createState() => _BrainScreenState();
}

class _BrainScreenState extends State<BrainScreen> {
  String? _brainContent;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final chatState = context.read<ChatState>();
      unawaited(chatState.reconcileHardcover());
      final json = await chatState.loadBrain(forceRefresh: true);
      if (mounted) {
        setState(() {
          _brainContent = json;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
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
        leading: BackButton(color: cs.onSurface.withAlpha(180)),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PulsingLoop(size: 18, color: cs.primary),
            const SizedBox(width: 10),
            Text(
              'READING BRAIN',
              style: AppTextStyles.display(context).copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        centerTitle: false,
        titleSpacing: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_sharp,
                size: 18, color: cs.onSurface.withAlpha(120)),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: cs.outline),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return _buildError();
    }
    if (_brainContent == null) {
      return Center(
        child: BlockLoader(color: Theme.of(context).colorScheme.primary),
      );
    }
    return _buildBrain(context, _brainContent!);
  }

  Widget _buildError() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_sharp,
                size: 28, color: cs.onSurface.withAlpha(90)),
            const SizedBox(height: 12),
            Text(
              'Could not load the reading brain.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body(context).copyWith(
                color: cs.onSurface.withAlpha(160),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrain(BuildContext context, String json) {
    Brain brain;
    try {
      brain = Brain.fromJson(jsonDecode(json) as Map<String, dynamic>);
      brain.sortBooksByRecent();
    } catch (_) {
      return _buildError();
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 64),
          children: [
            _buildHero(context, brain),
            _section(context, 'Current Reading',
                _buildCurrentReading(context, brain.currentReading)),
            _section(context, 'Reader Profile',
                _buildReaderProfile(context, brain.readerProfile)),
            _section(context, 'Reading Modes',
                _buildReadingModes(context, brain.readingModes)),
            _section(context, 'Vocabulary',
                _buildVocabulary(context, brain.vocabulary)),
            _section(context, 'Favorite Authors',
                _buildFavoriteAuthors(context, brain.favoriteAuthors)),
            _section(context, 'Favorite Books',
                _buildFavoriteBooks(context, brain.favoriteBooks)),
            _section(context, 'Blind Spots',
                _buildBlindSpots(context, brain.readerBlindSpots)),
            _section(context, 'Reading Evolution',
                _buildEvolution(context, brain.readingEvolution)),
            _section(context, 'Active Questions',
                _buildQuestions(context, brain.activeQuestions)),
            _section(context, 'Recommendation Queue',
                _buildQueue(context, brain.recommendationQueue)),
            _section(context, 'Observations',
                _buildObservations(context, brain.observations)),
            _section(context, 'Books', _buildBooks(context, brain.books)),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context, Brain brain) {
    final cs = Theme.of(context).colorScheme;
    final meta = brain.meta;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 10, height: 2, color: cs.primary),
            const SizedBox(width: 10),
            Text('READING BRAIN', style: AppTextStyles.sectionLabel(context)),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          "${meta.name}'s Reading Brain",
          style: AppTextStyles.display(context).copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'VERSION ${brain.version}  \u00b7  UPDATED ${brain.lastUpdated}  '
          '\u00b7  READING SERIOUSLY SINCE ${meta.startedReadingSeriously}',
          style: AppTextStyles.chatCaption(context).copyWith(
            color: cs.onSurface.withAlpha(120),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 22),
        _accentBox(context, cs.primary, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(context, 'Primary Goal'),
            const SizedBox(height: 6),
            Text(
              meta.primaryGoal,
              style: AppTextStyles.display(context).copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ],
        )),
      ],
    );
  }

  Widget _buildCurrentReading(BuildContext context, CurrentReading? cr) {
    final cs = Theme.of(context).colorScheme;
    if (cr == null || !cr.isNotEmpty) {
      return _emptyNote(context, 'No current reading set.');
    }

    final fraction = _progressFraction(cr.progress);

    return _accentBox(context, cs.tertiary, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _label(context, 'Now Reading'),
            const Spacer(),
            Text(
              cr.progress,
              style: AppTextStyles.chatCaption(context).copyWith(
                color: cs.tertiary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          cr.book,
          style: AppTextStyles.display(context).copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        if (fraction != null) ...[
          const SizedBox(height: 14),
          Container(
            height: 6,
            color: cs.surfaceContainerHighest,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction,
              child: Container(color: cs.tertiary),
            ),
          ),
        ],
        if (cr.readingStrategy.isNotEmpty)
          _kv(context, 'Reading Strategy', cr.readingStrategy),
        if (cr.notes.isNotEmpty) _kv(context, 'Notes', cr.notes),
      ],
    ));
  }

  Widget _buildReaderProfile(BuildContext context, ReaderProfile profile) {
    final cs = Theme.of(context).colorScheme;
    final prefs = profile.narrativePreferences;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _accentBox(context, cs.tertiary, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(context, 'Core Philosophy'),
            const SizedBox(height: 6),
            Text(
              profile.corePhilosophy,
              style: AppTextStyles.chatBody(context).copyWith(height: 1.55),
            ),
          ],
        )),
        const SizedBox(height: 14),
        _chipGroup(context, 'Consistently Loved',
            profile.thingsIConsistentlyLove,
            accent: cs.primary),
        const SizedBox(height: 12),
        _label(context, 'Narrative Preferences'),
        const SizedBox(height: 8),
        _chipGroup(context, 'Very High', prefs.veryHigh, accent: cs.primary),
        _chipGroup(context, 'High', prefs.high, accent: cs.tertiary),
        _chipGroup(context, 'Medium', prefs.medium,
            accent: cs.onSurface.withAlpha(140)),
        _chipGroup(context, 'Low', prefs.low,
            accent: cs.onSurface.withAlpha(70)),
      ],
    );
  }

  Widget _buildReadingModes(BuildContext context, Map<String, String> modes) {
    final cs = Theme.of(context).colorScheme;
    if (modes.isEmpty) return _emptyNote(context, '(empty)');

    return Column(
      children: [
        for (final entry in modes.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _box(context, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key.toUpperCase(),
                  style: AppTextStyles.chatCaption(context).copyWith(
                    color: cs.tertiary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.value,
                  style: AppTextStyles.chatBody(context).copyWith(height: 1.5),
                ),
              ],
            )),
          ),
      ],
    );
  }

  Widget _buildVocabulary(
      BuildContext context, Map<String, VocabularyTerm> vocabulary) {
    if (vocabulary.isEmpty) return _emptyNote(context, '(empty)');

    return Column(
      children: [
        for (final entry in vocabulary.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _box(context, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key,
                  style: AppTextStyles.display(context).copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  entry.value.definition,
                  style: AppTextStyles.chatBody(context).copyWith(height: 1.5),
                ),
                if (entry.value.examples.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: entry.value.examples
                        .map((e) => _chip(context, e))
                        .toList(),
                  ),
                ],
              ],
            )),
          ),
      ],
    );
  }

  Widget _buildFavoriteAuthors(
      BuildContext context, FavoriteAuthors authors) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _chipGroup(context, 'Tier S', authors.tierS, accent: cs.primary),
        _chipGroup(context, 'Tier A', authors.tierA, accent: cs.tertiary),
      ],
    );
  }

  Widget _buildFavoriteBooks(BuildContext context, FavoriteBooks books) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < books.ranked.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    (i + 1).toString().padLeft(2, '0'),
                    style: AppTextStyles.chatCaption(context).copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    books.ranked[i],
                    style: AppTextStyles.chatBody(context).copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        if (books.ranked.isEmpty) _emptyNote(context, '(empty)'),
        const SizedBox(height: 12),
        _label(context, 'Favorite Nonfiction'),
        const SizedBox(height: 6),
        _chipsOrDash(context, books.favoriteNonfiction),
        const SizedBox(height: 12),
        _label(context, 'Favorite Short Story Collection'),
        const SizedBox(height: 6),
        _chipsOrDash(context, books.favoriteShortStoryCollection),
      ],
    );
  }

  Widget _buildBlindSpots(BuildContext context, ReaderBlindSpots bs) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _chipGroup(context, 'Probably Overvalued', bs.overvalued,
            accent: cs.primary),
        _kv(context, 'Probably Undervalued', bs.undervalued),
        const SizedBox(height: 12),
        _label(context, 'Books That Changed My Mind'),
        const SizedBox(height: 6),
        _chipsOrDash(context, bs.booksThatChangedMyMind),
      ],
    );
  }

  Widget _buildEvolution(BuildContext context, List<EvolutionEntry> entries) {
    final cs = Theme.of(context).colorScheme;
    if (entries.isEmpty) return _emptyNote(context, '(empty)');

    return Column(
      children: [
        for (var i = 0; i < entries.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 96,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      entries[i].year,
                      style: AppTextStyles.chatCaption(context).copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
                Container(width: 1, color: cs.outline),
                const SizedBox(width: 16),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Text(
                      entries[i].insight,
                      style: AppTextStyles.chatBody(context).copyWith(height: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildQuestions(BuildContext context, List<String> questions) {
    final cs = Theme.of(context).colorScheme;
    if (questions.isEmpty) return _emptyNote(context, '(empty)');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < questions.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    'Q${i + 1}',
                    style: AppTextStyles.chatCaption(context).copyWith(
                      color: cs.tertiary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    questions[i],
                    style: AppTextStyles.chatBody(context).copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildQueue(BuildContext context, RecommendationQueue queue) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _queueTier(context, 'Highest Priority', queue.highestPriority,
            accent: cs.primary),
        _queueTier(context, 'High Confidence', queue.highConfidence,
            accent: cs.tertiary),
        _queueTier(context, 'Future', queue.future,
            accent: cs.onSurface.withAlpha(100)),
      ],
    );
  }

  Widget _buildObservations(
      BuildContext context, List<ObservationEntry> observations) {
    if (observations.isEmpty) return _emptyNote(context, '(empty)');

    return Column(
      children: [
        for (final obs in observations)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _box(context, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv(context, 'Evidence', obs.evidence),
                _kv(context, 'Hypothesis', obs.hypothesis),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _chip(
                      context,
                      'CONFIDENCE ${obs.confidence.toStringAsFixed(2)}',
                      borderColor: _confidenceColor(context, obs.confidence),
                      textColor: _confidenceColor(context, obs.confidence),
                    ),
                    _chip(context, 'LOGGED ${obs.logged}'),
                  ],
                ),
              ],
            )),
          ),
      ],
    );
  }

  Widget _buildBooks(BuildContext context, List<Book> books) {
    if (books.isEmpty) return _emptyNote(context, '(empty)');

    return Column(
      children: [
        for (final book in books)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _box(context, child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (book.coverUrl != null) ...[
                  SizedBox(
                    width: 60,
                    height: 90,
                    child: _coverImage(book.coverUrl!),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              book.title,
                              style:
                                  AppTextStyles.display(context).copyWith(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _statusChip(context, book.status),
                        ],
                      ),
                      if (book.rating != null) ...[
                        const SizedBox(height: 8),
                        _ratingRow(context, book.rating!),
                      ],
                      if (book.personalSignificance != null)
                        _kv(context, 'Significance',
                            book.personalSignificance!),
                      if (book.whyItMatters != null)
                        _kv(context, 'Why It Matters', book.whyItMatters!),
                      if (book.progress != null)
                        _kv(context, 'Progress', book.progress!),
                      if (book.currentImpression != null)
                        _kv(context, 'Impression',
                            book.currentImpression!),
                      if (book.readingStrategy != null)
                        _kv(context, 'Strategy', book.readingStrategy!),
                      if (book.abandonmentReason != null)
                        _kv(context, 'Abandoned',
                            book.abandonmentReason!),
                    ],
                  ),
                ),
              ],
            )),
          ),
      ],
    );
  }

  Widget _queueTier(BuildContext context, String label,
      List<QueueEntry> entries, {Color? accent}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, label, color: accent),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            _emptyNote(context, '(empty)')
          else
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _box(context, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.book,
                      style: AppTextStyles.display(context).copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.reason,
                      style: AppTextStyles.chatBody(context).copyWith(
                        height: 1.4,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withAlpha(160),
                      ),
                    ),
                  ],
                )),
              ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, String status) {
    final cs = Theme.of(context).colorScheme;
    final s = status.trim().toLowerCase();
    final Color color;
    if (s == 'finished') {
      color = cs.primary;
    } else if (s == 'reading' || s == 'in progress' || s == 'currently reading') {
      color = cs.tertiary;
    } else {
      color = cs.onSurface.withAlpha(140);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        status.toUpperCase(),
        style: AppTextStyles.chatCaption(context).copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _ratingRow(BuildContext context, double rating) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(5, (i) {
          return Icon(
            i < rating.round() ? Icons.star_sharp : Icons.star_outline_sharp,
            size: 13,
            color: i < rating.round()
                ? cs.secondary
                : cs.onSurface.withAlpha(50),
          );
        }),
        const SizedBox(width: 6),
        Text(
          rating.toStringAsFixed(1),
          style: AppTextStyles.chatCaption(context).copyWith(
            color: cs.onSurface.withAlpha(140),
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Color _confidenceColor(BuildContext context, double confidence) {
    final cs = Theme.of(context).colorScheme;
    if (confidence >= 0.7) return cs.primary;
    if (confidence >= 0.4) return cs.tertiary;
    return cs.onSurface.withAlpha(120);
  }

  Widget _coverImage(String url) {
    final proxied = '$hardcoverImageProxyBase${Uri.encodeComponent(url)}';
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        proxied,
        width: 60,
        height: 90,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _coverPlaceholder(context),
      ),
    );
  }

  Widget _coverPlaceholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 60,
      height: 90,
      color: cs.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.menu_book, size: 20, color: cs.onSurfaceVariant),
    );
  }

  double? _progressFraction(String progress) {
    final trimmed = progress.trim();
    if (trimmed.endsWith('%')) {
      final value = double.tryParse(
          trimmed.substring(0, trimmed.length - 1));
      if (value != null) return (value / 100).clamp(0.0, 1.0);
    }
    return null;
  }

  Widget _section(BuildContext context, String label, Widget child) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 1, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                label.toUpperCase(),
                style: AppTextStyles.sectionLabel(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text, {Color? color}) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text.toUpperCase(),
      style: AppTextStyles.chatCaption(context).copyWith(
        color: color ?? cs.onSurface.withAlpha(130),
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _kv(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, label),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTextStyles.chatBody(context).copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _box(BuildContext context, {required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline, width: 1),
      ),
      child: child,
    );
  }

  Widget _accentBox(BuildContext context, Color accent, {required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: accent, width: 3),
          top: BorderSide(color: cs.outline, width: 1),
          right: BorderSide(color: cs.outline, width: 1),
          bottom: BorderSide(color: cs.outline, width: 1),
        ),
      ),
      child: child,
    );
  }

  Widget _chip(
    BuildContext context,
    String text, {
    Color? borderColor,
    Color? textColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor ?? cs.outline, width: 1),
      ),
      child: Text(
        text,
        style: AppTextStyles.chatCaption(context).copyWith(
          color: textColor ?? cs.onSurface.withAlpha(200),
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _chipsOrDash(BuildContext context, List<String> items) {
    if (items.isEmpty) return _emptyNote(context, '\u2014');
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items.map((e) => _chip(context, e)).toList(),
    );
  }

  Widget _chipGroup(BuildContext context, String label, List<String> items,
      {Color? accent}) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: _label(context, label, color: accent)),
          Expanded(
            child: _chipsOrDash(context, items),
          ),
        ],
      ),
    );
  }

  Widget _emptyNote(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: AppTextStyles.chatCaption(context).copyWith(
        color: cs.onSurface.withAlpha(80),
        fontStyle: FontStyle.italic,
      ),
    );
  }
}
