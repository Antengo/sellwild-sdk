import 'package:flutter/material.dart';

import 'ads_screen.dart';
import 'diagnostics_screen.dart';
import 'feed_screen.dart';
import 'legacy_screen.dart';
import 'listings_screen.dart';
import 'sample_ids.dart';
import 'sample_model.dart';

/// Sellwild Sample: configure at launch, then five tabs.
class SampleApp extends StatelessWidget {
  const SampleApp({super.key, this.model});

  /// Tests pass their own model.
  final SampleModel? model;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Sellwild Sample',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF1565C0)),
        home: _Boot(model: model ?? SampleModel()),
      );
}

/// Runs configure once, then shows the tabs.
class _Boot extends StatefulWidget {
  const _Boot({required this.model});

  final SampleModel model;

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  late final Future<SampleBoot> _boot = widget.model.boot();

  @override
  Widget build(BuildContext context) => FutureBuilder<SampleBoot>(
        future: _boot,
        builder: (context, snapshot) {
          final boot = snapshot.data;
          if (boot != null) return SampleTabs(boot: boot, model: widget.model);
          final text = snapshot.hasError
              ? 'configure failed: ${snapshot.error}'
              : 'Loading Sellwild config';
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!snapshot.hasError) const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(text),
                ],
              ),
            ),
          );
        },
      );
}

/// One tab: its title (the contract's exact text), e2e id, icon and screen.
typedef _Tab = ({
  String title,
  String id,
  IconData icon,
  Widget Function() screen,
});

/// The five tabs. A tab's screen is built the first time it is opened and
/// then kept, so the WebViews of a tab start only when someone opens it.
class SampleTabs extends StatefulWidget {
  const SampleTabs({super.key, required this.boot, required this.model});

  final SampleBoot boot;
  final SampleModel model;

  @override
  State<SampleTabs> createState() => _SampleTabsState();
}

class _SampleTabsState extends State<SampleTabs> {
  int _index = 0;
  final Set<int> _opened = {0};

  late final List<_Tab> _tabs = [
    (
      title: 'Feed',
      id: SampleId.tabFeed,
      icon: Icons.view_agenda_outlined,
      screen: () => FeedScreen(config: widget.boot.config),
    ),
    (
      title: 'Ads',
      id: SampleId.tabAds,
      icon: Icons.campaign_outlined,
      screen: () => AdsScreen(config: widget.boot.config),
    ),
    (
      title: 'Listings',
      id: SampleId.tabListings,
      icon: Icons.list,
      screen: () => ListingsScreen(config: widget.boot.config),
    ),
    (
      title: 'Diagnostics',
      id: SampleId.tabDiagnostics,
      icon: Icons.monitor_heart_outlined,
      screen: () => DiagnosticsScreen(
            boot: widget.boot,
            failureCodes: widget.model.failureCodes,
          ),
    ),
    (
      title: 'Legacy',
      id: SampleId.tabLegacy,
      icon: Icons.public,
      screen: () => LegacyScreen(config: widget.boot.config),
    ),
  ];

  void _select(int index) => setState(() {
        _index = index;
        _opened.add(index);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < _tabs.length; i++)
              _opened.contains(i) ? _tabs[i].screen() : const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [
          for (var i = 0; i < _tabs.length; i++)
            // One node per tab button, with the tab's id and title. The
            // button's own semantics are replaced by this node's.
            Semantics(
              container: true,
              identifier: _tabs[i].id,
              label: _tabs[i].title,
              button: true,
              selected: i == _index,
              onTap: () => _select(i),
              excludeSemantics: true,
              child: NavigationDestination(
                icon: Icon(_tabs[i].icon),
                label: _tabs[i].title,
              ),
            ),
        ],
      ),
    );
  }
}
