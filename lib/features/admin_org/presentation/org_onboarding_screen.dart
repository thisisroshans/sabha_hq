import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../admin_auth/application/auth_controller.dart';
import '../application/org_controller.dart';

/// Shown by AdminScaffold in place of the normal dashboard shell whenever
/// a signed-in admin has no org yet (currentOrgIdProvider resolves to
/// null) — a fresh signup, or an existing account that was never
/// migrated/invited into one. Two ways out: create a new org (self-serve,
/// task #7), or redeem an invite link someone sent them.
class OrgOnboardingScreen extends ConsumerStatefulWidget {
  const OrgOnboardingScreen({super.key});

  @override
  ConsumerState<OrgOnboardingScreen> createState() => _OrgOnboardingScreenState();
}

class _OrgOnboardingScreenState extends ConsumerState<OrgOnboardingScreen> {
  final _orgNameController = TextEditingController();
  final _inviteLinkController = TextEditingController();

  @override
  void dispose() {
    _orgNameController.dispose();
    _inviteLinkController.dispose();
    super.dispose();
  }

  Future<void> _createOrg() async {
    final name = _orgNameController.text.trim();
    if (name.isEmpty) return;

    final success = await ref.read(orgActionControllerProvider.notifier).createOrg(name);
    if (!mounted) return;

    if (!success) {
      final error = ref.read(orgActionControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $error'), backgroundColor: Colors.red),
      );
    }
    // On success, currentOrgIdProvider was invalidated by the controller
    // and re-resolves with the new orgId — AdminScaffold picks that up
    // and swaps this screen out for the real dashboard automatically, no
    // navigation call needed here.
  }

  void _goToInviteLink() {
    final pasted = _inviteLinkController.text.trim();
    if (pasted.isEmpty) return;

    final uri = Uri.tryParse(pasted);
    final orgId = uri?.queryParameters['orgId'];
    final token = uri?.queryParameters['token'];

    if (uri == null || orgId == null || token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("That doesn't look like a valid invite link."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    context.go('/accept-invite?orgId=$orgId&token=$token');
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(orgActionControllerProvider);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Get Started'),
        backgroundColor: const Color(0xFFc51f43),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.apartment, size: 56, color: Color(0xFFc51f43)),
                const SizedBox(height: 16),
                const Text(
                  'Your account isn\'t part of an organization yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Create a new organization',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _orgNameController,
                          decoration: const InputDecoration(
                            labelText: 'Organization Name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: actionState.isLoading ? null : _createOrg,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFc51f43),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: actionState.isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Create Organization'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey[400])),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('OR', style: TextStyle(color: Colors.grey[600])),
                    ),
                    Expanded(child: Divider(color: Colors.grey[400])),
                  ],
                ),
                const SizedBox(height: 24),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Have an invite link?",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "If you clicked the link directly you're already on the right "
                          "page — otherwise paste it here.",
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _inviteLinkController,
                          decoration: const InputDecoration(
                            labelText: 'Paste invite link',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _goToInviteLink,
                            child: const Text('Continue'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
