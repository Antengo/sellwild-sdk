/// Sellwild Flutter SDK — Runnable Sample App
///
/// How to run:
///   1. Create a new Flutter project:
///        flutter create sellwild_demo
///   2. Add the SDK to pubspec.yaml:
///        dependencies:
///          sellwild_sdk: ^1.0.0
///          url_launcher: ^6.2.0
///   3. Run: flutter pub get
///   4. Replace lib/main.dart with this file.
///   5. Add INTERNET permission and NSAllowsArbitraryLoads (see SETUP.md).
///   6. Run: flutter run
///
/// Replace 'YOUR_PARTNER_CODE' with your real partner code from sdk@sellwild.com.
library;

import 'package:flutter/material.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';
import 'package:url_launcher/url_launcher.dart';

// ─── Shared Config ────────────────────────────────────────────────────────────

// ─── TWO PREBID MODES ─────────────────────────────────────────────────────────
//
//  Mode A (default) — Prebid.js client-side in the WebView.
//    Set appBundleId so Prebid.js declares in-app (ortb2.app) inventory.
//
//  Mode B — Prebid Server S2S.
//    Routes all bids server-side through a Prebid Server instance.
//    Solves cookie/IDFA limitations. Uncomment prebidServer below.
//    See sdk/PREBID.md for full setup instructions.

// MODE A — default config (Prebid.js in WebView):
const _config = SellwildConfig(
  partnerCode: 'YOUR_PARTNER_CODE',
  listingsUrl:
      'https://api.sellwild.com/widget/listings?partner=YOUR_PARTNER_CODE&count=20',

  // Required: tells Prebid.js this is in-app traffic (ortb2.app), not web (ortb2.site).
  // Use the actual bundle ID / package name for your app.
  appBundleId: 'com.mycompany.myapp',
  appStoreUrl: 'https://apps.apple.com/app/idXXXXXXXXX',

  // Uncomment to enable Google Ad Manager banner:
  // gamTag: '/12345678/your-ad-unit',

  // Uncomment to enable zone-based banners:
  // bannerZid: '98765',
  // mobileZids: ['11111', '22222'],

  // MODE B — Prebid Server S2S (uncomment to activate):
  // prebidServer: PrebidServerConfig(
  //   accountId: 'YOUR_ACCOUNT_ID',
  //   endpoint: 'https://prebid-server.example.com/openrtb2/auction',
  //   // AppNexus hosted: 'https://prebid.adnxs.com/pbs/v1/openrtb2/auction'
  //   // Rubicon hosted:  'https://prebid-server.rubiconproject.com/openrtb2/auction'
  //   bidders: ['appnexus', 'rubicon', 'ix', 'openx'],
  //   timeout: 1500,
  // ),

  adRefreshMaxMobile: 5,
  adRefreshInterval: Duration(seconds: 30),
  debug: true,
);

// ─── App Entry Point ──────────────────────────────────────────────────────────

void main() {
  runApp(const SellwildSampleApp());
}

class SellwildSampleApp extends StatelessWidget {
  const SellwildSampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sellwild Demo',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

// ─── Main Screen — Bottom Nav ─────────────────────────────────────────────────

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const _pages = [
    _WebViewWidgetPage(),
    _BannerPage(),
    _NativeListingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Widget'),
          NavigationDestination(icon: Icon(Icons.rectangle_outlined), label: 'Banners'),
          NavigationDestination(icon: Icon(Icons.list), label: 'Listings'),
        ],
      ),
    );
  }
}

// ─── Page 1: Full WebView Widget ─────────────────────────────────────────────

class _WebViewWidgetPage extends StatelessWidget {
  const _WebViewWidgetPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sellwild Widget')),
      body: SellwildWidget(
        config: _config,
        onListingTap: (listing) async {
          final url = listing.url;
          if (url != null) {
            final uri = Uri.tryParse(url);
            if (uri != null && await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }
        },
        onAdImpression: (zoneId) {
          debugPrint('[Sellwild] Ad impression zoneId=$zoneId');
        },
        onLoad: () {
          debugPrint('[Sellwild] Widget loaded');
        },
        onError: (error) {
          debugPrint('[Sellwild] Widget error: $error');
        },
      ),
    );
  }
}

// ─── Page 2: Standalone Banner Ads ───────────────────────────────────────────

class _BannerPage extends StatelessWidget {
  const _BannerPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Banner Ads')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 24),
            const Text('320×50 Banner', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SellwildBanner(
              config: _config,
              adSize: SellwildAdSize.banner320x50,
              zoneId: _config.bannerZid ?? 'YOUR_ZONE_ID',
              onImpression: () => debugPrint('[Sellwild] 320x50 impression'),
              onError: (e) => debugPrint('[Sellwild] Banner error: $e'),
            ),
            const SizedBox(height: 32),
            const Text('300×250 MREC', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SellwildBanner(
              config: _config,
              adSize: SellwildAdSize.mrec300x250,
              zoneId: _config.mobileZids.isNotEmpty
                  ? _config.mobileZids.first
                  : 'YOUR_ZONE_ID',
              onImpression: () => debugPrint('[Sellwild] MREC impression'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ─── Page 3: Native Listing Cards ────────────────────────────────────────────

class _NativeListingsPage extends StatefulWidget {
  const _NativeListingsPage();

  @override
  State<_NativeListingsPage> createState() => _NativeListingsPageState();
}

class _NativeListingsPageState extends State<_NativeListingsPage> {
  List<SellwildListing> _listings = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  Future<void> _loadListings({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (forceRefresh) SellwildAPIClient.instance.clearCache();

    try {
      final response = await SellwildAPIClient.instance.fetchListings(_config);
      if (mounted) {
        setState(() {
          _listings = response.listings;
          _loading = false;
        });
      }
    } on SellwildException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Listings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadListings(forceRefresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          // Top banner
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SellwildBanner(
              config: _config,
              adSize: SellwildAdSize.banner320x50,
              zoneId: _config.bannerZid ?? 'YOUR_ZONE_ID',
            ),
          ),

          // Listing grid or state indicators
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text('Failed to load listings',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_error!, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadListings,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_listings.isEmpty) {
      return const Center(child: Text('No listings found'));
    }

    return RefreshIndicator(
      onRefresh: () => _loadListings(forceRefresh: true),
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.75,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _listings.length,
        itemBuilder: (context, index) {
          final listing = _listings[index];
          return SellwildListingCard(
            listing: listing,
            config: _config,
            onTap: (l) async {
              final url = l.url;
              if (url != null) {
                final uri = Uri.tryParse(url);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              }
            },
          );
        },
      ),
    );
  }
}
