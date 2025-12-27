import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/user_model.dart';

class ProfileSocialLinksWidget extends StatelessWidget {
  final UserModel user;

  const ProfileSocialLinksWidget({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final links = <_SocialLink>[];

    if (user.facebookLink != null && user.facebookLink!.isNotEmpty) {
      links.add(_SocialLink(
        icon: Icons.facebook,
        label: 'Facebook',
        url: user.facebookLink!,
        color: const Color(0xFF1877F2),
      ));
    }

    if (user.instagramLink != null && user.instagramLink!.isNotEmpty) {
      links.add(_SocialLink(
        icon: Icons.camera_alt,
        label: 'Instagram',
        url: user.instagramLink!,
        color: const Color(0xFFE4405F),
      ));
    }

    if (user.twitterLink != null && user.twitterLink!.isNotEmpty) {
      links.add(_SocialLink(
        icon: Icons.alternate_email,
        label: 'Twitter',
        url: user.twitterLink!,
        color: const Color(0xFF1DA1F2),
      ));
    }

    if (user.tiktokLink != null && user.tiktokLink!.isNotEmpty) {
      links.add(_SocialLink(
        icon: Icons.music_note,
        label: 'TikTok',
        url: user.tiktokLink!,
        color: Colors.black,
      ));
    }

    if (user.websiteLink != null && user.websiteLink!.isNotEmpty) {
      links.add(_SocialLink(
        icon: Icons.language,
        label: 'Website',
        url: user.websiteLink!,
        color: theme.primaryColor,
      ));
    }

    if (links.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: links.map((link) {
          return InkWell(
            onTap: () => _openUrl(link.url),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: link.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: link.color.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(link.icon, color: link.color, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    link.label,
                    style: TextStyle(
                      color: link.color,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _SocialLink {
  final IconData icon;
  final String label;
  final String url;
  final Color color;

  _SocialLink({
    required this.icon,
    required this.label,
    required this.url,
    required this.color,
  });
}

