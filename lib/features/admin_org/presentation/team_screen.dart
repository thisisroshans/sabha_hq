import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/providers/current_org_provider.dart';
import '../application/team_providers.dart';

class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  void _showInviteDialog(BuildContext context, WidgetRef ref) {
    final emailController = TextEditingController();
    String selectedRole = 'staff';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Invite Team Member'),
            // Scrollable so the open keyboard on a phone can't push the
            // role picker and buttons off-screen (overflow).
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Email Address'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: 'staff', child: Text('Staff')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'owner', child: Text('Owner')),
                  ],
                  onChanged: (val) => setDialogState(() => selectedRole = val ?? 'staff'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final email = emailController.text.trim();
                  if (email.isEmpty || !email.contains('@')) return;

                  final link = await ref
                      .read(inviteControllerProvider.notifier)
                      .createInvite(email: email, role: selectedRole);

                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);

                  if (link == null) {
                    final error = ref.read(inviteControllerProvider).error;
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $error'), backgroundColor: Colors.red),
                      );
                    }
                    return;
                  }

                  if (context.mounted) {
                    _showInviteLinkDialog(context, link);
                  }
                },
                child: const Text('Send Invite'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showInviteLinkDialog(BuildContext context, String link) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite Created'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "No email is sent automatically yet — share this link with "
              "them directly (it expires in 7 days):",
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(link, style: const TextStyle(fontSize: 12)),
                  ),
                  IconButton(
                    tooltip: 'Copy Link',
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: link));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied!'), backgroundColor: Colors.green),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersState = ref.watch(teamMembersProvider);
    final roleState = ref.watch(currentRoleProvider);
    final canInvite = roleState.valueOrNull == 'owner' || roleState.valueOrNull == 'admin';

    return Scaffold(
      appBar: AppBar(title: const Text('Team')),
      body: membersState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (members) {
          if (members.isEmpty) {
            return const Center(child: Text('No team members found.'));
          }
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
      ),
      floatingActionButton: canInvite
          ? FloatingActionButton.extended(
              onPressed: () => _showInviteDialog(context, ref),
              icon: const Icon(Icons.person_add),
              label: const Text('Invite'),
            )
          : null,
    );
  }
}
