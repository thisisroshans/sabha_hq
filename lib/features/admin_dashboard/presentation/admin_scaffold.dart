import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../admin_auth/application/auth_controller.dart';

class AdminScaffold extends ConsumerWidget {
  final Widget child;

  const AdminScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Determine the current path to highlight the correct menu item
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = location.contains('guests')
        ? 1
        : location.contains('analytics')
        ? 2
        : 0;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: true,
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) {
              if (index == 0) context.go('/dashboard/events');
              if (index == 1) context.go('/dashboard/guests');
              if (index == 2) context.go('/dashboard/analytics');
            },
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.event),
                label: Text('Events'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.people),
                label: Text('Guests'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.analytics),
                label: Text('Analytics'),
              ),
            ],
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: TextButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                    onPressed: () {
                      // Trigger the real Firebase logout
                      ref.read(authControllerProvider.notifier).logout();
                    },
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          // The 'child' is the injected screen (Events or Analytics)
          Expanded(child: child),
        ],
      ),
    );
  }
}
