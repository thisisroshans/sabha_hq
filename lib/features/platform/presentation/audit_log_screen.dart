import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../application/platform_providers.dart';
import 'platform_gate.dart';

/// Every platform action across every org — the org-scoped version of
/// this same log lives as a tab on OrgDetailScreen.
class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logState = ref.watch(platformAuditLogProvider(null));

    return PlatformGate(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/platform'),
          ),
          title: const Text('Platform Audit Log'),
          backgroundColor: const Color(0xFFc51f43),
          foregroundColor: Colors.white,
        ),
        body: logState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (entries) {
            if (entries.isEmpty) return const Center(child: Text('No platform actions yet.'));
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(entry.action),
                  subtitle: Text(
                    '${entry.orgId ?? '(no org)'} • ${entry.details}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: entry.at != null
                      ? Text(DateFormat('MMM d, h:mm a').format(entry.at!), style: const TextStyle(fontSize: 11))
                      : null,
                  onTap: entry.orgId != null ? () => context.go('/platform/orgs/${entry.orgId}') : null,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
