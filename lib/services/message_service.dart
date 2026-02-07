import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';

/// Modèle représentant un message
class Message {
  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final DateTime createdAt;
  final DateTime? readAt;

  // Infos du sender (optionnel, rempli par les jointures)
  String? senderName;
  String? senderPhotoUrl;

  Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.createdAt,
    this.readAt,
    this.senderName,
    this.senderPhotoUrl,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      senderId: json['sender_id'],
      receiverId: json['receiver_id'],
      content: json['content'],
      createdAt: DateTime.parse(json['created_at']),
      readAt: json['read_at'] != null ? DateTime.parse(json['read_at']) : null,
    );
  }

  bool get isRead => readAt != null;
}

/// Service gérant les messages entre joueurs
class MessageService {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Envoie un message à un ami
  Future<Message?> sendMessage({
    required String senderId,
    required String receiverId,
    required String content,
  }) async {
    try {
      final response = await _client
          .from('messages')
          .insert({
            'sender_id': senderId,
            'receiver_id': receiverId,
            'content': content,
          })
          .select()
          .single();

      // Envoyer la notification push au destinataire
      _sendMessageNotification(
        senderId: senderId,
        receiverId: receiverId,
        content: content,
      );

      return Message.fromJson(response);
    } catch (e) {
      print('Erreur envoi message: $e');
      return null;
    }
  }

  /// Envoie une notification push pour un nouveau message
  Future<void> _sendMessageNotification({
    required String senderId,
    required String receiverId,
    required String content,
  }) async {
    try {
      // Récupérer les infos du sender
      final senderData = await _client
          .from('players')
          .select('username, photo_url')
          .eq('id', senderId)
          .maybeSingle();

      if (senderData != null) {
        await NotificationService.sendNewMessage(
          targetPlayerId: receiverId,
          senderName: senderData['username'] ?? 'Joueur',
          senderPhotoUrl: senderData['photo_url'],
          messagePreview: content,
        );
      }
    } catch (e) {
      print('Erreur notification message: $e');
    }
  }

  /// Récupère la conversation entre deux joueurs
  Future<List<Message>> getConversation({
    required String playerId,
    required String friendId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await _client
          .from('messages')
          .select('*')
          .or('and(sender_id.eq.$playerId,receiver_id.eq.$friendId),and(sender_id.eq.$friendId,receiver_id.eq.$playerId)')
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (response as List)
          .map((json) => Message.fromJson(json))
          .toList()
          .reversed
          .toList(); // Inverser pour avoir les plus anciens en premier
    } catch (e) {
      print('Erreur récupération conversation: $e');
      return [];
    }
  }

  /// Marque les messages comme lus
  Future<void> markAsRead({
    required String playerId,
    required String friendId,
  }) async {
    try {
      await _client
          .from('messages')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('sender_id', friendId)
          .eq('receiver_id', playerId)
          .isFilter('read_at', null);
    } catch (e) {
      print('Erreur marquage lu: $e');
    }
  }

  /// Récupère le nombre de messages non lus d'un ami
  Future<int> getUnreadCountFromFriend({
    required String playerId,
    required String friendId,
  }) async {
    try {
      final response = await _client
          .from('messages')
          .select('id')
          .eq('sender_id', friendId)
          .eq('receiver_id', playerId)
          .isFilter('read_at', null);

      return (response as List).length;
    } catch (e) {
      print('Erreur comptage non lus: $e');
      return 0;
    }
  }

  /// Récupère le nombre total de messages non lus
  Future<int> getTotalUnreadCount(String playerId) async {
    try {
      final response = await _client
          .from('messages')
          .select('id')
          .eq('receiver_id', playerId)
          .isFilter('read_at', null);

      return (response as List).length;
    } catch (e) {
      print('Erreur comptage total non lus: $e');
      return 0;
    }
  }

  /// Récupère le dernier message d'une conversation
  Future<Message?> getLastMessage({
    required String playerId,
    required String friendId,
  }) async {
    try {
      final response = await _client
          .from('messages')
          .select('*')
          .or('and(sender_id.eq.$playerId,receiver_id.eq.$friendId),and(sender_id.eq.$friendId,receiver_id.eq.$playerId)')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        return Message.fromJson(response);
      }
      return null;
    } catch (e) {
      print('Erreur récupération dernier message: $e');
      return null;
    }
  }

  /// Récupère la liste des conversations avec le dernier message
  Future<List<Map<String, dynamic>>> getConversationsList(String playerId) async {
    try {
      // Récupérer tous les messages où le joueur est impliqué
      final response = await _client
          .from('messages')
          .select('''
            *,
            sender:players!messages_sender_id_fkey(id, username, photo_url),
            receiver:players!messages_receiver_id_fkey(id, username, photo_url)
          ''')
          .or('sender_id.eq.$playerId,receiver_id.eq.$playerId')
          .order('created_at', ascending: false);

      // Grouper par conversation (ami)
      final Map<String, Map<String, dynamic>> conversations = {};

      for (var msg in response) {
        final friendId = msg['sender_id'] == playerId
            ? msg['receiver_id']
            : msg['sender_id'];

        if (!conversations.containsKey(friendId)) {
          final friendData = msg['sender_id'] == playerId
              ? msg['receiver']
              : msg['sender'];

          conversations[friendId] = {
            'friendId': friendId,
            'friendName': friendData?['username'] ?? 'Joueur',
            'friendPhotoUrl': friendData?['photo_url'],
            'lastMessage': msg['content'],
            'lastMessageTime': DateTime.parse(msg['created_at']),
            'isFromMe': msg['sender_id'] == playerId,
            'unreadCount': 0,
          };
        }
      }

      // Compter les non lus pour chaque conversation
      for (var conv in conversations.values) {
        conv['unreadCount'] = await getUnreadCountFromFriend(
          playerId: playerId,
          friendId: conv['friendId'],
        );
      }

      // Trier par date du dernier message
      final list = conversations.values.toList();
      list.sort((a, b) => (b['lastMessageTime'] as DateTime)
          .compareTo(a['lastMessageTime'] as DateTime));

      return list;
    } catch (e) {
      print('Erreur récupération liste conversations: $e');
      return [];
    }
  }
}

// Instance globale
final messageService = MessageService();
