import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:sabha_hq/features/attendee_feedback/application/feedback_admin_providers.dart';
import '../../admin_events/application/event_providers.dart';
import '../application/metrics_calculator.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  String? _selectedEventId;

  @override
  Widget build(BuildContext context) {
    final eventsState = ref.watch(eventListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Event Analytics')),
      body: eventsState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (events) {
          if (events.isEmpty) {
            return const Center(child: Text('No events found.'));
          }

          _selectedEventId ??= events.first.id;

          // 1. Wrap the body in a LayoutBuilder to detect screen width
          return LayoutBuilder(
            builder: (context, constraints) {
              // Define a breakpoint for mobile vs web (600px is standard)
              final isDesktop = constraints.maxWidth > 600;

              return Padding(
                // Dynamic padding: smaller for mobile, larger for web
                padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // EVENT SELECTOR
                    SizedBox(
                      // Limit width on desktop so it doesn't stretch across the whole screen
                      width: isDesktop ? 400 : double.infinity,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedEventId,
                        decoration: const InputDecoration(
                          labelText: 'Select Event to Analyze',
                          border: OutlineInputBorder(),
                        ),
                        isExpanded:
                            true, // Prevents text overflow on small screens
                        items: events.map((e) {
                          return DropdownMenuItem(
                            value: e.id,
                            child: Text(
                              e.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) =>
                            setState(() => _selectedEventId = val),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // METRICS & CHART
                    Expanded(
                      child: _selectedEventId == null
                          ? const SizedBox.shrink()
                          : _buildMetricsDashboard(
                              _selectedEventId!,
                              isDesktop,
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMetricsDashboard(String eventId, bool isDesktop) {
    final metricsState = ref.watch(eventMetricsProvider(eventId));

    return metricsState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
      data: (metrics) {
        if (metrics.totalRegistered == 0) {
          return const Center(
            child: Text('No attendees registered for this event yet.'),
          );
        }

        // 2. Extract Chart into a reusable widget
        Widget chartWidget = Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: isDesktop
                    ? 60
                    : 50, // Slightly smaller on mobile
                sections: [
                  PieChartSectionData(
                    value: metrics.totalCheckedIn.toDouble(),
                    color: Colors.green,
                    title:
                        '${((metrics.totalCheckedIn / metrics.totalRegistered) * 100).toStringAsFixed(0)}%',
                    radius: isDesktop ? 50 : 40,
                    titleStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  PieChartSectionData(
                    value: metrics.pending.toDouble(),
                    color: Colors.grey[300],
                    title: '',
                    radius: isDesktop ? 50 : 40,
                  ),
                ],
              ),
            ),
            Text(
              '${metrics.totalCheckedIn}\nChecked In',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: isDesktop ? 16 : 14,
              ),
            ),
          ],
        );

        // 3. Extract Stats into a reusable widget
        Widget statsWidget = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatTile(
              title: 'Total Registered',
              value: metrics.totalRegistered,
              icon: Icons.people,
            ),
            _StatTile(
              title: 'Movers',
              value: metrics.movers,
              icon: Icons.person_outline,
            ),
            _StatTile(
              title: 'Pitchers',
              value: metrics.pitchers,
              icon: Icons.star_border,
            ),
          ],
        );

        // 4. Return Row for Desktop, Scrollable Column for Mobile.
        // Feedback (task #8) is appended below either layout, in its own
        // scrollable section, rather than squeezed into the fixed-height
        // chart/stats row — that layout is deliberately tight (fl_chart
        // needs a bounded height) and not the place to add a
        // variable-length comment list.
        if (isDesktop) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 260,
                  child: Row(
                    children: [
                      Expanded(flex: 1, child: chartWidget),
                      const SizedBox(width: 32),
                      Expanded(flex: 1, child: statsWidget),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                _FeedbackSection(eventId: eventId),
              ],
            ),
          );
        } else {
          return SingleChildScrollView(
            child: Column(
              children: [
                // fl_chart requires bounded height in a Column
                SizedBox(height: 250, child: chartWidget),
                const SizedBox(height: 32),
                statsWidget,
                const SizedBox(height: 32),
                _FeedbackSection(eventId: eventId),
                const SizedBox(height: 32), // Bottom padding for scrolling
              ],
            ),
          );
        }
      },
    );
  }
}

class _FeedbackSection extends ConsumerWidget {
  final String eventId;
  const _FeedbackSection({required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedbackState = ref.watch(feedbackForEventProvider(eventId));

    return feedbackState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error loading feedback: $e'),
      data: (feedback) {
        if (feedback.isEmpty) {
          return const SizedBox.shrink();
        }

        final avgRating =
            feedback.map((f) => f.rating).reduce((a, b) => a + b) /
            feedback.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Feedback',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.star, color: Colors.amber, size: 18),
                const SizedBox(width: 4),
                Text(
                  '${avgRating.toStringAsFixed(1)} avg • ${feedback.length} response${feedback.length == 1 ? '' : 's'}',
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...feedback.map((f) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      5,
                      (i) => Icon(
                        i < f.rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 16,
                      ),
                    ),
                  ),
                  title: Text(
                    f.comment?.isNotEmpty == true ? f.comment! : 'No comment',
                  ),
                  subtitle: Text(
                    DateFormat('MMM d, yyyy • h:mm a').format(f.submittedAt),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  final String title;
  final int value;
  final IconData icon;

  const _StatTile({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFFc51f43), size: 32),
        title: Text(title, style: const TextStyle(color: Colors.grey)),
        subtitle: Text(
          value.toString(),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
