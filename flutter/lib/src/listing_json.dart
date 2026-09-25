// Pure checks on a raw listing item (contracts/schemas/listing.schema.json)
// for what SellwildListing.fromJson skips without saying so. Its callers
// report what these find: fetchListings and the SellwildWidget bridge.

/// How many `photos` entries of [item] are not objects: fromJson skips
/// them. 0 when `photos` is absent or not a list (fromJson then reads no
/// photos, or cannot read the item at all).
int nonObjectPhotoCount(Map<String, dynamic> item) {
  final photos = item['photos'];
  if (photos is! List) return 0;
  return photos.where((photo) => photo is! Map<String, dynamic>).length;
}
