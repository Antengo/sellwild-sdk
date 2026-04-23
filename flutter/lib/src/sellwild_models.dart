/// Sellwild domain models

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
        url: json['url'] as String? ?? '',
        thumbUrl: json['thumbUrl'] as String? ?? '',
        background: json['background'] as String?,
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
        id: json['id'] as String? ?? '',
        firstName: json['firstName'] as String? ?? '',
        lastName: json['lastName'] as String? ?? '',
        username: json['username'] as String? ?? '',
        membershipType: json['membershipType'] as String? ?? '',
        trustLevel: json['trustLevel'] as String? ?? '',
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
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      title: json['title'] as String? ?? '',
      text: json['text'] as String?,
      url: json['url'] as String?,
      categoryId: json['categoryId'] as String?,
      currency: json['currency'] as String?,
      price: json['price'] as String?,
      strikePrice: json['strikePrice'] as String?,
      hasPhoto: json['has_photo'] as bool? ?? false,
      photos: photos,
      createdDate: json['createdDate'] as String?,
      shippable: json['shippable'] as String?,
      dataSourceId: json['dataSourceId'] as String?,
      user: userJson != null ? SellwildUser.fromJson(userJson) : null,
      distance: (json['distance'] as num?)?.toDouble(),
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
