import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:a_strange_loop/models/brain.dart';
import 'package:a_strange_loop/models/hardcover_models.dart';
import 'package:a_strange_loop/models/sync_queue.dart';
import 'package:a_strange_loop/services/firestore_service.dart';
import 'package:a_strange_loop/services/hardcover_service.dart';
import 'package:a_strange_loop/services/brain_parser.dart';

class SyncService {
  final FirestoreService _firestore;
  final HardcoverService _hardcover;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _collPrefix;
  Timer? _periodicTimer;
  StreamSubscription? _queueListener;

  int _syncPendingCount = 0;
  int get syncPendingCount => _syncPendingCount;

  String get _meta => 'meta$_collPrefix';

  SyncService({
    required FirestoreService firestore,
    required HardcoverService hardcover,
    String collectionPrefix = '',
  })  : _firestore = firestore,
        _hardcover = hardcover,
        _collPrefix = collectionPrefix;

  Future<void> startupReconcile() async {
    try {
      final userBooks = await _hardcover.fetchUserBooks();
      final bookIds = userBooks.map((e) => e.bookId).toSet().toList();
      final details = await _hardcover.fetchBookDetails(bookIds);
      final detailsById = <int, HardcoverBookDetail>{};
      for (final d in details) {
        detailsById[d.id] = d;
      }

      final brainJson = await _firestore.getBrain();
      final brain = Brain.fromJson(
          jsonDecode(brainJson) as Map<String, dynamic>);
      var changed = false;

      for (final ub in userBooks) {
        final detail = detailsById[ub.bookId];
        final hardcoverId = ub.bookId.toString();

        var matchedBook = brain.books.cast<Book?>().firstWhere(
            (b) => b!.hardcoverId == hardcoverId,
            orElse: () => null);
        if (matchedBook == null) {
          final normalizedTitle = _normalize(ub.bookTitle ?? '');
          matchedBook = brain.books.cast<Book?>().firstWhere(
              (b) => _normalize(b!.title) == normalizedTitle,
              orElse: () => null);
        }

        if (matchedBook != null) {
          _enrichBook(matchedBook, ub, detail);
          changed = true;
        } else {
          final stub = _createStub(ub, detail);
          brain.books.add(stub);
          changed = true;
        }
      }

      final cr = brain.currentReading;
      if (cr != null && cr.isNotEmpty && cr.hardcoverId == null) {
        for (final ub in userBooks) {
          if (_normalize(ub.bookTitle ?? '') == _normalize(cr.book)) {
            cr.hardcoverId = ub.bookId.toString();
            changed = true;
            break;
          }
        }
        if (cr.hardcoverId == null) {
          final matched = brain.books.cast<Book?>().firstWhere(
              (b) => _normalize(b!.title) == _normalize(cr.book) && b.hardcoverId != null,
              orElse: () => null);
          if (matched != null) {
            cr.hardcoverId = matched.hardcoverId;
            changed = true;
          }
        }
      }

      for (final book in brain.books) {
        if (book.hardcoverId == null) continue;
        final bid = int.tryParse(book.hardcoverId!);
        if (bid == null) continue;
        final inHardcover = userBooks.any((ub) => ub.bookId == bid);
        if (!inHardcover) {
          _enqueueItem(SyncQueueItem(
            action: 'upsert_user_book',
            payload: _bookToPayload(book),
            bookTitle: book.title,
          ));
        }
      }

      brain.books.removeWhere((b) => b.isStub && b.hardcoverId == null);

      if (changed) {
        brain.lastUpdated = _todayString();
        await _firestore.updateBrain(
          const JsonEncoder.withIndent('  ').convert(brain.toJson()),
          [],
        );
      }
    } catch (e) {
      debugPrint('Reconciliation error: $e');
    }
  }

  void _enrichBook(
      Book book, HardcoverUserBook ub, HardcoverBookDetail? detail) {
    book.hardcoverId ??= ub.bookId.toString();
    book.author ??= detail?.primaryAuthor;
    book.coverUrl ??= detail?.coverUrl;
    if (detail?.genres.isNotEmpty == true && book.genres.isEmpty) {
      book.genres = detail!.genres;
    }
    book.pages ??= detail?.pages;
    book.hardcoverUrl ??= detail?.hardcoverUrl;
    book.dateAdded ??= ub.dateAdded;
    book.dateRead ??= ub.lastReadDate;
    book.hardcoverStatus = ub.status;
    book.hardcoverRating = ub.rating;
    book.rating ??= ub.rating;
    if (book.isStub) {
      book.status = _hardcoverStatusToBrain(ub.status);
    }
  }

  Book _createStub(HardcoverUserBook ub, HardcoverBookDetail? detail) {
    return Book(
      title: detail?.title ?? ub.bookTitle ?? 'Unknown Book',
      status: _hardcoverStatusToBrain(ub.status),
      hardcoverId: ub.bookId.toString(),
      author: detail?.primaryAuthor,
      coverUrl: detail?.coverUrl,
      genres: detail?.genres ?? [],
      pages: detail?.pages,
      hardcoverUrl: detail?.hardcoverUrl,
      dateAdded: ub.dateAdded,
      dateRead: ub.lastReadDate,
      hardcoverStatus: ub.status,
      rating: ub.rating,
      hardcoverRating: ub.rating,
    );
  }

  static String _hardcoverStatusToBrain(String hcStatus) {
    switch (hcStatus) {
      case 'Read':
        return 'Finished';
      case 'Currently Reading':
        return 'Reading';
      case 'Paused':
        return 'Reading';
      case 'Did Not Finish':
        return 'Abandoned';
      default:
        return 'Want to Read';
    }
  }

  Map<String, dynamic> _bookToPayload(Book book) {
    return {
      'title': book.title,
      'status': book.status,
      if (book.hardcoverId != null) 'hardcoverId': book.hardcoverId,
      if (book.hardcoverReview != null)
        'hardcoverReview': book.hardcoverReview,
      'hardcoverSpoiler': book.hardcoverSpoiler,
      if (book.rating != null) 'rating': book.rating,
      if (book.author != null) 'author': book.author,
    };
  }

  Future<void> startPeriodicSync() async {
    await drainSyncQueue();
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => drainSyncQueue(),
    );
    _queueListener = _db.collection(_meta).doc('sync_queue').snapshots().listen((_) {
      drainSyncQueue();
    });
  }

  Future<void> drainSyncQueue() async {
    try {
      final snapshot = await _db
          .collection(_meta)
          .doc('sync_queue')
          .collection('items')
          .where('status', isEqualTo: 'pending')
          .limit(20)
          .get();

      if (snapshot.docs.isEmpty) {
        _syncPendingCount = 0;
        return;
      }

      for (final doc in snapshot.docs) {
        final item = SyncQueueItem.fromMap(doc.id, doc.data());
        await doc.reference.update({'status': 'in_progress'});

        try {
          await _processSyncItem(item);
          await doc.reference.delete();
        } catch (e) {
          final newRetry = item.retryCount + 1;
          if (item.isAbandoned) {
            await doc.reference.delete();
            if (item.bookTitle != null) {
              await _pruneStub(item.bookTitle!);
            }
          } else {
            await doc.reference.update({
              'status': 'failed',
              'retryCount': newRetry,
              'lastError': e.toString(),
            });
          }
        }
      }

      final pendingSnapshot = await _db
          .collection(_meta)
          .doc('sync_queue')
          .collection('items')
          .where('status', isEqualTo: 'pending')
          .count()
          .get();
      _syncPendingCount = pendingSnapshot.count ?? 0;
    } catch (e) {
      debugPrint('Sync queue drain error: $e');
    }
  }

  int get pendingCount => _syncPendingCount;

  Future<void> _processSyncItem(SyncQueueItem item) async {
    final action = item.action;
    final payload = item.payload;
    final title = payload['title'] as String? ?? item.bookTitle ?? '';

    int? bookId;
    if (payload['hardcoverId'] != null) {
      bookId = int.tryParse(payload['hardcoverId'] as String);
    }

    if (bookId == null && title.isNotEmpty) {
      bookId = await _resolveBookId(title);
    }

    switch (action) {
      case 'upsert_user_book':
        if (bookId == null) return;
        final status = payload['status'] as String? ?? 'Read';
        final rating = (payload['rating'] as num?)?.toDouble();
        final review = payload['hardcoverReview'] as String?;
        final spoiler = payload['hardcoverSpoiler'] as bool?;
        final pagesRead = (payload['pagesRead'] as num?)?.toInt();
        await _hardcover.upsertUserBook(
          bookId: bookId,
          status: status,
          rating: rating,
          review: review,
          spoiler: spoiler,
          pagesRead: pagesRead,
        );
        if (title.isNotEmpty) {
          await _writeBookHardcoverId(title, bookId.toString());
        }
        break;

      case 'delete_user_book':
        if (bookId == null) return;
        await _hardcover.deleteUserBook(bookId);
        break;
    }
  }

  Future<int?> _resolveBookId(String title) async {
    try {
      final results = await _hardcover.searchBooks(title);
      if (results.isNotEmpty) return results.first.id;
      final newId = await _hardcover.createBook(title);
      return newId;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeBookHardcoverId(String title, String hardcoverId) async {
    try {
      final brainJson = await _firestore.getBrain();
      final brain = Brain.fromJson(
          jsonDecode(brainJson) as Map<String, dynamic>);
      for (final book in brain.books) {
        if (_normalize(book.title) == _normalize(title)) {
          book.hardcoverId = hardcoverId;
          brain.lastUpdated = _todayString();
          await _firestore.updateBrain(
            const JsonEncoder.withIndent('  ').convert(brain.toJson()),
            [],
          );
          return;
        }
      }
    } catch (_) {}
  }

  Future<void> _pruneStub(String title) async {
    try {
      final brainJson = await _firestore.getBrain();
      final brain = Brain.fromJson(
          jsonDecode(brainJson) as Map<String, dynamic>);
      brain.books.removeWhere(
          (b) => _normalize(b.title) == _normalize(title) && b.isStub);
      brain.lastUpdated = _todayString();
      await _firestore.updateBrain(
        const JsonEncoder.withIndent('  ').convert(brain.toJson()),
        [],
      );
    } catch (_) {}
  }

  void enqueueFromBrainMutation(
      List<OperationBlock> blocks, String previousBrainJson) {
    Brain? previousBrain;
    try {
      previousBrain = Brain.fromJson(
          jsonDecode(previousBrainJson) as Map<String, dynamic>);
    } catch (_) {}

    final abandonedTitles = <String>{};
    for (final block in blocks) {
      if (block.type == BlockType.appendBook &&
          block.jsonData['status'] == 'Abandoned') {
        abandonedTitles
            .add(_normalize(block.jsonData['title'] as String? ?? ''));
      }
    }

    for (final block in blocks) {
      switch (block.type) {
        case BlockType.appendBook:
          _enqueueItem(SyncQueueItem(
            action: 'upsert_user_book',
            payload: _jsonToPayload(block.jsonData),
            bookTitle: block.jsonData['title'] as String?,
          ));
          break;

        case BlockType.updateBook:
          final bookJson =
              block.jsonData['book'] as Map<String, dynamic>?;
          if (bookJson != null) {
            _enqueueItem(SyncQueueItem(
              action: 'upsert_user_book',
              payload: _jsonToPayload(bookJson),
              bookTitle: bookJson['title'] as String?,
            ));
          }
          break;

        case BlockType.deleteBook:
          final targetTitle =
              block.jsonData['targetTitle'] as String? ?? '';
          if (targetTitle.isEmpty) break;
          final existing = previousBrain?.books
              .where((b) => b.title == targetTitle)
              .firstOrNull;
          if (existing?.hardcoverId != null) {
            _enqueueItem(SyncQueueItem(
              action: 'delete_user_book',
              payload: {'hardcoverId': existing!.hardcoverId},
              bookTitle: targetTitle,
            ));
          }
          break;

        case BlockType.patch:
          final targetSection =
              block.jsonData['targetSection'] as String? ?? '';
          if (targetSection == 'CURRENT_READING') {
            final replacement =
                block.jsonData['replacementContent'];
            if (replacement == null || replacement is Map && replacement.isEmpty) {
              final prevBook =
                  previousBrain?.currentReading?.book;
              if (prevBook != null && prevBook.isNotEmpty) {
                final isAbandoned =
                    abandonedTitles.contains(_normalize(prevBook)) ||
                    previousBrain?.books.any((b) =>
                        _normalize(b.title) == _normalize(prevBook) &&
                        b.status == 'Abandoned') == true;
                _enqueueItem(SyncQueueItem(
                  action: 'upsert_user_book',
                  payload: {
                    'title': prevBook,
                    'status': isAbandoned ? 'Did Not Finish' : 'Read',
                  },
                  bookTitle: prevBook,
                ));
              }
            } else if (replacement is Map<String, dynamic>) {
              var hardcoverIdStr =
                  replacement['hardcoverId'] as String? ??
                  previousBrain?.currentReading?.hardcoverId;
              final progress = replacement['progress'] as String?;
              if (hardcoverIdStr == null && progress != null) {
                final bookTitle = replacement['book'] as String? ??
                    previousBrain?.currentReading?.book;
                if (bookTitle != null && bookTitle.isNotEmpty) {
                  final matchedBook = previousBrain?.books.cast<Book?>().firstWhere(
                      (b) =>
                          _normalize(b!.title) == _normalize(bookTitle) &&
                          b.hardcoverId != null,
                      orElse: () => null);
                  hardcoverIdStr = matchedBook?.hardcoverId;
                }
              }
              if (hardcoverIdStr != null && progress != null) {
                final hardcoverId = int.tryParse(hardcoverIdStr);
                if (hardcoverId != null) {
                  final fraction = _parseProgressFraction(progress);
                  final book = previousBrain?.books.cast<Book?>().firstWhere(
                      (b) => b!.hardcoverId == hardcoverIdStr,
                      orElse: () => null);
                  final pages = book?.pages;
                  final pagesRead = fraction != null && pages != null
                      ? (pages * fraction).round()
                      : null;
                  _enqueueItem(SyncQueueItem(
                    action: 'upsert_user_book',
                    payload: {
                      'hardcoverId': hardcoverIdStr,
                      'title': replacement['book'] as String? ?? '',
                      'status': 'Currently Reading',
                      if (pagesRead != null) 'pagesRead': pagesRead,
                    },
                    bookTitle: replacement['book'] as String?,
                  ));
                }
              }
            }
          }
          break;

        case BlockType.observation:
          break;
      }
    }
  }

  void _enqueueItem(SyncQueueItem item) {
    _db
        .collection(_meta)
        .doc('sync_queue')
        .collection('items')
        .add(item.toMap());
  }

  Map<String, dynamic> _jsonToPayload(Map<String, dynamic> json) {
    return {
      'title': json['title'] as String? ?? '',
      'status': json['status'] as String? ?? 'Read',
      if (json['hardcoverId'] != null) 'hardcoverId': json['hardcoverId'],
      if (json['hardcoverReview'] != null)
        'hardcoverReview': json['hardcoverReview'],
      'hardcoverSpoiler': json['hardcoverSpoiler'] as bool? ?? false,
      if (json['rating'] != null) 'rating': json['rating'],
    };
  }

  String _normalize(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';
  }

  static double? _parseProgressFraction(String progress) {
    final trimmed = progress.trim();
    if (trimmed.endsWith('%')) {
      final num = double.tryParse(trimmed.substring(0, trimmed.length - 1));
      if (num != null) return num / 100;
    }
    final d = double.tryParse(trimmed);
    if (d != null && d <= 1) return d;
    if (d != null && d > 1) return d / 100;
    return null;
  }

  void dispose() {
    _periodicTimer?.cancel();
    _queueListener?.cancel();
    _hardcover.dispose();
  }
}
