import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/utils/color_utils.dart';
import 'package:sabha_hq/features/admin_events/application/event_providers.dart';
import '../application/feedback_controller.dart';

class FeedbackScreen extends ConsumerStatefulWidget {
  final String? orgId;
  final String? eventId;

  const FeedbackScreen({super.key, required this.orgId, required this.eventId});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  int _rating = 0;
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.orgId == null || widget.eventId == null) {
      return const Scaffold(
        body: Center(child: Text('Invalid Link. Missing Event ID.')),
      );
    }

    final orgId = widget.orgId!;
    final eventId = widget.eventId!;

    final feedbackState = ref.watch(feedbackControllerProvider);
    final eventState = ref.watch(
      eventForGuestProvider((orgId: orgId, eventId: eventId)),
    );

    final brandColor = eventState.valueOrNull?.branding['primaryColor'] as String?;
    final themeColor = parseHexColor(brandColor) ?? const Color(0xFFc51f43);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Event Feedback'),
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20)],
                ),
                child: feedbackState.step == FeedbackStep.submitted
                    ? _buildThankYou(themeColor)
                    : _buildForm(themeColor, feedbackState),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThankYou(Color themeColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, color: Colors.green[600], size: 72),
        const SizedBox(height: 20),
        const Text(
          'Thanks for your feedback!',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildForm(Color themeColor, FeedbackState feedbackState) {
    final isBusy = feedbackState.step == FeedbackStep.submitting;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.rate_review_outlined, size: 56, color: themeColor),
        const SizedBox(height: 16),
        const Text(
          'How was the event?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),

        if (feedbackState.step == FeedbackStep.error) ...[
          Container(
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              feedbackState.errorMessage ?? 'Something went wrong.',
              style: const TextStyle(color: Colors.red),
            ),
          ),
          const SizedBox(height: 16),
        ],

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            final starValue = index + 1;
            return IconButton(
              iconSize: 40,
              icon: Icon(
                starValue <= _rating ? Icons.star : Icons.star_border,
                color: Colors.amber,
              ),
              onPressed: () => setState(() => _rating = starValue),
            );
          }),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _commentController,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Comments (optional)',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: isBusy || _rating == 0
                ? null
                : () => ref.read(feedbackControllerProvider.notifier).submit(
                      orgId: widget.orgId!,
                      eventId: widget.eventId!,
                      rating: _rating,
                      comment: _commentController.text.trim().isEmpty
                          ? null
                          : _commentController.text.trim(),
                    ),
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: isBusy
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : const Text('Submit Feedback', style: TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );
  }
}
