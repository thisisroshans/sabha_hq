import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
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
    // 1. Fetch available events for the dropdown
    final eventsState = ref.watch(eventListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Event Analytics')),
      body: eventsState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (events) {
          if (events.isEmpty)
            return const Center(child: Text('No events found.'));

          // Auto-select the first event if none is selected
          _selectedEventId ??= events.first.id;

          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // EVENT SELECTOR
                DropdownButtonFormField<String>(
                  value: _selectedEventId,
                  decoration: const InputDecoration(
                    labelText: 'Select Event to Analyze',
                    border: OutlineInputBorder(),
                  ),
                  items: events.map((e) {
                    return DropdownMenuItem(value: e.id, child: Text(e.title));
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedEventId = val),
                ),
                const SizedBox(height: 32),

                // METRICS & CHART
                Expanded(
                  child: _selectedEventId == null
                      ? const SizedBox.shrink()
                      : _buildMetricsDashboard(_selectedEventId!),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetricsDashboard(String eventId) {
    // 2. Fetch and calculate metrics for the selected event
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

        return Row(
          children: [
            // PIE CHART
            Expanded(
              flex: 1,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 60,
                      sections: [
                        PieChartSectionData(
                          value: metrics.totalCheckedIn.toDouble(),
                          color: Colors.green,
                          title:
                              '${((metrics.totalCheckedIn / metrics.totalRegistered) * 100).toStringAsFixed(0)}%',
                          radius: 50,
                          titleStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        PieChartSectionData(
                          value: metrics.pending.toDouble(),
                          color: Colors.grey[300],
                          title: '', // Hide label for pending
                          radius: 50,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${metrics.totalCheckedIn}\nChecked In',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),

            // STATS CARDS
            Expanded(
              flex: 1,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatTile(
                    title: 'Total Registered',
                    value: metrics.totalRegistered,
                    icon: Icons.people,
                  ),
                  _StatTile(
                    title: 'Guests',
                    value: metrics.guests,
                    icon: Icons.person_outline,
                  ),
                  _StatTile(
                    title: 'Participants',
                    value: metrics.participants,
                    icon: Icons.star_border,
                  ),
                ],
              ),
            ),
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
        leading: Icon(icon, color: Colors.deepPurple, size: 32),
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
