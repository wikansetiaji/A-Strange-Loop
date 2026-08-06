class HardcoverUserBook {
  final int id;
  final String status;
  final double? rating;
  final String? review;
  final bool reviewHasSpoilers;
  final String? dateAdded;
  final String? firstReadDate;
  final String? lastReadDate;
  final int readsCount;
  final int bookId;
  final String? bookTitle;

  const HardcoverUserBook({
    required this.id,
    required this.status,
    this.rating,
    this.review,
    this.reviewHasSpoilers = false,
    this.dateAdded,
    this.firstReadDate,
    this.lastReadDate,
    this.readsCount = 0,
    required this.bookId,
    this.bookTitle,
  });

  factory HardcoverUserBook.fromJson(Map<String, dynamic> json) {
    final book = json['book'] as Map<String, dynamic>?;
    final statusId = json['status_id'] as int?;
    final status = _idToStatus(statusId);
    return HardcoverUserBook(
      id: json['id'] as int,
      status: status,
      rating: (json['rating'] as num?)?.toDouble(),
      review: json['review'] as String?,
      reviewHasSpoilers: json['review_has_spoilers'] as bool? ?? false,
      dateAdded: json['date_added'] as String?,
      firstReadDate: json['first_read_date'] as String?,
      lastReadDate: json['last_read_date'] as String?,
      readsCount: json['read_count'] as int? ?? 0,
      bookId: json['book_id'] as int,
      bookTitle: book?['title'] as String?,
    );
  }
}

String _idToStatus(int? id) {
  switch (id) {
    case 1: return 'Want to Read';
    case 2: return 'Currently Reading';
    case 3: return 'Read';
    case 4: return 'Paused';
    case 5: return 'Did Not Finish';
    case 6: return 'Ignored';
    default: return 'Want to Read';
  }
}

class HardcoverBookDetail {
  final int id;
  final String title;
  final String? subtitle;
  final String? description;
  final int? pages;
  final double? rating;
  final int? ratingsCount;
  final String? releaseDate;
  final String? slug;
  final String? coverUrl;
  final List<String> genres;
  final List<HardcoverAuthor> authors;

  const HardcoverBookDetail({
    required this.id,
    required this.title,
    this.subtitle,
    this.description,
    this.pages,
    this.rating,
    this.ratingsCount,
    this.releaseDate,
    this.slug,
    this.coverUrl,
    this.genres = const [],
    this.authors = const [],
  });

  String? get primaryAuthor =>
      authors.isNotEmpty ? authors.first.name : null;

  String get hardcoverUrl => 'https://hardcover.app/books/$slug';

  factory HardcoverBookDetail.fromJson(Map<String, dynamic> json) {
    final image = json['image'] as Map<String, dynamic>?;
    final authors = (json['contributions'] as List<dynamic>?)
            ?.map((c) {
              final author = c['author'] as Map<String, dynamic>?;
              return author != null
                  ? HardcoverAuthor.fromJson(author)
                  : null;
            })
            .whereType<HardcoverAuthor>()
            .toList() ??
        [];
    return HardcoverBookDetail(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String?,
      description: json['description'] as String?,
      pages: json['pages'] as int?,
      rating: (json['rating'] as num?)?.toDouble(),
      ratingsCount: json['ratings_count'] as int?,
      releaseDate: json['release_date'] as String?,
      slug: json['slug'] as String?,
      coverUrl: image?['url'] as String?,
      genres: [],
      authors: authors,
    );
  }
}

class HardcoverAuthor {
  final int id;
  final String name;

  const HardcoverAuthor({required this.id, required this.name});

  factory HardcoverAuthor.fromJson(Map<String, dynamic> json) {
    return HardcoverAuthor(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
    );
  }
}

class HardcoverSearchResult {
  final int id;
  final String title;
  final String? description;
  final int? pages;
  final double? rating;
  final String? coverUrl;
  final String? author;
  final String? slug;

  const HardcoverSearchResult({
    required this.id,
    required this.title,
    this.description,
    this.pages,
    this.rating,
    this.coverUrl,
    this.author,
    this.slug,
  });

  String get hardcoverUrl => 'https://hardcover.app/books/$slug';

  factory HardcoverSearchResult.fromJson(Map<String, dynamic> json) {
    final image = json['image'] as Map<String, dynamic>?;
    final contributions = json['contributions'] as List<dynamic>?;
    String? primaryAuthor;
    if (contributions != null && contributions.isNotEmpty) {
      final first = contributions.first as Map<String, dynamic>?;
      final author = first?['author'] as Map<String, dynamic>?;
      primaryAuthor = author?['name'] as String?;
    }
    return HardcoverSearchResult(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      pages: json['pages'] as int?,
      rating: (json['rating'] as num?)?.toDouble(),
      coverUrl: image?['url'] as String?,
      author: primaryAuthor,
      slug: json['slug'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (description != null) 'description': description,
        if (pages != null) 'pages': pages,
        if (rating != null) 'rating': rating,
        if (coverUrl != null) 'coverUrl': coverUrl,
        if (author != null) 'author': author,
        if (slug != null) 'url': hardcoverUrl,
      };
}
