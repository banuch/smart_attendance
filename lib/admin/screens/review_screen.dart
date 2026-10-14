import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_config.dart';
import '../../core/data/providers.dart';
import '../../core/models/attendance_record.dart';
import '../../core/utils/dates.dart';
import '../widgets/attendance_detail_dialog.dart';
import '../widgets/common.dart';

/// Punches flagged by face mismatch / weak GPS, awaiting an admin decision.
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingReviewProvider);
    return pending.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState(Icons.error_outline, 'Could not load: $e'),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(
            Icons.verified_outlined,
            'Nothing to review. Flagged check-ins will appear here.',
          );
        }
        final sorted = [...list]..sort((a, b) => b.date.compareTo(a.date));
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: sorted.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _ReviewTile(record: sorted[i]),
        );
      },
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.record});

  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final reasons = {
      ...record.checkIn.flagReasons,
      ...?record.checkOut?.flagReasons,
    };
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: SelfieThumb(record.checkIn.photoUrl, size: 56),
        title: Text(record.employeeName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${dayFormat.format(parseDateKey(record.date))} · '
              'in ${timeFormat.format(record.checkIn.time)}'
              '${record.checkOut == null ? '' : ' · out ${timeFormat.format(record.checkOut!.time)}'}',
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final r in reasons)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.flag, size: 16, color: Colors.orange),
                    label: Text(FlagReason.label(r)),
                  ),
              ],
            ),
          ],
        ),
        trailing: FilledButton.tonal(
          onPressed: () => AttendanceDetailDialog.show(context, record),
          child: const Text('Review'),
        ),
      ),
    );
  }
}
