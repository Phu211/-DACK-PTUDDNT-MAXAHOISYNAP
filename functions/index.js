const admin = require('firebase-admin');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');

admin.initializeApp();

function previewBody(messageData) {
  const text = (messageData.content || '').toString().trim();
  if (text) return text;
  if (messageData.imageUrl) return '[Ảnh]';
  if (messageData.videoUrl) return '[Video]';
  if (messageData.audioUrl) return '[Voice]';
  if (messageData.gifUrl) return '[GIF]';
  return 'Bạn có tin nhắn mới';
}

// Kiểm tra xem cuộc trò chuyện có bị tắt thông báo cho user không
async function isConversationMuted(conversationId, userId) {
  if (!conversationId || !userId) return false;
  try {
    const muteDoc = await admin.firestore()
      .collection('conversations')
      .doc(conversationId)
      .collection('mutes')
      .doc(userId)
      .get();
    
    if (!muteDoc.exists) return false;
    
    const data = muteDoc.data();
    const mutedUntil = data?.mutedUntil;
    if (!mutedUntil) return false;
    
    const mutedUntilDate = new Date(mutedUntil);
    const now = new Date();
    // Kiểm tra xem thời gian mute còn hiệu lực không
    return mutedUntilDate > now;
  } catch (e) {
    console.error('Error checking mute status:', e);
    return false; // Mặc định là không mute nếu có lỗi
  }
}

exports.onMessageCreated = onDocumentCreated('messages/{messageId}', async (event) => {
  const snap = event.data;
  if (!snap) return;

  const messageId = snap.id;
  const data = snap.data() || {};

  const senderId = (data.senderId || '').toString();
  const receiverId = (data.receiverId || '').toString();
  const conversationId = (data.conversationId || '').toString();
  const groupId = (data.groupId || '').toString();

  if (!senderId) return;

  // Fetch sender name (optional)
  let senderName = 'Synap';
  try {
    const senderDoc = await admin.firestore().doc(`users/${senderId}`).get();
    senderName = senderDoc.get('fullName') || senderDoc.get('username') || senderName;
  } catch (_) {}

  const body = previewBody(data);

  // Group chat
  if (groupId) {
    const groupDoc = await admin.firestore().doc(`groups/${groupId}`).get();
    const memberIds = (groupDoc.get('memberIds') || []).map((x) => x.toString());
    const targets = memberIds.filter((uid) => uid && uid !== senderId);
    if (!targets.length) return;

    // Kiểm tra mute status cho từng user và lọc bỏ những user đã tắt thông báo
    const tokenPairs = await Promise.all(targets.map(async (uid) => {
      // Kiểm tra xem conversation có bị mute cho user này không
      const isMuted = await isConversationMuted(conversationId, uid);
      if (isMuted) return null; // Bỏ qua user đã tắt thông báo
      
      const u = await admin.firestore().doc(`users/${uid}`).get();
      const t = u.get('fcmToken');
      return t ? t.toString() : null;
    }));
    const tokens = tokenPairs.filter(Boolean);
    if (!tokens.length) return;

    await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: senderName,
        body,
      },
      data: {
        type: 'group_chat_message',
        senderId,
        groupId,
        conversationId,
        messageId,
      },
      android: {
        notification: {
          channelId: 'synap_general',
        },
      },
    });
    return;
  }

  // Direct chat
  if (!receiverId || senderId === receiverId) return;
  
  // Kiểm tra xem conversation có bị mute cho receiver không
  const isMuted = await isConversationMuted(conversationId, receiverId);
  if (isMuted) {
    console.log(`Conversation ${conversationId} is muted for user ${receiverId}, skipping notification`);
    return; // Không gửi thông báo nếu đã tắt
  }
  
  const receiverDoc = await admin.firestore().doc(`users/${receiverId}`).get();
  const token = receiverDoc.get('fcmToken');
  if (!token) return;

  await admin.messaging().send({
    token: token.toString(),
    notification: {
      title: senderName,
      body,
    },
    data: {
      type: 'chat_message',
      senderId,
      receiverId,
      conversationId,
      messageId,
    },
    android: {
      notification: {
        channelId: 'synap_general',
      },
    },
  });
});

function notificationBodyByType(type, actorName) {
  switch ((type || '').toString()) {
    case 'like':
      return `${actorName} đã thích bài viết của bạn`;
    case 'comment':
      return `${actorName} đã bình luận bài viết của bạn`;
    case 'reply':
      return `${actorName} đã phản hồi bình luận của bạn`;
    case 'follow':
      return `${actorName} đã theo dõi bạn`;
    case 'share':
      return `${actorName} đã chia sẻ bài viết của bạn`;
    case 'mention':
      return `${actorName} đã gắn thẻ bạn trong bài viết`;
    case 'friendRequest':
      return `${actorName} đã gửi lời mời kết bạn`;
    default:
      return 'Bạn có thông báo mới';
  }
}

exports.onAppNotificationCreated = onDocumentCreated('notifications/{notificationId}', async (event) => {
  const snap = event.data;
  if (!snap) return;

  const notificationId = snap.id;
  const data = snap.data() || {};

  const userId = (data.userId || '').toString();
  const actorId = (data.actorId || '').toString();
  const type = (data.type || '').toString();
  const postId = (data.postId || '').toString();
  const commentId = (data.commentId || '').toString();

  if (!userId) return;

  const receiverDoc = await admin.firestore().doc(`users/${userId}`).get();
  const token = receiverDoc.get('fcmToken');
  if (!token) return;

  let actorName = 'Ai đó';
  try {
    const actorDoc = await admin.firestore().doc(`users/${actorId}`).get();
    actorName = actorDoc.get('fullName') || actorDoc.get('username') || actorName;
  } catch (_) {}

  const body = notificationBodyByType(type, actorName);

  await admin.messaging().send({
    token: token.toString(),
    notification: {
      title: 'Synap',
      body,
    },
    data: {
      type: 'app_notification',
      notificationId,
      notificationType: type,
      userId,
      actorId,
      postId,
      commentId,
    },
    android: {
      notification: {
        channelId: 'synap_general',
      },
    },
  });
});

exports.onCallInvitationCreated = onDocumentCreated('callNotifications/{callId}', async (event) => {
  const snap = event.data;
  if (!snap) return;

  const callId = snap.id;
  const data = snap.data() || {};

  const recipientUserId = (data.recipientUserId || '').toString();
  const callerId = (data.callerId || '').toString();
  const callerName = (data.callerName || '').toString();
  const channelName = (data.channelName || '').toString();
  const status = (data.status || '').toString();
  const isVideo = !!data.isVideo;

  if (!recipientUserId || !callerId || !channelName) return;
  if (status && status !== 'ringing') return;

  // Prefer token from callNotifications doc (already looked up by client)
  let token = (data.fcmToken || '').toString();
  if (!token) {
    try {
      const receiverDoc = await admin.firestore().doc(`users/${recipientUserId}`).get();
      token = (receiverDoc.get('fcmToken') || '').toString();
    } catch (_) {}
  }
  if (!token) return;

  const title = callerName || 'Cuộc gọi đến';
  const body = isVideo ? 'Cuộc gọi video đến' : 'Cuộc gọi thoại đến';

  await admin.messaging().send({
    token,
    notification: {
      title,
      body,
    },
    data: {
      type: 'incoming_call',
      callerId,
      isVideo: isVideo ? 'true' : 'false',
      callId,
      channelName,
    },
    android: {
      notification: {
        channelId: 'synap_general',
      },
    },
  });
});
