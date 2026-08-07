import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../admin_auth/application/auth_controller.dart';
import '../application/team_providers.dart';

/// Reached via a link like /accept-invite?orgId=X&token=Y — shared out of
/// band by an owner/admin from the Team screen, since no transactional
/// email exists yet (functions/src/invites.ts's createInvite just returns
/// the token/link; sending it is the inviter's job for now).
///
/// The invite doc itself is locked down to Admin-SDK-only reads
/// (firestore.rules) — this screen can't pre-fetch "you were invited as
/// x@example.com" to show before accepting. It just asks the visitor to
/// sign in (or create an account) and lets the server-side email check in
/// acceptInviteHandler be the source of truth, surfacing its error if it
/// doesn't match.
class AcceptInviteScreen extends ConsumerStatefulWidget {
  final String? orgId;
  final String? token;

  const AcceptInviteScreen({super.key, required this.orgId, required this.token});

  @override
  ConsumerState<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends ConsumerState<AcceptInviteScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isNewAccount = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInOrSignUpThenAccept() async {
    if (!_formKey.currentState!.validate()) return;

    final authNotifier = ref.read(authControllerProvider.notifier);
    if (_isNewAccount) {
      await authNotifier.signup(_emailController.text.trim(), _passwordController.text.trim());
    } else {
      await authNotifier.login(_emailController.text.trim(), _passwordController.text.trim());
    }

    if (!mounted) return;
    if (ref.read(authControllerProvider).hasError) return; // error shown inline below

    await _accept();
  }

  Future<void> _accept() async {
    final orgId = widget.orgId;
    final token = widget.token;
    if (orgId == null || token == null) return;

    final success = await ref
        .read(acceptInviteControllerProvider.notifier)
        .acceptInvite(orgId: orgId, token: token);

    if (!mounted) return;

    if (success) {
      context.go('/dashboard/events');
    } else {
      final error = ref.read(acceptInviteControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $error'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.orgId == null || widget.token == null) {
      return const Scaffold(
        body: Center(child: Text('Invalid invite link.')),
      );
    }

    final user = ref.watch(authStateProvider).valueOrNull;
    final authState = ref.watch(authControllerProvider);
    final acceptState = ref.watch(acceptInviteControllerProvider);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 24, offset: const Offset(0, 8)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.groups, size: 56, color: Color(0xFFc51f43)),
                const SizedBox(height: 16),
                const Text(
                  "You've Been Invited",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),

                if (user == null) ...[
                  Text(
                    'Sign in with the email this invite was sent to, or create an account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[700], fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  if (authState.hasError)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      color: Colors.red[50],
                      child: Text(
                        authState.error.toString(),
                        style: TextStyle(color: Colors.red[900], fontSize: 12),
                      ),
                    ),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) => v != null && v.contains('@') ? null : 'Enter a valid email',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            border: OutlineInputBorder(),
                          ),
                          obscureText: true,
                          validator: (v) => v != null && v.length >= 6 ? null : 'At least 6 characters',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_isNewAccount ? "I'm new here" : 'I already have an account'),
                      Switch(
                        value: _isNewAccount,
                        activeThumbColor: const Color(0xFFc51f43),
                        onChanged: (v) => setState(() => _isNewAccount = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: authState.isLoading || acceptState.isLoading
                        ? null
                        : _signInOrSignUpThenAccept,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFFc51f43),
                      foregroundColor: Colors.white,
                    ),
                    child: authState.isLoading || acceptState.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_isNewAccount ? 'Create Account & Accept' : 'Sign In & Accept'),
                  ),
                ] else ...[
                  Text(
                    "Signed in as ${user.email}.\nAccept this invite to join the organization.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[700], fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: acceptState.isLoading ? null : _accept,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFFc51f43),
                      foregroundColor: Colors.white,
                    ),
                    child: acceptState.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Accept Invite'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
