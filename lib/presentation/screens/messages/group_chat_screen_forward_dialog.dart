import 'package:flutter/material.dart';
import '../../../data/services/message_service.dart';
import '../../../data/services/user_service.dart';
import '../../../data/services/group_service.dart';
import '../../../data/models/conversation_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/group_model.dart';

class ForwardMessageDialog extends StatelessWidget {
  final String currentUserId;
  final MessageService messageService;

  const ForwardMessageDialog({
    super.key,
    required this.currentUserId,
    required this.messageService,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text(
                    'Chọn cuộc trò chuyện',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black87),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<ConversationModel>>(
                stream: messageService.getConversations(currentUserId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.black),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                      child: Text(
                        'Chưa có cuộc trò chuyện nào',
                        style: TextStyle(color: Colors.black87),
                      ),
                    );
                  }

                  final conversations = snapshot.data!;

                  return ListView.builder(
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final conversation = conversations[index];
                      
                      // Direct conversation
                      if (conversation.type == 'direct') {
                        final otherUserId = conversation.getOtherUserId(
                          currentUserId,
                        );
                        if (otherUserId == null) return const SizedBox.shrink();

                        return FutureBuilder<UserModel?>(
                          future: UserService().getUserById(otherUserId),
                          builder: (context, userSnapshot) {
                            if (!userSnapshot.hasData) {
                              return const SizedBox.shrink();
                            }

                            final user = userSnapshot.data!;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: user.avatarUrl != null
                                    ? NetworkImage(user.avatarUrl!)
                                    : null,
                                child: user.avatarUrl == null
                                    ? Text(user.fullName[0].toUpperCase())
                                    : null,
                              ),
                              title: Text(
                                user.fullName,
                                style: const TextStyle(color: Colors.black),
                              ),
                              subtitle: Text(
                                conversation.lastMessageContent ?? '',
                                style: TextStyle(color: Colors.grey[400]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.pop(
                                context,
                                {'conversationId': conversation.id, 'type': 'direct'},
                              ),
                            );
                          },
                        );
                      }
                      
                      // Group conversation
                      if (conversation.type == 'group' && conversation.groupId != null) {
                        return FutureBuilder<GroupModel?>(
                          future: GroupService().getGroup(conversation.groupId!),
                          builder: (context, groupSnapshot) {
                            if (!groupSnapshot.hasData) {
                              return const SizedBox.shrink();
                            }

                            final group = groupSnapshot.data!;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: group.coverUrl != null
                                    ? NetworkImage(group.coverUrl!)
                                    : null,
                                child: group.coverUrl == null
                                    ? Text(group.name[0].toUpperCase())
                                    : null,
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    group.name,
                                    style: const TextStyle(color: Colors.black),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.group,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                conversation.lastMessageContent ?? '',
                                style: TextStyle(color: Colors.grey[400]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.pop(
                                context,
                                {'conversationId': conversation.id, 'type': 'group', 'groupId': group.id},
                              ),
                            );
                          },
                        );
                      }
                      
                      return const SizedBox.shrink();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

