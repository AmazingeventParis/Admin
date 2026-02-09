/// Statut d'un duel
enum DuelStatus {
  pending,    // En attente de réponse
  active,     // Accepté, en cours (async)
  live,       // Duel en temps réel simultané
  completed,  // Terminé
  declined,   // Refusé
  expired,    // Expiré
}

/// Modèle représentant un duel entre deux joueurs
class Duel {
  final String id;
  final String challengerId;
  final String challengedId;
  final int seed;
  final DuelStatus status;
  final int? challengerScore;
  final int? challengedScore;
  final int? challengerTime;  // Temps en secondes
  final int? challengedTime;  // Temps en secondes
  final String? winnerId;
  final DateTime createdAt;
  final DateTime expiresAt;

  // Détails des joueurs (chargés séparément)
  String? challengerName;
  String? challengerPhotoUrl;
  String? challengedName;
  String? challengedPhotoUrl;

  Duel({
    required this.id,
    required this.challengerId,
    required this.challengedId,
    required this.seed,
    required this.status,
    this.challengerScore,
    this.challengedScore,
    this.challengerTime,
    this.challengedTime,
    this.winnerId,
    required this.createdAt,
    required this.expiresAt,
    this.challengerName,
    this.challengerPhotoUrl,
    this.challengedName,
    this.challengedPhotoUrl,
  });

  factory Duel.fromJson(Map<String, dynamic> json) {
    return Duel(
      id: json['id'],
      challengerId: json['challenger_id'],
      challengedId: json['challenged_id'],
      seed: json['seed'],
      status: _parseStatus(json['status']),
      challengerScore: json['challenger_score'],
      challengedScore: json['challenged_score'],
      challengerTime: json['challenger_time'],
      challengedTime: json['challenged_time'],
      winnerId: json['winner_id'],
      createdAt: DateTime.parse(json['created_at']),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'])
          : DateTime.now().add(const Duration(hours: 24)),
    );
  }

  static DuelStatus _parseStatus(String? status) {
    switch (status) {
      case 'pending':
        return DuelStatus.pending;
      case 'active':
        return DuelStatus.active;
      case 'live':
        return DuelStatus.live;
      case 'completed':
        return DuelStatus.completed;
      case 'declined':
        return DuelStatus.declined;
      case 'expired':
        return DuelStatus.expired;
      default:
        return DuelStatus.pending;
    }
  }

  /// Vérifie si le duel attend une réponse
  bool get isPending => status == DuelStatus.pending;

  /// Vérifie si le duel est en cours
  bool get isActive => status == DuelStatus.active || status == DuelStatus.live;

  /// Vérifie si le duel est en mode temps réel
  bool get isLive => status == DuelStatus.live;

  /// Vérifie si le duel est terminé
  bool get isCompleted => status == DuelStatus.completed;

  /// Vérifie si c'est une égalité
  bool get isTie =>
      isCompleted &&
      challengerScore != null &&
      challengedScore != null &&
      challengerScore == challengedScore;

  /// Récupère le nom du gagnant
  String? get winnerName {
    if (winnerId == null) return null;
    if (winnerId == challengerId) return challengerName;
    if (winnerId == challengedId) return challengedName;
    return null;
  }
}
