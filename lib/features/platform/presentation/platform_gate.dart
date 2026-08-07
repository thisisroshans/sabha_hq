import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sabha_hq/core/providers/platform_role_provider.dart';
import 'package:sabha_hq/features/admin_auth/application/auth_controller.dart';

/// Wraps every /platform/* screen. app_router.dart's redirect only checks
/// "is this an authenticated admin-type account" (same coarse check as
/// /dashboard) — the actual "are they specifically Sabha HQ platform
/// staff" check happens here, same architectural split as AdminScaffold
/// gating on currentOrgIdProvider rather than the router doing async
/// claim resolution.
class PlatformGate extends ConsumerWidget {
  final Widget child;
  const PlatformGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleState = ref.watch(platformRoleProvider);

    return roleState.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Error checking access: $e')),
      ),
      data: (role) {
        if (role != 'owner') {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 56, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    "You don't have access to the Sabha HQ platform dashboard.",
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => context.go('/dashboard/events'),
                    child: const Text('Go to my dashboard'),
                  ),
                  TextButton(
                    onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                    child: const Text('Logout'),
                  ),
                ],
              ),
            ),
          );
        }
        return child;
      },
    );
  }
}
