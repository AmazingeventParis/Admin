import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/message_service.dart';
import '../../services/supabase_service.dart';
import '../../services/friend_service.dart';
import '../widgets/candy_ui.dart';

class ChatScreen extends StatefulWidget {
  final String friendId;
  final String friendName;
  final String? friendPhotoUrl;

  const ChatScreen({
    super.key,
    required this.friendId,
    required this.friendName,
    this.friendPhotoUrl,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _friendIsTyping = false;


  // Timer pour mise à jour statut online
  Timer? _onlineTimer;

  // Timer pour le debounce de la frappe
  Timer? _typingTimer;

  // Abonnements Realtime
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _typingChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMessages();
    _markMessagesAsRead();
    _startOnlineUpdates();
    _setupRealtimeMessages();
    _setupRealtimeTyping();

    // Écouter les changements de texte pour l'indicateur de frappe
    _messageController.addListener(_onTextChanged);
  }

  /// Configure le Realtime pour les messages
  void _setupRealtimeMessages() {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    _messagesChannel = Supabase.instance.client
        .channel('messages-channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final newMessage = payload.newRecord;
            if (newMessage == null || !mounted) return;

            final senderId = newMessage['sender_id'];
            final receiverId = newMessage['receiver_id'];

            // Vérifier si le message concerne cette conversation
            final isForThisConversation =
                (senderId == playerId && receiverId == widget.friendId) ||
                (senderId == widget.friendId && receiverId == playerId);

            if (isForThisConversation) {
              final message = Message.fromJson(newMessage);

              // Éviter les doublons
              if (!_messages.any((m) => m.id == message.id)) {
                setState(() {
                  _messages.add(message);
                });
                _scrollToBottom();

                // Marquer comme lu si c'est un message reçu
                if (message.senderId == widget.friendId) {
                  _markMessagesAsRead();
                }
              }
            }
          },
        )
        .subscribe();
  }

  /// Configure le Realtime pour l'indicateur de frappe
  void _setupRealtimeTyping() {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    _typingChannel = Supabase.instance.client
        .channel('typing-channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'typing_status',
          callback: (payload) {
            final record = payload.newRecord;
            if (record == null || !mounted) return;

            if (record['player_id'] == widget.friendId &&
                record['target_id'] == playerId) {
              final isTyping = record['is_typing'] == true;
              setState(() {
                _friendIsTyping = isTyping;
              });
              // Scroll vers le bas pour voir l'indicateur
              if (isTyping) {
                _scrollToBottom();
              }
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messagesChannel?.unsubscribe();
    _typingChannel?.unsubscribe();
    _onlineTimer?.cancel();
    _typingTimer?.cancel();
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();

    // Arrêter d'écrire et mettre offline
    final playerId = supabaseService.playerId;
    if (playerId != null) {
      _setTypingStatus(false);
      friendService.setOffline(playerId);
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      friendService.setOffline(playerId);
    } else if (state == AppLifecycleState.resumed) {
      friendService.updateOnlineStatus(playerId);
      _markMessagesAsRead();
    }
  }

  void _startOnlineUpdates() {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    friendService.updateOnlineStatus(playerId);
    _onlineTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        friendService.updateOnlineStatus(playerId);
      }
    });
  }

  Future<void> _loadMessages() async {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    final messages = await messageService.getConversation(
      playerId: playerId,
      friendId: widget.friendId,
    );

    if (mounted) {
      setState(() {
        _messages = messages;
        _isLoading = false;
      });

      // Scroll vers le bas après chargement
      _scrollToBottom();
    }
  }


  /// Appelé quand le texte change dans le champ de saisie
  void _onTextChanged() {
    final hasText = _messageController.text.isNotEmpty;

    if (hasText) {
      // L'utilisateur écrit - mettre à jour le statut
      _setTypingStatus(true);

      // Réinitialiser le timer - arrêter d'écrire après 3 secondes d'inactivité
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        _setTypingStatus(false);
      });
    } else {
      // Le champ est vide - arrêter l'indicateur
      _typingTimer?.cancel();
      _setTypingStatus(false);
    }
  }

  /// Met à jour le statut de frappe dans la base de données
  Future<void> _setTypingStatus(bool isTyping) async {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    try {
      await Supabase.instance.client.from('typing_status').upsert({
        'player_id': playerId,
        'target_id': widget.friendId,
        'is_typing': isTyping,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Ignorer les erreurs silencieusement
      print('Erreur mise à jour typing: $e');
    }
  }

  Future<void> _markMessagesAsRead() async {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    await messageService.markAsRead(
      playerId: playerId,
      friendId: widget.friendId,
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    setState(() => _isSending = true);

    // Arrêter l'indicateur de frappe
    _typingTimer?.cancel();
    _setTypingStatus(false);

    final message = await messageService.sendMessage(
      senderId: playerId,
      receiverId: widget.friendId,
      content: text,
    );

    if (mounted) {
      setState(() => _isSending = false);

      if (message != null) {
        _messageController.clear();
        // Ajouter le message immédiatement à la liste (pas attendre le realtime)
        setState(() {
          _messages.add(message);
        });
        _scrollToBottom();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A1B3D), Color(0xFF1A0F2E)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              _buildHeader(screenWidth),

              // Messages
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Color(0xFFE91E63)),
                      )
                    : _messages.isEmpty
                        ? _buildEmptyState()
                        : _buildMessageList(),
              ),

              // Input
              _buildInputArea(screenWidth),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(double screenWidth) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B9D), Color(0xFFE91E63)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE91E63).withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Bouton retour
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
            ),
          ),
          const SizedBox(width: 12),

          // Photo de profil
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                ),
              ],
            ),
            child: ClipOval(
              child: widget.friendPhotoUrl != null
                  ? Image.network(
                      widget.friendPhotoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildDefaultAvatar(),
                    )
                  : _buildDefaultAvatar(),
            ),
          ),
          const SizedBox(width: 12),

          // Nom
          Expanded(
            child: Text(
              widget.friendName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Bouton défier
          GestureDetector(
            onTap: () {
              // TODO: Défier depuis le chat
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Défier depuis le chat - Bientôt disponible'),
                  backgroundColor: Colors.blue,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.sports_esports, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      color: const Color(0xFFFFD700),
      child: Center(
        child: Text(
          widget.friendName.isNotEmpty ? widget.friendName[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 80,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Aucun message',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Envoie le premier message à ${widget.friendName} !',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    final playerId = supabaseService.playerId;
    // Ajouter 1 item si l'ami est en train d'écrire
    final itemCount = _messages.length + (_friendIsTyping ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Si c'est le dernier item et l'ami écrit, afficher l'indicateur
        if (_friendIsTyping && index == _messages.length) {
          return _buildTypingBubble();
        }

        final message = _messages[index];
        final isMe = message.senderId == playerId;
        final showDate = index == 0 ||
            !_isSameDay(_messages[index - 1].createdAt, message.createdAt);

        return Column(
          children: [
            if (showDate) _buildDateSeparator(message.createdAt),
            _buildMessageBubble(message, isMe),
          ],
        );
      },
    );
  }

  /// Bulle "Prénom écrit..." en bas à gauche
  Widget _buildTypingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.friendName} écrit',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(width: 4),
            _TypingDots(),
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    String text;
    if (messageDate == today) {
      text = "Aujourd'hui";
    } else if (messageDate == yesterday) {
      text = 'Hier';
    } else {
      text = '${date.day}/${date.month}/${date.year}';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withOpacity(0.6),
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Message message, bool isMe) {
    final time = '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: isMe
                    ? const LinearGradient(
                        colors: [Color(0xFFFF6B9D), Color(0xFFE91E63)],
                      )
                    : null,
                color: isMe ? null : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message.content,
                style: TextStyle(
                  color: isMe ? Colors.white : const Color(0xFF2A1B3D),
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.isRead ? Icons.done_all : Icons.done,
                    size: 14,
                    color: message.isRead
                        ? const Color(0xFF4FC3F7)
                        : Colors.white.withOpacity(0.5),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea(double screenWidth) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1B3D),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Champ de texte
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _messageController,
                focusNode: _focusNode,
                style: const TextStyle(color: Colors.white),
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Écris un message...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Bouton envoyer
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B9D), Color(0xFFE91E63)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE91E63).withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _isSending
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget animé pour les points de frappe "..."
class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final progress = (_controller.value + delay) % 1.0;
            final opacity = progress < 0.5 ? progress * 2 : (1.0 - progress) * 2;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.4 + opacity * 0.6),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
