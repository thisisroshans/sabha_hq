import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sabha_hq/features/admin_auth/application/auth_controller.dart';
import '../application/platform_providers.dart';
import 'platform_gate.dart';

class OrgDirectoryScreen extends ConsumerStatefulWidget {
  const OrgDirectoryScreen({super.key});

  @override
  ConsumerState<OrgDirectoryScreen> createState() => _OrgDirectoryScreenState();
}

class _OrgDirectoryScreenState extends ConsumerState<OrgDirectoryScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overviewState = ref.watch(platformOverviewProvider);

    return PlatformGate(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sabha HQ — Platform'),
          backgroundColor: const Color(0xFFc51f43),
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(platformOverviewProvider),
            ),
            IconButton(
              tooltip: 'Audit Log',
              icon: const Icon(Icons.history),
              onPressed: () => context.go('/platform/audit-log'),
            ),
            IconButton(
              tooltip: 'Logout',
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            ),
          ],
        ),
        body: overviewState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error loading orgs: $e')),
          data: (orgs) {
            final filtered = _query.isEmpty
                ? orgs
                : orgs.where((o) => o.name.toLowerCase().contains(_query.toLowerCase())).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            labelText: 'Search organizations',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (val) => setState(() => _query = val),
                        ),
                      ),
                      const SizedBox(width: 16),
                      _OverviewStat(label: 'Orgs', value: orgs.length.toString()),
                      const SizedBox(width: 16),
                      _OverviewStat(
                        label: 'Events',
                        value: orgs.fold<int>(0, (sum, o) => sum + o.usage.eventCount).toString(),
                      ),
                      const SizedBox(width: 16),
                      _OverviewStat(
                        label: 'Attendees',
                        value: orgs.fold<int>(0, (sum, o) => sum + o.usage.attendeeCount).toString(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('No organizations found.'))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final org = filtered[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: org.isSuspended ? Colors.red : const Color(0xFFc51f43),
                                child: Icon(
                                  org.isSuspended ? Icons.block : Icons.apartment,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                              title: Text(org.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                '${org.plan.toUpperCase()} • '
                                '${org.usage.eventCount} event${org.usage.eventCount == 1 ? '' : 's'} • '
                                '${org.usage.teamMemberCount}/${org.limits.maxTeamMembers} seats • '
                                '${org.usage.attendeeCount} attendees'
                                '${org.isSuspended ? ' • SUSPENDED' : ''}',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.go('/platform/orgs/${org.id}'),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  final String label;
  final String value;
  const _OverviewStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}
