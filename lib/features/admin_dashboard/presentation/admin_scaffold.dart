import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sabha_hq/core/providers/current_org_provider.dart';
import 'package:sabha_hq/core/providers/platform_role_provider.dart';
import 'package:sabha_hq/features/admin_dashboard/application/live_feed_providers.dart';
import 'package:sabha_hq/features/admin_org/presentation/org_onboarding_screen.dart';
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
          backgroundColor: const Color(0xFFc51f43),
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
    if (location.contains('/team')) return 4;
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

      case 4:
        context.go('/dashboard/team');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final orgIdState = ref.watch(currentOrgIdProvider);

    // Every child screen under /dashboard assumes a resolved org — rather
    // than have each one separately handle "org still loading" / "no org
    // at all", gate here once. See lib/core/providers/current_org_provider.dart.
    if (orgIdState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (orgIdState.hasError) {
      return Scaffold(
        body: Center(child: Text('Error loading account: ${orgIdState.error}')),
      );
    }
    if (orgIdState.value == null) {
      // A Sabha HQ platform-staff account (functions/scripts/grant-
      // platform-staff.js) has no orgId at all — it doesn't belong to
      // any org. Without this check they'd land on "create an
      // organization or accept an invite", which is wrong for them; send
      // them to their actual dashboard instead. Deferred to a post-frame
      // callback since navigating during build isn't safe.
      final platformRoleState = ref.watch(platformRoleProvider);
      if (platformRoleState.value == 'owner') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/platform');
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (platformRoleState.isLoading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return const OrgOnboardingScreen();
    }

    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _getSelectedIndex(location);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800; // Breakpoint for mobile

        return Scaffold(
          // Mobile Bottom Navigation Bar
          bottomNavigationBar: isMobile
              ? NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) async {
                    // Add Logout as the 6th item on mobile
                    if (index == 5) {
                      await ref.read(authControllerProvider.notifier).logout();
                      return;
                    }
                    _onDestinationSelected(context, index);
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.event_outlined),
                      selectedIcon: Icon(Icons.event),
                      label: 'Events',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.people_outline),
                      selectedIcon: Icon(Icons.people),
                      label: 'Guests',
                    ),
                    NavigationDestination(
                      icon: Badge(
                        backgroundColor: Colors.redAccent,
                        smallSize: 8,
                        child: Icon(Icons.sensors),
                      ),
                      label: 'Live',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.analytics_outlined),
                      selectedIcon: Icon(Icons.analytics),
                      label: 'Analytics',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.groups_outlined),
                      selectedIcon: Icon(Icons.groups),
                      label: 'Team',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.logout),
                      label: 'Logout',
                    ),
                  ],
                )
              : null,
          body: SafeArea(
            child: Row(
              children: [
                // Desktop/Tablet Navigation Rail
                if (!isMobile) ...[
                  NavigationRail(
                    extended:
                        constraints.maxWidth >
                        1000, // Collapse on medium screens
                    minExtendedWidth: 220,
                    selectedIndex: selectedIndex,
                    groupAlignment: -0.9,
                    onDestinationSelected: (index) =>
                        _onDestinationSelected(context, index),
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Image.asset('assets/logo.jpeg', height: 80),
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
                      NavigationRailDestination(
                        icon: Icon(Icons.groups_outlined),
                        selectedIcon: Icon(Icons.groups),
                        label: Text('Team'),
                      ),
                    ],
                    trailing: Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: IconButton(
                            icon: const Icon(Icons.logout),
                            tooltip: 'Logout',
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
                ],

                /// Main Screen Content
                Expanded(
                  child: Column(
                    children: [
                      _SuspensionBanner(),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: widget.child,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Shown across every /dashboard screen when a Sabha HQ platform owner has
/// suspended this org (org_detail_screen.dart's Suspend button) — reads
/// stay open on a suspended org specifically so this can render instead
/// of every write silently failing with no explanation. Renders nothing
/// while active, so it's zero-height and invisible the vast majority of
/// the time.
class _SuspensionBanner extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusState = ref.watch(currentOrgStatusProvider);
    if (statusState.valueOrNull != 'suspended') return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: Colors.red[700],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Row(
        children: [
          Icon(Icons.block, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Your organization is currently suspended — creating events, inviting '
              'members, and guest check-in are paused. Contact Sabha HQ for details.',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
