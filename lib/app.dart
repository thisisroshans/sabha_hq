import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/notifications/check_in_notifications.dart';
import 'core/router/app_router.dart';

class SabhaApp extends ConsumerStatefulWidget {
  const SabhaApp({super.key});

  @override
  ConsumerState<SabhaApp> createState() => _SabhaAppState();
}

class _SabhaAppState extends ConsumerState<SabhaApp> {
  @override
  void initState() {
    super.initState();
    // Tapping a check-in push notification (Android/iOS) opens the live
    // feed — including the one that cold-started the app, which is why
    // this is wired up here at the root rather than in AdminScaffold.
    CheckInNotifications.instance.startTapHandling(ref.read(goRouterProvider));
  }

  @override
  Widget build(BuildContext context) {
    // Watch the router provider to rebuild if core routing logic changes
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: 'Sabha HQ',
      debugShowCheckedModeBanner: false,

      // The router config handles all the URL parsing and navigation
      routerConfig: router,

      // Default theme (Phase 4 will add dynamic branding overrides)
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFc51f43)),
        useMaterial3: true,
      ),
    );
  }
}
