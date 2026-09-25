// nonObjectPhotoCount (lib/src/listing_json.dart): how many photos entries
// SellwildListing.fromJson skips, for fetchListings and the widget bridge
// to report (listings.item.invalid).

import 'package:flutter_test/flutter_test.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';
import 'package:sellwild_sdk/src/listing_json.dart';

import 'factories/shape_factories.dart';

void main() {
  final listings = ListingFactory();

  test('every entry that is not an object is counted, whatever its kind', () {
    expect(nonObjectPhotoCount(listings.photoNotObject()), 1);
    expect(nonObjectPhotoCount(listings.photosNotObject(2)), 2);
    // A number, null and an array: not only text.
    expect(nonObjectPhotoCount(listings.photosOfOtherKinds()), 3);
  });

  test('the count is what fromJson skips', () {
    for (final item in [
      listings.photoNotObject(),
      listings.photosNotObject(2),
      listings.photosOfOtherKinds(),
    ]) {
      final photos = item['photos'] as List;

      final listing = SellwildListing.fromJson(item);

      expect(listing.photos.length, photos.length - nonObjectPhotoCount(item));
    }
  });

  test('0 for clean photos, no photos, or photos that are not a list', () {
    expect(nonObjectPhotoCount(listings.build()), 0);
    expect(nonObjectPhotoCount(listings.noPhotos()), 0);
    expect(nonObjectPhotoCount(listings.withoutPhotos()), 0);
    expect(nonObjectPhotoCount(listings.photosNotArray()), 0);
  });
}
