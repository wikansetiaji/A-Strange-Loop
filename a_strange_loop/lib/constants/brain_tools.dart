class BrainTools {
  static List<Map<String, dynamic>> get all => [
        searchBooks,
        searchWeb,
        appendBook,
        updateBook,
        deleteBook,
        patchBrain,
        logObservation,
      ];

  static const searchBooks = {
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

  static const searchWeb = {
    'type': 'function',
    'function': {
      'name': 'searchWeb',
      'description':
          'Search the open web. Use this for anything that is NOT a '
              'book-metadata lookup: current events, author news, essays, '
              'criticism, scholarly work, or general knowledge. For book '
              'titles, metadata, or reviews, use searchBooks instead.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'The web search query',
          },
          'type': {
            'type': 'string',
            'enum': ['auto', 'deep'],
            'description':
                "'auto': fast search returning top results with highlighted "
                    'snippets. Use for quick facts, links, or scanning sources. '
                    "'deep': multi-step research returning a synthesized, cited "
                    'answer. Use for open-ended questions, "summarize X", or '
                    '"what is the current state of Y".',
          },
          'numResults': {
            'type': 'integer',
            'description': 'Number of results to return, 1-10. Default 5.',
          },
          'category': {
            'type': 'string',
            'enum': ['news', 'publication', 'company', 'people'],
            'description':
                'Optional bias toward result types. "news" for current '
                    'events, "publication" for scholarly/research content, '
                    '"company" for company pages, "people" for people profiles.',
          },
        },
        'required': ['query', 'type'],
      },
    },
  };

  static const appendBook = {
    'type': 'function',
    'function': {
      'name': 'appendBook',
      'description':
          'Add a new book to the Reading Brain. For Finished books, rating, '
              'personalSignificance, and whyItMatters are required by the handler.',
      'parameters': {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
          'status': {
            'type': 'string',
            'enum': ['Finished', 'Reading', 'Abandoned', 'Want to Read'],
          },
          'rating': {
            'type': 'number',
            'description': '0-5 with half-points',
          },
          'personalSignificance': {
            'type': 'string',
            'description': 'Vocabulary term',
          },
          'whyItMatters': {
            'type': 'string',
            'description': 'Why this book matters to the reader',
          },
          'hardcoverReview': {
            'type': 'string',
            'description': 'Public review, max ~500 chars, no hyphens or em-dashes',
          },
          'hardcoverSpoiler': {'type': 'boolean'},
          'hardcoverId': {'type': 'string'},
          'author': {'type': 'string'},
          'coverUrl': {'type': 'string'},
          'genres': {'type': 'array', 'items': {'type': 'string'}},
          'pages': {'type': 'integer'},
          'hardcoverUrl': {'type': 'string'},
          'dateAdded': {'type': 'string'},
          'dateRead': {'type': 'string'},
          'hardcoverStatus': {'type': 'string'},
          'progress': {'type': 'string', 'description': "e.g. '30%'"},
          'currentImpression': {'type': 'string'},
          'readingStrategy': {'type': 'string'},
          'abandonmentReason': {'type': 'string'},
        },
        'required': ['title', 'status'],
      },
    },
  };

  static const updateBook = {
    'type': 'function',
    'function': {
      'name': 'updateBook',
      'description':
          'Replace an existing book entry by exact title match (targetTitle). '
              'The book object must contain the complete new state.',
      'parameters': {
        'type': 'object',
        'properties': {
          'targetTitle': {
            'type': 'string',
            'description': 'Exact title of the book to replace',
          },
          'book': {
            'type': 'object',
            'properties': {
              'title': {'type': 'string'},
              'status': {
                'type': 'string',
                'enum': [
                  'Finished',
                  'Reading',
                  'Abandoned',
                  'Want to Read'
                ],
              },
              'rating': {
                'type': 'number',
                'description': '0-5 with half-points',
              },
              'personalSignificance': {'type': 'string'},
              'whyItMatters': {'type': 'string'},
              'hardcoverReview': {
                'type': 'string',
                'description': 'Public review, max ~500 chars, no hyphens or em-dashes',
              },
              'hardcoverSpoiler': {'type': 'boolean'},
              'hardcoverId': {'type': 'string'},
              'author': {'type': 'string'},
              'coverUrl': {'type': 'string'},
              'genres': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'pages': {'type': 'integer'},
              'hardcoverUrl': {'type': 'string'},
              'dateAdded': {'type': 'string'},
              'dateRead': {'type': 'string'},
              'hardcoverStatus': {'type': 'string'},
              'progress': {'type': 'string'},
              'currentImpression': {'type': 'string'},
              'readingStrategy': {'type': 'string'},
              'abandonmentReason': {'type': 'string'},
            },
            'required': ['title', 'status'],
          },
        },
        'required': ['targetTitle', 'book'],
      },
    },
  };

  static const deleteBook = {
    'type': 'function',
    'function': {
      'name': 'deleteBook',
      'description': 'Remove a book from the Reading Brain by exact title match.',
      'parameters': {
        'type': 'object',
        'properties': {
          'targetTitle': {
            'type': 'string',
            'description': 'Exact title of the book to delete',
          },
        },
        'required': ['targetTitle'],
      },
    },
  };

  static const patchBrain = {
    'type': 'function',
    'function': {
      'name': 'patchBrain',
      'description':
          'Modify any section of the Reading Brain EXCEPT the book list. For '
              'book operations use appendBook/updateBook/deleteBook. '
              'replacementContent must be the COMPLETE new value — not a diff. '
              'Copy forward every existing value you are not intentionally changing.',
      'parameters': {
        'type': 'object',
        'properties': {
          'targetSection': {
            'type': 'string',
            'enum': [
              'META',
              'READER_PROFILE',
              'READER_PROFILE.CORE_PHILOSOPHY',
              'READER_PROFILE.THINGS_I_CONSISTENTLY_LOVE',
              'READER_PROFILE.NARRATIVE_PREFERENCES',
              'READING_MODES',
              'VOCABULARY',
              'FAVORITE_AUTHORS',
              'FAVORITE_BOOKS',
              'READER_BLIND_SPOTS',
              'READING_EVOLUTION',
              'ACTIVE_QUESTIONS',
              'CURRENT_READING',
              'RECOMMENDATION_QUEUE',
              'OBSERVATIONS',
            ],
          },
          'replacementContent': {
            'description':
                'Complete new value. Type depends on targetSection:\n'
                    '- Object: META, READER_PROFILE, READER_PROFILE.NARRATIVE_PREFERENCES, '
                    'READING_MODES, VOCABULARY, FAVORITE_AUTHORS, FAVORITE_BOOKS, '
                    'READER_BLIND_SPOTS, RECOMMENDATION_QUEUE\n'
                    '- Array: ACTIVE_QUESTIONS, READING_EVOLUTION, OBSERVATIONS\n'
                    '- String: READER_PROFILE.CORE_PHILOSOPHY\n'
                    '- Array of strings: READER_PROFILE.THINGS_I_CONSISTENTLY_LOVE\n'
'- null: CURRENT_READING (to clear), or '
'{book: "Title", hardcoverId?: "id", progress: "30%", '
'readingStrategy: "...", notes: "..."} to set',
          },
          'reason': {'type': 'string'},
          'evidence': {'type': 'string'},
          'confidence': {
            'type': 'number',
            'description':
                '0.9-1.0:Certain, 0.7-0.89:Strong (>=0.8 required for PATCH). '
                    '0.4-0.69:Weak. <0.4: do not log.',
          },
        },
        'required': [
          'targetSection',
          'replacementContent',
          'reason',
          'evidence',
          'confidence',
        ],
      },
    },
  };

  static const logObservation = {
    'type': 'function',
    'function': {
      'name': 'logObservation',
      'description':
          'Silently log a hypothesis about the reader. Not shown to the user. '
              'If 3 observations converge on the same hypothesis, call patchBrain '
              'instead (promotion rule).',
      'parameters': {
        'type': 'object',
        'properties': {
          'evidence': {'type': 'string'},
          'hypothesis': {'type': 'string'},
          'confidence': {
            'type': 'number',
            'description':
                '0.4-0.69 Weak, 0.7-0.89 Strong. Below 0.4 do not log.',
          },
          'logged': {
            'type': 'string',
            'description': 'ISO date e.g. 2026-08-06',
          },
        },
        'required': ['evidence', 'hypothesis', 'confidence', 'logged'],
      },
    },
  };
}
