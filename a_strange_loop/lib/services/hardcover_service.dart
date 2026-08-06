import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:a_strange_loop/constants/hardcover_config.dart';
import 'package:a_strange_loop/models/hardcover_models.dart';

class HardcoverService {
  final http.Client _client = http.Client();
  String apiKey = hardcoverApiKey;

  static int statusToId(String status) {
    switch (status) {
      case 'Want to Read': return 1;
      case 'Currently Reading':
      case 'Reading': return 2;
      case 'Read':
      case 'Finished': return 3;
      case 'Paused': return 4;
      case 'Did Not Finish':
      case 'Abandoned': return 5;
      default: return 1;
    }
  }

  static String? idToStatus(int? id) {
    switch (id) {
      case 1: return 'Want to Read';
      case 2: return 'Currently Reading';
      case 3: return 'Read';
      case 4: return 'Paused';
      case 5: return 'Did Not Finish';
      case 6: return 'Ignored';
      default: return null;
    }
  }

  Future<List<HardcoverUserBook>> fetchUserBooks() async {
    final query = '''
query GetUserBooks {
  user_books(
    where: { user_id: { _eq: $hardcoverUserId }, status_id: { _in: [1, 2, 3, 4, 5] } }
    limit: 200
  ) {
    id
    status_id
    rating
    review
    review_has_spoilers
    date_added
    last_read_date
    book_id
    book { id title }
  }
}
''';
    final data = await _graphqlRequest(query);
    final userBooks = (data['user_books'] as List)
        .map((e) => HardcoverUserBook.fromJson(e as Map<String, dynamic>))
        .toList();
    return userBooks;
  }

  Future<List<HardcoverBookDetail>> fetchBookDetails(List<int> bookIds) async {
    if (bookIds.isEmpty) return [];
    final results = <HardcoverBookDetail>[];
    for (var i = 0; i < bookIds.length; i += 20) {
      final batch = bookIds.sublist(i, (i + 20).clamp(0, bookIds.length));
      final result = await _fetchBookDetailBatch(batch);
      results.addAll(result);
    }
    return results;
  }

  Future<List<HardcoverBookDetail>> _fetchBookDetailBatch(
      List<int> bookIds) async {
    final ids = bookIds.join(', ');
    final query = '''
query GetBookDetails {
  books(where: { id: { _in: [$ids] } }) {
    id
    title
    subtitle
    description
    pages
    rating
    ratings_count
    release_date
    slug
    image { url }
    contributions { author { id name } }
  }
}
''';
    final data = await _graphqlRequest(query);
    return (data['books'] as List)
        .map((e) =>
            HardcoverBookDetail.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<HardcoverSearchResult>> searchBooks(String query) async {
    final escaped = query.replaceAll('"', '\\"');
    final gql = '''
query SearchBooks {
  search(query: "$escaped", query_type: "book", per_page: 5) {
    ids
  }
}
''';
    try {
      final data = await _graphqlRequest(gql);
      final searchData = data['search'] as Map<String, dynamic>?;
      final ids = (searchData?['ids'] as List?)
          ?.map((e) => e as int)
          .toList();
      if (ids == null || ids.isEmpty) return [];
      final details = await fetchBookDetails(ids);
      return details.map((d) => _detailToSearchResult(d)).toList();
    } catch (_) {
      return [];
    }
  }

  HardcoverSearchResult _detailToSearchResult(HardcoverBookDetail d) {
    return HardcoverSearchResult(
      id: d.id,
      title: d.title,
      description: d.description,
      pages: d.pages,
      rating: d.rating,
      coverUrl: d.coverUrl,
      author: d.primaryAuthor,
      slug: d.slug,
    );
  }

  Future<int?> upsertUserBook({
    required int bookId,
    required String status,
    double? rating,
    String? review,
    bool? spoiler,
    int? pagesRead,
  }) async {
    final statusId = statusToId(status);
    final ratingStr = rating != null ? '$rating' : 'null';

    final existingIds = await _findUserBookIds(bookId);
    int? userBookId;
    if (existingIds.isNotEmpty) {
      userBookId = existingIds.first;
      final parts = <String>['status_id: $statusId'];
      if (rating != null) parts.add('rating: $ratingStr');
      if (review != null) {
        final escapedReview = review.replaceAll('"', '\\"').replaceAll('\n', '\\n');
        parts.add('review_markdown: "$escapedReview"');
      }
      if (spoiler != null) parts.add('review_has_spoilers: $spoiler');
      final updateMutation = '''
mutation UpdateUserBook {
  update_user_book(
    id: $userBookId
    object: { ${parts.join(', ')} }
  ) {
    id
  }
}
''';
      await _graphqlRequest(updateMutation);
    } else {
      final insertParts = <String>['book_id: $bookId', 'status_id: $statusId'];
      if (rating != null) insertParts.add('rating: $ratingStr');
      if (review != null) {
        final escapedReview = review.replaceAll('"', '\\"').replaceAll('\n', '\\n');
        insertParts.add('review_markdown: "$escapedReview"');
      }
      if (spoiler != null) insertParts.add('review_has_spoilers: $spoiler');
      final mutation = '''
mutation InsertUserBook {
  insert_user_book(object: { ${insertParts.join(', ')} }) { id }
}
''';
      final data = await _graphqlRequest(mutation);
      userBookId = ((data['insert_user_book'] as Map<String, dynamic>?) ?? {})['id'] as int?;
    }

    if (pagesRead != null && userBookId != null) {
      await _insertReadingProgress(userBookId, pagesRead);
    }

    return userBookId;
  }

  Future<List<int>> _findUserBookIds(int bookId) async {
    final query = '''
query FindUserBooks {
  user_books(where: { book_id: { _eq: $bookId }, user_id: { _eq: $hardcoverUserId } }) { id }
}
''';
    try {
      final data = await _graphqlRequest(query);
      final list = data['user_books'] as List? ?? [];
      return list.map((e) => (e as Map<String, dynamic>)['id'] as int).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _insertReadingProgress(int userBookId, int pagesRead) async {
    final mutation = '''
mutation InsertReadingProgress {
  insert_user_book_read(
    user_book_id: $userBookId
    user_book_read: { progress_pages: $pagesRead }
  ) {
    id
  }
}
''';
    await _graphqlRequest(mutation);
  }

  Future<void> deleteUserBook(int bookId) async {
    final ids = await _findUserBookIds(bookId);
    for (final userBookId in ids) {
      final mutation = '''
mutation DeleteUserBook {
  delete_user_book(id: $userBookId) { id }
}
''';
      await _graphqlRequest(mutation);
    }
  }

  Future<int> createBook(String title, {int? pages, String? releaseDate}) async {
    final escaped = title.replaceAll('"', '\\"');
    final pagesStr = pages != null ? 'pages: $pages' : '';
    final dateStr = releaseDate != null ? 'release_date: "$releaseDate"' : '';
    final inputParts = ['title: "$escaped"'];
    if (pagesStr.isNotEmpty) inputParts.add(pagesStr);
    if (dateStr.isNotEmpty) inputParts.add(dateStr);
    final mutation = '''
mutation CreateBook {
  createBook(input: { ${inputParts.join(', ')} }) { book { id } }
}
''';
    final data = await _graphqlRequest(mutation);
    final created = data['createBook'] as Map<String, dynamic>?;
    final book = created?['book'] as Map<String, dynamic>?;
    if (book == null) throw Exception('Failed to create book');
    return book['id'] as int;
  }

  Future<Map<String, dynamic>> _graphqlRequest(String query,
      {int retries = 3}) async {
    Exception? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(seconds: (1 << (attempt - 1)) * 2));
      }
      try {
        final response = await _client.post(
          Uri.parse(hardcoverApiEndpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({'query': query}),
        );
        if (response.statusCode == 429) {
          throw Exception('Throttled');
        }
        if (response.statusCode != 200) {
          throw Exception(
              'Hardcover API error ${response.statusCode}: ${response.body}');
        }
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body.containsKey('errors')) {
          final errors = body['errors'] as List;
          final hasThrottled = errors.any(
              (e) => (e is Map && e['message']?.toString().toLowerCase().contains('throttle') == true));
          if (hasThrottled) {
            throw Exception('Throttled');
          }
          throw Exception('Hardcover GraphQL error: $errors');
        }
        return body['data'] as Map<String, dynamic>;
      } on Exception catch (e) {
        lastError = e;
        if (e.toString() != 'Exception: Throttled') {
          rethrow;
        }
      }
    }
    throw lastError ?? Exception('Hardcover request failed after $retries retries');
  }

  Map<String, dynamic> get searchBooksTool => {
        'type': 'function',
        'function': {
          'name': 'searchBooks',
          'description':
              'Search for books on Hardcover.app. Use this to find book '
                  'metadata, discover similar books, or look up books by '
                  'title/author/topic. Returns up to 5 results with id, '
                  'title, author, cover, rating, and description.',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description':
                    'The search query — book title, author name, or topic keywords',
              },
            },
            'required': ['query'],
          },
        },
      };

  void dispose() {
    _client.close();
  }
}
