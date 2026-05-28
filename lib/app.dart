import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';

class SabhaApp extends ConsumerWidget {
  const SabhaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the router provider to rebuild if core routing logic changes
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: 'The Unpuzzle Project',
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
