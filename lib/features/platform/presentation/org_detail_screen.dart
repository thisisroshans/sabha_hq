import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sabha_hq/core/models/event.dart';
import '../application/platform_models.dart';
import '../application/platform_providers.dart';
import 'platform_gate.dart';

class OrgDetailScreen extends ConsumerWidget {
  final String orgId;
  const OrgDetailScreen({super.key, required this.orgId});

  Future<void> _showEditLimitsDialog(BuildContext context, WidgetRef ref, OrgLimits current) async {
    final maxTeamMembers = TextEditingController(text: current.maxTeamMembers.toString());
    final maxEvents = TextEditingController(text: current.maxEvents.toString());
    final maxAttendeesPerEvent = TextEditingController(text: current.maxAttendeesPerEvent.toString());
    final checkInRateLimit = TextEditingController(text: current.checkInRateLimitPerMinute.toString());

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Limits'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: maxTeamMembers,
                decoration: const InputDecoration(labelText: 'Max team members (seats)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: maxEvents,
                decoration: const InputDecoration(labelText: 'Max events'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: maxAttendeesPerEvent,
                decoration: const InputDecoration(labelText: 'Max attendees per event'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: checkInRateLimit,
                decoration: const InputDecoration(labelText: 'Check-in attempts / minute'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final parsed = <String, int>{};
              for (final entry in {
                'maxTeamMembers': maxTeamMembers.text,
                'maxEvents': maxEvents.text,
                'maxAttendeesPerEvent': maxAttendeesPerEvent.text,
                'checkInRateLimitPerMinute': checkInRateLimit.text,
              }.entries) {
                final value = int.tryParse(entry.value);
                if (value == null || value < 1) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('${entry.key} must be a positive whole number.')),
                  );
                  return;
                }
                parsed[entry.key] = value;
              }

              final success = await ref.read(platformActionControllerProvider.notifier).updateLimits(orgId, parsed);
              if (!dialogContext.mounted) return;
              if (success) {
                Navigator.pop(dialogContext);
              } else {
                final error = ref.read(platformActionControllerProvider).error;
                ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Error: $error')));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmToggleStatus(BuildContext context, WidgetRef ref, OrgSummary org) async {
    final suspending = !org.isSuspended;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(suspending ? 'Suspend Organization?' : 'Reactivate Organization?'),
        content: Text(
          suspending
              ? '${org.name} will be blocked from creating events, inviting members, or accepting check-ins. '
                  "They'll still be able to sign in and see their own dashboard."
              : '${org.name} will regain full access.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: suspending ? Colors.red : Colors.green),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(suspending ? 'Suspend' : 'Reactivate'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    final success = await ref
        .read(platformActionControllerProvider.notifier)
        .setStatus(orgId, suspending ? 'suspended' : 'active');
    if (!context.mounted) return;
    if (!success) {
      final error = ref.read(platformActionControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $error')));
    }
  }

  void _showEventAttendees(BuildContext context, WidgetRef ref, Event event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          expand: false,
          builder: (context, scrollController) {
            final attendeesState = ref.watch(
              platformEventAttendeesProvider((orgId: orgId, eventId: event.id)),
            );
            return attendeesState.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (attendees) => ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: attendees.length + 1,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${event.title} — ${attendees.length} attendee${attendees.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    );
                  }
                  final a = attendees[index - 1];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      a.isCheckedIn ? Icons.check_circle : Icons.circle_outlined,
                      color: a.isCheckedIn ? Colors.green : Colors.grey,
                      size: 20,
                    ),
                    title: Text(a.name),
                    subtitle: Text('${a.role} • ${a.companyName.isNotEmpty ? a.companyName : 'no company on file'}'),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailState = ref.watch(orgDetailProvider(orgId));

    return PlatformGate(
      child: DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/platform'),
            ),
            title: detailState.maybeWhen(data: (org) => Text(org.name), orElse: () => const Text('Organization')),
            backgroundColor: const Color(0xFFc51f43),
            foregroundColor: Colors.white,
            bottom: const TabBar(
              indicatorColor: Colors.white,
              tabs: [
                Tab(text: 'Overview'),
                Tab(text: 'Events'),
                Tab(text: 'Team'),
                Tab(text: 'Audit Log'),
              ],
            ),
          ),
          body: detailState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error loading organization: $e')),
            data: (org) {
              return TabBarView(
                children: [
                  _OverviewTab(
                    org: org,
                    onEditLimits: () => _showEditLimitsDialog(context, ref, org.limits),
                    onToggleStatus: () => _confirmToggleStatus(context, ref, org),
                  ),
                  _EventsTab(orgId: orgId, onTapEvent: (event) => _showEventAttendees(context, ref, event)),
                  _TeamTab(orgId: orgId),
                  _AuditLogTab(orgId: orgId),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final OrgSummary org;
  final VoidCallback onEditLimits;
  final VoidCallback onToggleStatus;

  const _OverviewTab({required this.org, required this.onEditLimits, required this.onToggleStatus});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (org.isSuspended)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8)),
            child: const Row(
              children: [
                Icon(Icons.block, color: Colors.red),
                SizedBox(width: 8),
                Expanded(child: Text('This organization is suspended.', style: TextStyle(color: Colors.red))),
              ],
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Plan: ${org.plan.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ElevatedButton.icon(
                      onPressed: onToggleStatus,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: org.isSuspended ? Colors.green : Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      icon: Icon(org.isSuspended ? Icons.play_arrow : Icons.block),
                      label: Text(org.isSuspended ? 'Reactivate' : 'Suspend'),
                    ),
                  ],
                ),
                if (org.createdAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Created ${DateFormat('MMM d, yyyy').format(org.createdAt!)}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Usage & Limits', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    TextButton.icon(onPressed: onEditLimits, icon: const Icon(Icons.edit), label: const Text('Edit')),
                  ],
                ),
                const SizedBox(height: 8),
                _UsageRow('Team members (seats)', org.usage.teamMemberCount, org.limits.maxTeamMembers),
                _UsageRow('Events', org.usage.eventCount, org.limits.maxEvents),
                _UsageRow('Attendees (across all events)', org.usage.attendeeCount, null),
                const Divider(),
                Text(
                  'Max attendees per event: ${org.limits.maxAttendeesPerEvent}',
                  style: const TextStyle(fontSize: 13),
                ),
                Text(
                  'Check-in rate limit: ${org.limits.checkInRateLimitPerMinute}/minute',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _UsageRow extends StatelessWidget {
  final String label;
  final int used;
  final int? limit;
  const _UsageRow(this.label, this.used, this.limit);

  @override
  Widget build(BuildContext context) {
    final overLimit = limit != null && used >= limit!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            limit != null ? '$used / $limit' : '$used',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: overLimit ? Colors.red : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventsTab extends ConsumerWidget {
  final String orgId;
  final void Function(Event event) onTapEvent;
  const _EventsTab({required this.orgId, required this.onTapEvent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsState = ref.watch(platformOrgEventsProvider(orgId));

    return eventsState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (events) {
        if (events.isEmpty) return const Center(child: Text('No events yet.'));
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: events.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final event = events[index];
            return ListTile(
              title: Text(event.title),
              subtitle: Text('${DateFormat('MMM d, yyyy').format(event.date)} • ${event.location}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onTapEvent(event),
            );
          },
        );
      },
    );
  }
}

class _TeamTab extends ConsumerWidget {
  final String orgId;
  const _TeamTab({required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersState = ref.watch(platformOrgMembersProvider(orgId));

    return membersState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (members) {
        if (members.isEmpty) return const Center(child: Text('No team members yet.'));
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: members.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final member = members[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFc51f43),
                child: Text(
                  member.email.isNotEmpty ? member.email[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(member.email.isNotEmpty ? member.email : member.uid),
              trailing: Chip(label: Text(member.role.toUpperCase())),
            );
          },
        );
      },
    );
  }
}

class _AuditLogTab extends ConsumerWidget {
  final String orgId;
  const _AuditLogTab({required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logState = ref.watch(platformAuditLogProvider(orgId));

    return logState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (entries) {
        if (entries.isEmpty) return const Center(child: Text('No platform actions on this org yet.'));
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return ListTile(
              leading: const Icon(Icons.history),
              title: Text(entry.action),
              subtitle: Text(entry.details.toString()),
              trailing: entry.at != null
                  ? Text(DateFormat('MMM d, h:mm a').format(entry.at!), style: const TextStyle(fontSize: 11))
                  : null,
            );
          },
        );
      },
    );
  }
}
