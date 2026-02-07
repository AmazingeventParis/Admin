import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/message_service.dart';
import '../../services/supabase_service.dart';
import '../../services/friend_service.dart';
import '../../services/duel_service.dart';
import '../widgets/candy_ui.dart';
import 'chat_screen.dart';
import 'menu_screen.dart';
import 'leaderboard_screen.dart';
import 'duel_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;
  int _pendingDuelCount = 0;

  // Animation pour les boutons du menu
  late AnimationController _menuButtonController;
  late Animation<double> _menuButtonAnimation;

  // Abonnement temps réel
  RealtimeChannel? _messagesChannel;

  // Timer pour mise à jour statut online
  Timer? _onlineTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupAnimations();
    _loadConversations();
    _setupRealtimeSubscription();
    _startOnlineUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _menuButtonController.dispose();
    _messagesChannel?.unsubscribe();
    _onlineTimer?.cancel();

    final playerId = supabaseService.playerId;
    if (playerId != null) {
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
      _loadConversations();
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

  void _setupAnimations() {
    _menuButtonController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _menuButtonAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _menuButtonController, curve: Curves.easeInOut),
    );
  }

  Future<void> _loadConversations() async {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    final conversations = await messageService.getConversationsList(playerId);
    final duelCount = await duelService.getPendingDuelCount(playerId);

    if (mounted) {
      setState(() {
        _conversations = conversations;
        _pendingDuelCount = duelCount;
        _isLoading = false;
      });
    }
  }

  void _setupRealtimeSubscription() {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    _messagesChannel = Supabase.instance.client
        .channel('messages_list_$playerId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            // Recharger les conversations quand un nouveau message arrive
            if (mounted) {
              _loadConversations();
            }
          },
        )
        .subscribe();
  }

  void _openChat(Map<String, dynamic> conversation) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          friendId: conversation['friendId'],
          friendName: conversation['friendName'],
          friendPhotoUrl: conversation['friendPhotoUrl'],
        ),
      ),
    );
    // Recharger les conversations au retour
    _loadConversations();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Container(
        width: screenWidth,
        height: screenHeight,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/ui/fondmessage.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              _buildHeader(screenWidth),

              // Liste des conversations
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Color(0xFFE91E63)),
                      )
                    : _conversations.isEmpty
                        ? _buildEmptyState()
                        : _buildConversationsList(screenWidth),
              ),

              // Menu en bas
              _buildBottomMenu(screenWidth),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(double screenWidth) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.05,
        vertical: 20,
      ),
      child: Row(
        children: [
          // Bouton retour style candy
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B9D), Color(0xFFE91E63)],
                ),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE91E63).withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
            ),
          ),
          const SizedBox(width: 12),
          // Titre candy style
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B9D), Color(0xFFE91E63)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE91E63).withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Center(
                child: CandyText(
                  text: 'Tes Matchs Gourmands',
                  fontSize: 18,
                  textColor: Colors.white,
                  strokeColor: Color(0xFFAD1457),
                  strokeWidth: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE91E63).withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: const Color(0xFFE91E63).withOpacity(0.5),
            ),
            const SizedBox(height: 20),
            const Text(
              'Aucune conversation',
              style: TextStyle(
                color: Color(0xFF8B4513),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Envoie un message à un ami\npour commencer une conversation !',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF8B4513).withOpacity(0.7),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationsList(double screenWidth) {
    // Calcul de la taille des biscuits (2 par ligne avec espacement)
    final biscuitWidth = (screenWidth - 48) / 2; // 48 = padding + spacing
    final biscuitHeight = biscuitWidth * 1.3; // Ratio du biscuit

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1 / 1.3,
      ),
      itemCount: _conversations.length,
      itemBuilder: (context, index) {
        return _buildBiscuitCard(_conversations[index], biscuitWidth);
      },
    );
  }

  Widget _buildBiscuitCard(Map<String, dynamic> conversation, double width) {
    final friendName = conversation['friendName'] as String;
    final friendPhotoUrl = conversation['friendPhotoUrl'] as String?;
    final lastMessage = conversation['lastMessage'] as String;
    final unreadCount = conversation['unreadCount'] as int;

    // Taille de la photo (dans le trou du biscuit) - agrandie et mieux centrée
    final photoSize = width * 0.52;
    final photoTopOffset = width * 0.11;

    return GestureDetector(
      onTap: () => _openChat(conversation),
      child: Stack(
        children: [
          // Image du biscuit
          Image.asset(
            'assets/ui/Biscuitmessages.png',
            width: width,
            fit: BoxFit.contain,
          ),

          // Photo de profil (dans le trou)
          Positioned(
            top: photoTopOffset,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: photoSize,
                height: photoSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: friendPhotoUrl != null
                      ? Image.network(
                          friendPhotoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildDefaultAvatar(friendName),
                        )
                      : _buildDefaultAvatar(friendName),
                ),
              ),
            ),
          ),

          // Nom de l'ami (sous la photo) - descendu
          Positioned(
            top: width * 0.64,
            left: 8,
            right: 8,
            child: Text(
              friendName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFF8B4513),
                fontSize: width * 0.10,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(
                    color: Colors.white.withOpacity(0.5),
                    offset: const Offset(0, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ),

          // Dernier message (zone rectangulaire du milieu) - descendu
          Positioned(
            top: width * 0.80,
            left: 14,
            right: 14,
            child: Text(
              lastMessage,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFF6B4423),
                fontSize: width * 0.075,
              ),
            ),
          ),

          // Badge non lus
          if (unreadCount > 0)
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE91E63),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE91E63).withOpacity(0.5),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  unreadCount > 9 ? '9+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDefaultAvatar(String name) {
    return Container(
      color: const Color(0xFFFF6B9D),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomMenu(double screenWidth) {
    final menuHeight = screenWidth * 0.22;
    final buttonSize = screenWidth * 0.20;

    return Container(
      width: screenWidth,
      height: menuHeight + 20,
      padding: const EdgeInsets.only(bottom: 10),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            'assets/ui/Menu.png',
            width: screenWidth * 0.95,
            fit: BoxFit.contain,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Bouton Accueil
              _buildAnimatedMenuButton(
                'assets/ui/Boutonaccueil.png',
                buttonSize,
                () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const MenuScreen()),
                  );
                },
                0.0,
              ),
              // Bouton Leader
              _buildAnimatedMenuButton(
                'assets/ui/boutonleader.png',
                buttonSize,
                () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const LeaderboardScreen()),
                  );
                },
                0.25,
              ),
              // Bouton Messages (statique - on est sur cette page)
              _buildStaticMenuButton(
                'assets/ui/boutonmessages.png',
                buttonSize,
              ),
              // Bouton Duel avec badge
              _buildDuelButtonWithBadge(buttonSize),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedMenuButton(String asset, double size, VoidCallback onTap, double delay) {
    return AnimatedBuilder(
      animation: _menuButtonController,
      builder: (context, child) {
        final animValue = (_menuButtonAnimation.value + delay) % 1.0;
        final scale = 1.0 + 0.08 * (0.5 - (animValue - 0.5).abs()) * 2;
        final translateY = -5.0 * (0.5 - (animValue - 0.5).abs()) * 2;

        return Transform.translate(
          offset: Offset(0, translateY),
          child: Transform.scale(
            scale: scale,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTap: onTap,
        child: Image.asset(
          asset,
          width: size,
          height: size,
        ),
      ),
    );
  }

  Widget _buildStaticMenuButton(String asset, double size) {
    return Opacity(
      opacity: 0.6,
      child: Image.asset(
        asset,
        width: size,
        height: size,
      ),
    );
  }

  /// Bouton Duel avec badge de notification
  Widget _buildDuelButtonWithBadge(double size) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _buildAnimatedMenuButton(
          'assets/ui/boutonduel.png',
          size,
          () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const DuelScreen()),
            );
          },
          0.75,
        ),
        if (_pendingDuelCount > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.5),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                _pendingDuelCount > 9 ? '9+' : '$_pendingDuelCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
