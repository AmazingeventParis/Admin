// Configuration Supabase
const SUPABASE_URL = 'https://icujwpwicsmyuyidubqf.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImljdWp3cHdpY3NteXV5aWR1YnFmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAxMTk5NjEsImV4cCI6MjA4NTY5NTk2MX0.PddUsHjUcHaJfeDciB8BYAVE50oNWG9AwkLLYjMFUl4';

// Initialiser Supabase
const supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Variables globales
let generatedProfiles = [];

// Charger les stats au démarrage
document.addEventListener('DOMContentLoaded', () => {
    loadStats();
    loadUsers();
});

// Charger les statistiques
async function loadStats() {
    try {
        // Total utilisateurs
        const { data: players, error: playersError } = await supabaseClient
            .from('players')
            .select('id, device_id');

        if (playersError) throw playersError;

        const totalUsers = players ? players.length : 0;
        const fakeUsers = players ? players.filter(p => p.device_id && p.device_id.startsWith('fake_')).length : 0;
        const realUsers = totalUsers - fakeUsers;

        document.getElementById('totalUsers').textContent = totalUsers;
        document.getElementById('realUsers').textContent = realUsers;
        document.getElementById('fakeUsers').textContent = fakeUsers;

        // Stats globales
        const { data: stats, error: statsError } = await supabaseClient
            .from('player_stats')
            .select('games_played, high_score');

        if (statsError) throw statsError;

        let totalGames = 0;
        let bestScore = 0;

        if (stats) {
            stats.forEach(s => {
                totalGames += s.games_played || 0;
                if (s.high_score > bestScore) bestScore = s.high_score;
            });
        }

        document.getElementById('totalGames').textContent = totalGames;
        document.getElementById('bestScore').textContent = formatNumber(bestScore);

        showToast('Statistiques mises à jour', 'success');
    } catch (error) {
        console.error('Erreur chargement stats:', error);
        showToast('Erreur de chargement', 'error');
    }
}

// Charger la liste des utilisateurs
async function loadUsers() {
    try {
        const { data: players, error } = await supabaseClient
            .from('players')
            .select(`
                id,
                username,
                device_id,
                photo_url,
                created_at,
                player_stats (
                    games_played,
                    high_score
                )
            `)
            .order('created_at', { ascending: false });

        if (error) throw error;

        // Récupérer le filtre sélectionné
        const filterSelect = document.getElementById('userFilter');
        const filter = filterSelect ? filterSelect.value : 'all';

        const tbody = document.getElementById('usersTableBody');
        tbody.innerHTML = '';

        if (players && players.length > 0) {
            // Filtrer les joueurs
            let filteredPlayers = players.filter(player => {
                const isFake = player.device_id && player.device_id.startsWith('fake_');
                if (filter === 'real') return !isFake;
                if (filter === 'fake') return isFake;
                return true; // 'all'
            });

            // Trier par score (du plus haut au plus bas)
            filteredPlayers.sort((a, b) => {
                const scoreA = a.player_stats ? (Array.isArray(a.player_stats) ? (a.player_stats[0]?.high_score || 0) : (a.player_stats.high_score || 0)) : 0;
                const scoreB = b.player_stats ? (Array.isArray(b.player_stats) ? (b.player_stats[0]?.high_score || 0) : (b.player_stats.high_score || 0)) : 0;
                return scoreB - scoreA;
            });

            if (filteredPlayers.length === 0) {
                tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;color:rgba(255,255,255,0.5);">Aucun utilisateur dans cette catégorie</td></tr>';
                return;
            }

            filteredPlayers.forEach(player => {
                const isFake = player.device_id && player.device_id.startsWith('fake_');

                // Gérer player_stats comme objet OU array
                let stats = { games_played: 0, high_score: 0 };
                if (player.player_stats) {
                    if (Array.isArray(player.player_stats) && player.player_stats[0]) {
                        stats = player.player_stats[0];
                    } else if (typeof player.player_stats === 'object') {
                        stats = player.player_stats;
                    }
                }

                // Utiliser photo_url directement
                const photoUrl = player.photo_url || '';

                const row = document.createElement('tr');
                row.innerHTML = `
                    <td>
                        ${photoUrl ?
                            `<img src="${photoUrl}" alt="${player.username}" onerror="this.src='https://via.placeholder.com/40'">` :
                            `<div style="width:40px;height:40px;border-radius:50%;background:linear-gradient(135deg,#ff6b9d,#ffc371);display:flex;align-items:center;justify-content:center;font-weight:bold;">${player.username ? player.username[0].toUpperCase() : '?'}</div>`
                        }
                    </td>
                    <td>${player.username || 'Anonyme'}</td>
                    <td><span class="type-badge ${isFake ? 'fake' : 'real'}">${isFake ? 'Bot' : 'Réel'}</span></td>
                    <td>${stats.games_played || 0}</td>
                    <td>${formatNumber(stats.high_score || 0)}</td>
                    <td>
                        ${isFake ? `<button class="btn btn-play" onclick="openPlayModal('${player.id}', '${player.username}')">🎮 Jouer</button>` : ''}
                        <button class="btn btn-edit" onclick="editScore('${player.id}', ${stats.high_score || 0})">✏️ Score</button>
                        <button class="btn btn-delete" onclick="deleteUser('${player.id}')">🗑️ Supprimer</button>
                    </td>
                `;
                tbody.appendChild(row);
            });
        } else {
            tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;color:rgba(255,255,255,0.5);">Aucun utilisateur</td></tr>';
        }
    } catch (error) {
        console.error('Erreur chargement utilisateurs:', error);
    }
}

// Générer des faux profils
async function generateProfiles() {
    console.log('Génération des profils...');

    const countInput = document.getElementById('profileCount');
    const nationalityInput = document.getElementById('nationality');
    const genderInput = document.getElementById('gender');
    const minScoreInput = document.getElementById('minScore');
    const maxScoreInput = document.getElementById('maxScore');

    if (!countInput || !nationalityInput || !genderInput) {
        console.error('Éléments non trouvés');
        alert('Erreur: éléments non trouvés');
        return;
    }

    const count = parseInt(countInput.value) || 5;
    const nationality = nationalityInput.value;
    const gender = genderInput.value;
    const minScore = parseInt(minScoreInput.value) || 1000;
    const maxScore = parseInt(maxScoreInput.value) || 15000;

    const loadingEl = document.getElementById('loading');
    const previewEl = document.getElementById('previewSection');

    if (loadingEl) loadingEl.style.display = 'block';
    if (previewEl) previewEl.style.display = 'none';

    try {
        // Appel à l'API randomuser.me
        let url = `https://randomuser.me/api/?results=${count}&inc=name,picture`;
        if (nationality) {
            url += `&nat=${nationality}`;
        }
        if (gender) {
            url += `&gender=${gender}`;
        }

        console.log('Appel API:', url);

        const response = await fetch(url);

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const data = await response.json();
        console.log('Données reçues:', data);

        if (data.results && data.results.length > 0) {
            // S'assurer que min <= max
            const scoreMin = Math.min(minScore, maxScore);
            const scoreMax = Math.max(minScore, maxScore);
            const scoreRange = scoreMax - scoreMin;

            generatedProfiles = data.results.map(user => {
                const highScore = Math.floor(Math.random() * scoreRange) + scoreMin;
                return {
                    name: user.name.first,
                    photo: user.picture.large,
                    // Générer des stats aléatoires réalistes basées sur le score
                    games_played: Math.floor(Math.random() * 100) + 10,
                    high_score: highScore,
                    total_score: highScore * (Math.floor(Math.random() * 5) + 3),
                    total_lines_cleared: Math.floor(highScore / 50) + Math.floor(Math.random() * 100),
                    total_play_time_seconds: Math.floor(Math.random() * 36000) + 3600,
                    best_combo: Math.floor(Math.random() * 8) + 2
                };
            });

            console.log('Profils générés:', generatedProfiles);
            displayPreview();
            showToast(`${generatedProfiles.length} profils générés!`, 'success');
        } else {
            throw new Error('Aucun résultat de l\'API');
        }
    } catch (error) {
        console.error('Erreur génération profils:', error);
        showToast('Erreur: ' + error.message, 'error');
        alert('Erreur de génération: ' + error.message);
    } finally {
        if (loadingEl) loadingEl.style.display = 'none';
    }
}

// Afficher l'aperçu des profils générés
function displayPreview() {
    const container = document.getElementById('profilesPreview');
    container.innerHTML = '';

    generatedProfiles.forEach(profile => {
        const card = document.createElement('div');
        card.className = 'profile-card';
        card.innerHTML = `
            <img src="${profile.photo}" alt="${profile.name}">
            <div class="name">${profile.name}</div>
            <div class="score">Score: ${formatNumber(profile.high_score)}</div>
            <div class="score">${profile.games_played} parties</div>
        `;
        container.appendChild(card);
    });

    document.getElementById('previewSection').style.display = 'block';
}

// Annuler la génération
function cancelProfiles() {
    generatedProfiles = [];
    document.getElementById('previewSection').style.display = 'none';
}

// Confirmer et ajouter les profils à la base
async function confirmProfiles() {
    if (generatedProfiles.length === 0) return;

    document.getElementById('loading').style.display = 'block';

    try {
        let successCount = 0;

        for (const profile of generatedProfiles) {
            // Créer un device_id unique pour les faux profils
            const fakeDeviceId = `fake_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

            // Insérer le joueur avec photo_url
            const { data: playerData, error: playerError } = await supabaseClient
                .from('players')
                .insert({
                    device_id: fakeDeviceId,
                    username: profile.name,
                    photo_url: profile.photo
                })
                .select('id')
                .single();

            if (playerError) {
                console.error('Erreur création joueur:', playerError);
                continue;
            }

            // Insérer les stats
            const { error: statsError } = await supabaseClient
                .from('player_stats')
                .insert({
                    player_id: playerData.id,
                    games_played: profile.games_played,
                    high_score: profile.high_score,
                    total_score: profile.total_score,
                    total_lines_cleared: profile.total_lines_cleared,
                    total_play_time_seconds: profile.total_play_time_seconds,
                    best_combo: profile.best_combo
                });

            if (statsError) {
                console.error('Erreur création stats:', statsError);
            } else {
                successCount++;
            }
        }

        showToast(`${successCount} profils ajoutés avec succès!`, 'success');

        // Rafraîchir les données
        generatedProfiles = [];
        document.getElementById('previewSection').style.display = 'none';
        loadStats();
        loadUsers();

    } catch (error) {
        console.error('Erreur ajout profils:', error);
        showToast('Erreur lors de l\'ajout', 'error');
    } finally {
        document.getElementById('loading').style.display = 'none';
    }
}

// Modifier le score d'un faux profil
async function editScore(playerId, currentScore) {
    console.log('editScore appelé avec:', playerId, currentScore);

    const newScore = prompt(`Nouveau score pour ce joueur:\n(Score actuel: ${formatNumber(currentScore)})`, currentScore);

    if (newScore === null) return; // Annulé

    const score = parseInt(newScore);
    if (isNaN(score) || score < 0) {
        showToast('Score invalide', 'error');
        return;
    }

    try {
        console.log('Mise à jour score pour player_id:', playerId, 'nouveau score:', score);

        const { data, error } = await supabaseClient
            .from('player_stats')
            .update({ high_score: score })
            .eq('player_id', playerId)
            .select();

        console.log('Résultat update:', data, error);

        if (error) throw error;

        showToast(`Score mis à jour: ${formatNumber(score)}`, 'success');

        // Attendre un peu puis rafraîchir
        setTimeout(() => {
            loadStats();
            loadUsers();
        }, 500);

    } catch (error) {
        console.error('Erreur modification score:', error);
        showToast('Erreur de modification', 'error');
    }
}

// Supprimer un utilisateur
async function deleteUser(userId) {
    if (!confirm('Supprimer ce profil ?')) return;

    try {
        // Supprimer d'abord les stats
        await supabaseClient
            .from('player_stats')
            .delete()
            .eq('player_id', userId);

        // Puis le joueur
        const { error } = await supabaseClient
            .from('players')
            .delete()
            .eq('id', userId);

        if (error) throw error;

        showToast('Profil supprimé', 'success');
        loadStats();
        loadUsers();

    } catch (error) {
        console.error('Erreur suppression:', error);
        showToast('Erreur de suppression', 'error');
    }
}

// Formater les nombres
function formatNumber(num) {
    if (num >= 1000000) {
        return (num / 1000000).toFixed(1) + 'M';
    } else if (num >= 1000) {
        return (num / 1000).toFixed(1) + 'K';
    }
    return num.toString();
}

// Afficher une notification toast
function showToast(message, type = 'success') {
    const toast = document.getElementById('toast');
    toast.textContent = message;
    toast.className = `toast ${type} show`;

    setTimeout(() => {
        toast.classList.remove('show');
    }, 3000);
}

// ============================================
// FONCTIONNALITÉS DUEL - JOUER EN TANT QUE BOT
// ============================================

let currentPlayerId = null;
let currentPlayerName = null;
let currentDuelId = null;
let currentOpponentScore = null;

// Ouvrir la modal de jeu
async function openPlayModal(playerId, playerName) {
    currentPlayerId = playerId;
    currentPlayerName = playerName;

    document.getElementById('playAsName').textContent = playerName;
    document.getElementById('playModal').style.display = 'flex';
    document.getElementById('playModalLoading').style.display = 'block';
    document.getElementById('playModalContent').style.display = 'none';

    await loadDuelsForPlayer(playerId);
}

// Fermer la modal de jeu
function closePlayModal() {
    document.getElementById('playModal').style.display = 'none';
    currentPlayerId = null;
    currentPlayerName = null;
}

// Charger les duels pour un joueur
async function loadDuelsForPlayer(playerId) {
    try {
        // Charger les duels où ce joueur est impliqué
        const { data: duels, error } = await supabaseClient
            .from('duels')
            .select(`
                id,
                seed,
                status,
                challenger_id,
                challenged_id,
                challenger_score,
                challenged_score,
                created_at
            `)
            .or(`challenger_id.eq.${playerId},challenged_id.eq.${playerId}`)
            .in('status', ['pending', 'active'])
            .order('created_at', { ascending: false });

        if (error) throw error;

        // Charger tous les joueurs pour les infos
        const { data: players } = await supabaseClient
            .from('players')
            .select('id, username, photo_url');

        const playersMap = {};
        players?.forEach(p => playersMap[p.id] = p);

        // Séparer les duels en attente et actifs
        const pendingDuels = [];
        const activeDuels = [];

        duels?.forEach(duel => {
            const isChallenger = duel.challenger_id === playerId;
            const opponentId = isChallenger ? duel.challenged_id : duel.challenger_id;
            const opponent = playersMap[opponentId] || { username: 'Inconnu', photo_url: null };

            const duelInfo = {
                ...duel,
                isChallenger,
                opponent,
                myScore: isChallenger ? duel.challenger_score : duel.challenged_score,
                opponentScore: isChallenger ? duel.challenged_score : duel.challenger_score
            };

            if (duel.status === 'pending') {
                if (isChallenger) {
                    // Le challenger peut jouer immédiatement après avoir créé le défi
                    if (duelInfo.myScore === null) {
                        activeDuels.push(duelInfo);
                    }
                } else {
                    // Le challenged doit accepter d'abord
                    pendingDuels.push(duelInfo);
                }
            } else if (duel.status === 'active') {
                // Si on n'a pas encore soumis son score
                if (duelInfo.myScore === null) {
                    activeDuels.push(duelInfo);
                }
            }
        });

        // Afficher les duels en attente
        displayPendingDuels(pendingDuels);
        displayActiveDuels(activeDuels);

        // Charger la liste des joueurs pour défier
        await loadPlayersForChallenge(playerId, players);

        document.getElementById('playModalLoading').style.display = 'none';
        document.getElementById('playModalContent').style.display = 'block';

    } catch (error) {
        console.error('Erreur chargement duels:', error);
        showToast('Erreur chargement duels', 'error');
    }
}

// Afficher les duels en attente
function displayPendingDuels(duels) {
    const container = document.getElementById('pendingDuelsList');

    if (duels.length === 0) {
        container.innerHTML = '<div class="no-duels">Aucun duel en attente</div>';
        return;
    }

    container.innerHTML = duels.map(duel => `
        <div class="duel-card">
            <div class="duel-info">
                ${duel.opponent.photo_url
                    ? `<img src="${duel.opponent.photo_url}" alt="${duel.opponent.username}">`
                    : `<div style="width:45px;height:45px;border-radius:50%;background:linear-gradient(135deg,#ff6b9d,#ffc371);display:flex;align-items:center;justify-content:center;font-weight:bold;">${duel.opponent.username?.[0] || '?'}</div>`
                }
                <div class="duel-details">
                    <span class="opponent-name">${duel.opponent.username || 'Inconnu'}</span>
                    <span class="duel-status">Vous a défié</span>
                </div>
            </div>
            <div class="duel-actions">
                <button class="btn btn-accept" onclick="acceptDuel('${duel.id}')">✅ Accepter</button>
                <button class="btn btn-decline" onclick="declineDuel('${duel.id}')">❌ Refuser</button>
            </div>
        </div>
    `).join('');
}

// Afficher les duels actifs
function displayActiveDuels(duels) {
    const container = document.getElementById('activeDuelsList');

    if (duels.length === 0) {
        container.innerHTML = '<div class="no-duels">Aucun duel actif à jouer</div>';
        return;
    }

    container.innerHTML = duels.map(duel => `
        <div class="duel-card">
            <div class="duel-info">
                ${duel.opponent.photo_url
                    ? `<img src="${duel.opponent.photo_url}" alt="${duel.opponent.username}">`
                    : `<div style="width:45px;height:45px;border-radius:50%;background:linear-gradient(135deg,#ff6b9d,#ffc371);display:flex;align-items:center;justify-content:center;font-weight:bold;">${duel.opponent.username?.[0] || '?'}</div>`
                }
                <div class="duel-details">
                    <span class="opponent-name">VS ${duel.opponent.username || 'Inconnu'}</span>
                    <span class="duel-status">
                        ${duel.opponentScore !== null
                            ? `Score adversaire: <span class="duel-score">${formatNumber(duel.opponentScore)}</span>`
                            : 'Adversaire n\'a pas encore joué'
                        }
                    </span>
                </div>
            </div>
            <div class="duel-actions">
                <button class="btn btn-play" onclick="openSimulateModal('${duel.id}', ${duel.opponentScore}, '${duel.opponent.username}', ${duel.isChallenger})">🎮 Jouer</button>
            </div>
        </div>
    `).join('');
}

// Charger les joueurs pour défier
async function loadPlayersForChallenge(currentId, players) {
    const select = document.getElementById('challengeTarget');
    select.innerHTML = '<option value="">Sélectionner un joueur...</option>';

    players?.filter(p => p.id !== currentId).forEach(player => {
        const option = document.createElement('option');
        option.value = player.id;
        option.textContent = player.username || 'Anonyme';
        select.appendChild(option);
    });
}

// Accepter un duel
async function acceptDuel(duelId) {
    try {
        const { error } = await supabaseClient
            .from('duels')
            .update({ status: 'active' })
            .eq('id', duelId);

        if (error) throw error;

        showToast('Duel accepté!', 'success');
        await loadDuelsForPlayer(currentPlayerId);

    } catch (error) {
        console.error('Erreur acceptation:', error);
        showToast('Erreur acceptation', 'error');
    }
}

// Refuser un duel
async function declineDuel(duelId) {
    try {
        const { error } = await supabaseClient
            .from('duels')
            .update({ status: 'declined' })
            .eq('id', duelId);

        if (error) throw error;

        showToast('Duel refusé', 'success');
        await loadDuelsForPlayer(currentPlayerId);

    } catch (error) {
        console.error('Erreur refus:', error);
        showToast('Erreur refus', 'error');
    }
}

// Créer un défi
async function createChallenge() {
    const targetId = document.getElementById('challengeTarget').value;
    if (!targetId) {
        showToast('Sélectionnez un joueur', 'error');
        return;
    }

    try {
        // Générer un seed aléatoire
        const seed = Math.floor(Math.random() * 2147483647);

        const { error } = await supabaseClient
            .from('duels')
            .insert({
                challenger_id: currentPlayerId,
                challenged_id: targetId,
                seed: seed,
                status: 'pending'
            });

        if (error) throw error;

        showToast('Défi envoyé!', 'success');
        document.getElementById('challengeTarget').value = '';
        await loadDuelsForPlayer(currentPlayerId);

    } catch (error) {
        console.error('Erreur création défi:', error);
        showToast('Erreur création défi', 'error');
    }
}

// Ouvrir la modal de simulation
function openSimulateModal(duelId, opponentScore, opponentName, isChallenger) {
    currentDuelId = duelId;
    currentOpponentScore = opponentScore;

    let info = `Duel contre <strong>${opponentName}</strong>`;
    if (opponentScore !== null) {
        info += `<br>Score à battre: <strong style="color:#ffc371">${formatNumber(opponentScore)}</strong>`;
    } else {
        info += `<br>L'adversaire n'a pas encore joué`;
    }

    document.getElementById('simulateInfo').innerHTML = info;
    document.getElementById('simulateModal').style.display = 'flex';

    // Suggérer un score aléatoire réaliste
    const suggestedScore = Math.floor(Math.random() * 10000) + 2000;
    document.getElementById('simulateScore').value = suggestedScore;
}

// Fermer la modal de simulation
function closeSimulateModal() {
    document.getElementById('simulateModal').style.display = 'none';
    currentDuelId = null;
    currentOpponentScore = null;
}

// Soumettre le score simulé
async function submitSimulatedScore() {
    const score = parseInt(document.getElementById('simulateScore').value);

    if (isNaN(score) || score < 0) {
        showToast('Score invalide', 'error');
        return;
    }

    try {
        // Récupérer le duel pour savoir si on est challenger ou challenged
        const { data: duel, error: duelError } = await supabaseClient
            .from('duels')
            .select('*')
            .eq('id', currentDuelId)
            .single();

        if (duelError) throw duelError;

        const isChallenger = duel.challenger_id === currentPlayerId;
        const scoreField = isChallenger ? 'challenger_score' : 'challenged_score';
        const opponentScoreField = isChallenger ? 'challenged_score' : 'challenger_score';

        // Vérifier si l'adversaire a aussi joué
        const opponentScore = duel[opponentScoreField];
        let updateData = { [scoreField]: score };

        // Si les deux ont joué, déterminer le gagnant
        if (opponentScore !== null) {
            let winnerId = null;
            if (score > opponentScore) {
                winnerId = currentPlayerId;
            } else if (opponentScore > score) {
                winnerId = isChallenger ? duel.challenged_id : duel.challenger_id;
            }
            // En cas d'égalité, winner_id reste null

            updateData.status = 'completed';
            updateData.winner_id = winnerId;
        }

        const { error } = await supabaseClient
            .from('duels')
            .update(updateData)
            .eq('id', currentDuelId);

        if (error) throw error;

        // Mettre à jour le high_score du bot si nécessaire
        await updateBotHighScore(currentPlayerId, score);

        closeSimulateModal();
        showToast(`Score ${formatNumber(score)} soumis!`, 'success');
        await loadDuelsForPlayer(currentPlayerId);

    } catch (error) {
        console.error('Erreur soumission score:', error);
        showToast('Erreur soumission', 'error');
    }
}

// Mettre à jour le high score du bot si le nouveau score est meilleur
async function updateBotHighScore(playerId, newScore) {
    try {
        const { data: stats } = await supabaseClient
            .from('player_stats')
            .select('high_score, games_played')
            .eq('player_id', playerId)
            .single();

        if (stats && newScore > (stats.high_score || 0)) {
            await supabaseClient
                .from('player_stats')
                .update({
                    high_score: newScore,
                    games_played: (stats.games_played || 0) + 1
                })
                .eq('player_id', playerId);
        } else if (stats) {
            await supabaseClient
                .from('player_stats')
                .update({
                    games_played: (stats.games_played || 0) + 1
                })
                .eq('player_id', playerId);
        }
    } catch (error) {
        console.error('Erreur mise à jour high score:', error);
    }
}
