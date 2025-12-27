import 'package:flutter/material.dart';
import '../../data/models/user_model.dart';
import 'package:intl/intl.dart';

class ProfileInfoCardsWidget extends StatelessWidget {
  final UserModel user;

  const ProfileInfoCardsWidget({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final infoItems = <_InfoItem>[];

    if (user.workplace != null && user.workplace!.isNotEmpty) {
      infoItems.add(_InfoItem(
        icon: Icons.work,
        label: 'Nơi làm việc',
        value: user.workplace!,
      ));
    }

    if (user.education != null && user.education!.isNotEmpty) {
      infoItems.add(_InfoItem(
        icon: Icons.school,
        label: 'Học vấn',
        value: user.education!,
      ));
    }

    if (user.location != null && user.location!.isNotEmpty) {
      infoItems.add(_InfoItem(
        icon: Icons.location_on,
        label: 'Nơi sống',
        value: user.location!,
      ));
    }

    if (user.hometown != null && user.hometown!.isNotEmpty) {
      infoItems.add(_InfoItem(
        icon: Icons.home,
        label: 'Quê quán',
        value: user.hometown!,
      ));
    }

    if (user.birthday != null) {
      final age = DateTime.now().year - user.birthday!.year;
      final formattedDate = DateFormat('dd/MM/yyyy').format(user.birthday!);
      infoItems.add(_InfoItem(
        icon: Icons.cake,
        label: 'Ngày sinh',
        value: '$formattedDate ($age tuổi)',
      ));
    }

    if (user.relationshipStatus != null &&
        user.relationshipStatus!.isNotEmpty) {
      infoItems.add(_InfoItem(
        icon: Icons.favorite,
        label: 'Mối quan hệ',
        value: user.relationshipStatus!,
      ));
    }

    if (infoItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: infoItems.map((item) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.dividerColor.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  color: theme.primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color
                              ?.withOpacity(0.7),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.value,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;

  _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });
}

