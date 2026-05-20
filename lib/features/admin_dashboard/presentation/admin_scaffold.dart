import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sabha_hq/features/admin_dashboard/application/live_feed_providers.dart';
import '../../admin_auth/application/auth_controller.dart';

class AdminScaffold extends ConsumerStatefulWidget {
  final Widget child;

  const AdminScaffold({super.key, required this.child});

  @override
  ConsumerState<AdminScaffold> createState() => _AdminScaffoldState();
}

class _AdminScaffoldState extends ConsumerState<AdminScaffold> {
  @override
  void initState() {
    super.initState();

    /// Listen once during widget lifecycle
    /// Prevents duplicate listeners on rebuilds
    ref.listenManual(liveActivityStreamProvider, (previous, next) {
      final previousList = previous?.value ?? [];
      final nextList = next.value ?? [];

      /// No new data
      if (nextList.isEmpty) return;

      /// Detect newly checked-in guest
      final hasNewCheckIn =
          previousList.isEmpty || previousList.first.id != nextList.first.id;

      if (!hasNewCheckIn) return;

      final newGuest = nextList.first;

      /// Prevent snackbar errors if widget is disposed
      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);

      /// Remove old snackbar before showing new one
      messenger.clearSnackBars();

      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(20),
          backgroundColor: Colors.deepPurple,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.flash_on,
                  color: Colors.yellow,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  '${newGuest.name} just checked in!',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  int _getSelectedIndex(String location) {
    if (location.contains('/guests')) return 1;
    if (location.contains('/live')) return 2;
    if (location.contains('/analytics')) return 3;
    return 0;
  }

  void _onDestinationSelected(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/dashboard/events');
        break;

      case 1:
        context.go('/dashboard/guests');
        break;

      case 2:
        context.go('/dashboard/live');
        break;

      case 3:
        context.go('/dashboard/analytics');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _getSelectedIndex(location);

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              extended: true,
              minExtendedWidth: 220,
              selectedIndex: selectedIndex,
              groupAlignment: -0.9,
              onDestinationSelected: (index) =>
                  _onDestinationSelected(context, index),
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    Icon(
                      Icons.event_available,
                      size: 34,
                      color: Colors.deepPurple,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Sabha HQ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.event_outlined),
                  selectedIcon: Icon(Icons.event),
                  label: Text('Events'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.people_outline),
                  selectedIcon: Icon(Icons.people),
                  label: Text('Guests'),
                ),
                NavigationRailDestination(
                  icon: Badge(
                    backgroundColor: Colors.redAccent,
                    smallSize: 8,
                    child: Icon(Icons.sensors),
                  ),
                  selectedIcon: Badge(
                    backgroundColor: Colors.redAccent,
                    child: Icon(Icons.sensors),
                  ),
                  label: Text('Live Feed'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.analytics_outlined),
                  selectedIcon: Icon(Icons.analytics),
                  label: Text('Analytics'),
                ),
              ],
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: FilledButton.icon(
                      icon: const Icon(Icons.logout),
                      label: const Text('Logout'),
                      onPressed: () async {
                        await ref
                            .read(authControllerProvider.notifier)
                            .logout();
                      },
                    ),
                  ),
                ),
              ),
            ),

            const VerticalDivider(width: 1),

            /// Main Screen
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: widget.child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
