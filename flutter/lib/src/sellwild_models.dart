// Sellwild domain models

class SellwildPhoto {
  final String url;
  final String thumbUrl;
  final String? background;

  const SellwildPhoto({
    required this.url,
    required this.thumbUrl,
    this.background,
  });

  factory SellwildPhoto.fromJson(Map<String, dynamic> json) => SellwildPhoto(
        url: _text(json['url']) ?? '',
        thumbUrl: _text(json['thumbUrl']) ?? '',
        background: _text(json['background']),
      );
}

class SellwildUser {
  final String id;
  final String firstName;
  final String lastName;
  final String username;
  final String membershipType;
  final String trustLevel;

  const SellwildUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.membershipType,
    required this.trustLevel,
  });

  factory SellwildUser.fromJson(Map<String, dynamic> json) => SellwildUser(
        id: _text(json['id']) ?? '',
        firstName: _text(json['firstName']) ?? '',
        lastName: _text(json['lastName']) ?? '',
        username: _text(json['username']) ?? '',
        membershipType: _text(json['membershipType']) ?? '',
        trustLevel: _text(json['trustLevel']) ?? '',
      );
}

class SellwildListing {
  final String id;
  final String status;
  final String title;
  final String? text;
  final String? url;
  final String? categoryId;
  final String? currency;
  final String? price;
  final String? strikePrice;
  final bool hasPhoto;
  final List<SellwildPhoto> photos;
  final String? createdDate;
  final String? shippable;
  final String? dataSourceId;
  final SellwildUser? user;
  final double? distance;

  const SellwildListing({
    required this.id,
    required this.status,
    required this.title,
    this.text,
    this.url,
    this.categoryId,
    this.currency,
    this.price,
    this.strikePrice,
    this.hasPhoto = false,
    this.photos = const [],
    this.createdDate,
    this.shippable,
    this.dataSourceId,
    this.user,
    this.distance,
  });

  factory SellwildListing.fromJson(Map<String, dynamic> json) {
    final photosJson = json['photos'] as List? ?? [];
    final photos = photosJson
        .whereType<Map<String, dynamic>>()
        .map(SellwildPhoto.fromJson)
        .toList();

    final userJson = json['user'] as Map<String, dynamic>?;

    return SellwildListing(
      id: _text(json['id']) ?? '',
      status: _text(json['status']) ?? '',
      title: _text(json['title']) ?? '',
      text: _text(json['text']),
      url: _text(json['url']),
      categoryId: _text(json['categoryId']),
      currency: _text(json['currency']),
      price: _text(json['price']),
      strikePrice: _text(json['strikePrice']),
      hasPhoto: _flag(json['has_photo']),
      photos: photos,
      createdDate: _text(json['createdDate']),
      shippable: _text(json['shippable']),
      dataSourceId: _text(json['dataSourceId']),
      user: userJson != null ? SellwildUser.fromJson(userJson) : null,
      distance: _number(json['distance']),
    );
  }

  String? get displayPrice {
    final value = double.tryParse(price ?? '');
    if (value == null || value <= 0) return null;
    return value.toStringAsFixed(0);
  }

  SellwildPhoto? get primaryPhoto => photos.isNotEmpty ? photos.first : null;
}

class SellwildListingsResponse {
  final List<SellwildListing> listings;
  final Map<String, dynamic> config;
  final String? widgetCacheVersionId;

  const SellwildListingsResponse({
    required this.listings,
    required this.config,
    this.widgetCacheVersionId,
  });
}

// Real listings caches send some fields with other JSON types than the model
// uses (contracts/schemas/listing.schema.json): bool `shippable` on the
// primary caches, numeric `price`/`strikePrice` on bargainhunter, numeric
// ids from JSON-RPC. fromJson reads text, numbers and bools as text instead of
// throwing. Any other type (an object or array where a scalar belongs, a
// `user` that is not an object, `photos` that is not an array) still throws
// TypeError; fetchListings reports that item and drops it.

String? _text(Object? v) => switch (v) {
      num() || bool() => '$v',
      _ => v as String?,
    };

// has_photo: a bool, a number (any non-zero value, NaN included, is true) or
// the text 'true'/'1' (trimmed, any case). Absent is false.
bool _flag(Object? v) => switch (v) {
      num() => v != 0,
      String() => const ['true', '1'].contains(v.trim().toLowerCase()),
      _ => v as bool? ?? false,
    };

// distance: a number, or text that parses as one (other text is null, as
// displayPrice treats price).
double? _number(Object? v) => switch (v) {
      String() => double.tryParse(v),
      _ => (v as num?)?.toDouble(),
    };
