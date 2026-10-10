import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/url_utils.dart';
import '../state/app_state.dart';
import 'screens/friends_screen.dart';
import 'screens/home_screen.dart';
import 'screens/inbox_screen.dart';
import 'screens/search_screen.dart';
import 'sheets/add_link_sheet.dart';

/// Bottom-nav shell. Tabs keep their state (IndexedStack); folders and boards open
/// as routes on top, so Back always lands on the tab you came from.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _showingShare = false;
  late final AppState _state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state = context.read<AppState>();
    _state.addListener(_onStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onStateChanged());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _state.removeListener(_onStateChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _state.onResumed();
  }

  void _onStateChanged() {
    if (!mounted) return;
    final flash = _state.takeFlash();
    if (flash != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(flash)));
    }
    _showNextSharedLink();
  }

  /// Links shared with "Choose collection" open the picker as soon as the app is visible.
  Future<void> _showNextSharedLink() async {
    if (_showingShare) return;
    final share = _state.takeChooseRequest();
    if (share == null) return;
    _showingShare = true;
    await showAddLinkSheet(
      context,
      initialUrl: share.url,
      initialTitle: titleFromShareText(share.text, share.url),
      fromShare: true,
    );
    _showingShare = false;
    if (mounted) _showNextSharedLink();
  }

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final waiting = context.select<AppState, int>((s) => s.newItems.length);
    return Scaffold(
      body: IndexedStack(index: _index, children: [
        HomeScreen(onOpenSearch: () => _go(1), onOpenInbox: () => _go(2)),
        const SearchScreen(),
        const InboxScreen(),
        const FriendsScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          const NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Search'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: waiting > 0,
              label: Text('$waiting'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
            selectedIcon: Badge(
              isLabelVisible: waiting > 0,
              label: Text('$waiting'),
              child: const Icon(Icons.notifications_rounded),
            ),
            label: 'New',
          ),
          const NavigationDestination(
              icon: Icon(Icons.group_outlined), selectedIcon: Icon(Icons.group_rounded), label: 'Friends'),
        ],
      ),
    );
  }
}
