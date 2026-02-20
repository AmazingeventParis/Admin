var currentUserId = null;
var currentUserEmail = null;

var alertUsers = document.getElementById('alert-users');

function showUsersAlert(msg, type) {
    alertUsers.textContent = msg;
    alertUsers.className = 'alert show alert-' + type;
    setTimeout(function() { alertUsers.className = 'alert'; }, 4000);
}

function showModalAlert(id, msg, type) {
    var el = document.getElementById(id);
    if (!el) return;
    el.textContent = msg;
    el.className = 'alert show alert-' + type;
    setTimeout(function() { el.className = 'alert'; }, 4000);
}

// --- API helper ---
async function apiCall(method, url, body) {
    var token = await getAccessToken();
    var opts = {
        method: method,
        headers: {
            'Authorization': 'Bearer ' + token,
            'Content-Type': 'application/json'
        }
    };
    if (body) opts.body = JSON.stringify(body);
    var res = await fetch(url, opts);
    return res.json();
}

// --- Load users ---
async function loadUsers() {
    var data = await apiCall('GET', '/api/admin/users');
    if (data.error) {
        showUsersAlert(data.error, 'error');
        return;
    }

    var tbody = document.getElementById('users-tbody');

    if (!data.users || data.users.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" style="text-align:center;color:#8b949e;padding:40px;">Aucun utilisateur</td></tr>';
        return;
    }

    data.users.sort(function(a, b) { return new Date(b.created_at) - new Date(a.created_at); });

    tbody.innerHTML = data.users.map(function(u) {
        var mfaClass = u.mfa_enabled ? 'mfa-active' : 'mfa-inactive';
        var mfaText = u.mfa_enabled ? '2FA actif' : 'Pas de 2FA';
        var lastLogin = u.last_sign_in_at ? formatDate(u.last_sign_in_at) : '<span style="color:#484f58">Jamais</span>';
        var resetBtn = u.mfa_enabled ? '<button class="btn-small btn-info" onclick="resetMFA(\'' + u.id + '\', \'' + escapeHtml(u.email) + '\')">Reset 2FA</button>' : '';

        return '<tr>' +
            '<td><strong>' + escapeHtml(u.email) + '</strong></td>' +
            '<td><span class="mfa-badge ' + mfaClass + '">' + mfaText + '</span></td>' +
            '<td>' + formatDate(u.created_at) + '</td>' +
            '<td>' + lastLogin + '</td>' +
            '<td><div class="actions-cell">' +
                '<button class="btn-small btn-info" onclick="openResetModal(\'' + u.id + '\', \'' + escapeHtml(u.email) + '\')">Mot de passe</button>' +
                resetBtn +
                '<button class="btn-small btn-danger" onclick="openDeleteModal(\'' + u.id + '\', \'' + escapeHtml(u.email) + '\')">Supprimer</button>' +
            '</div></td>' +
        '</tr>';
    }).join('');
}

// --- Create user ---
function openCreateModal() {
    document.getElementById('new-email').value = '';
    document.getElementById('new-password').value = '';
    document.getElementById('modal-create').classList.add('show');
    document.getElementById('new-email').focus();
}

function closeCreateModal() {
    document.getElementById('modal-create').classList.remove('show');
}

async function createUser() {
    var email = document.getElementById('new-email').value.trim();
    var password = document.getElementById('new-password').value;

    if (!email || !password) {
        showModalAlert('alert-modal', 'Remplissez tous les champs', 'error');
        return;
    }
    if (password.length < 6) {
        showModalAlert('alert-modal', 'Le mot de passe doit faire au moins 6 caracteres', 'error');
        return;
    }

    var btn = document.getElementById('btn-create-user');
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span>';

    var data = await apiCall('POST', '/api/admin/users', { email: email, password: password });

    if (data.error) {
        showModalAlert('alert-modal', data.error, 'error');
        btn.disabled = false;
        btn.textContent = 'Creer';
        return;
    }

    closeCreateModal();
    showUsersAlert('Utilisateur ' + email + ' cree avec succes', 'success');
    btn.disabled = false;
    btn.textContent = 'Creer';
    loadUsers();
}

// --- Reset password ---
function openResetModal(id, email) {
    currentUserId = id;
    currentUserEmail = email;
    document.getElementById('reset-email').textContent = email;
    document.getElementById('reset-password').value = '';
    document.getElementById('modal-reset').classList.add('show');
    document.getElementById('reset-password').focus();
}

function closeResetModal() {
    document.getElementById('modal-reset').classList.remove('show');
}

async function resetPassword() {
    var password = document.getElementById('reset-password').value;
    if (!password || password.length < 6) {
        showModalAlert('alert-reset', 'Le mot de passe doit faire au moins 6 caracteres', 'error');
        return;
    }

    var btn = document.getElementById('btn-reset-password');
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span>';

    var data = await apiCall('POST', '/api/admin/users/' + currentUserId + '/reset-password', { password: password });

    if (data.error) {
        showModalAlert('alert-reset', data.error, 'error');
        btn.disabled = false;
        btn.textContent = 'Modifier';
        return;
    }

    closeResetModal();
    showUsersAlert('Mot de passe modifie pour ' + currentUserEmail, 'success');
    btn.disabled = false;
    btn.textContent = 'Modifier';
}

// --- Reset MFA ---
async function resetMFA(id, email) {
    if (!confirm('Reinitialiser la 2FA de ' + email + ' ?\nL\'utilisateur devra reconfigurer son app d\'authentification.')) return;

    var data = await apiCall('DELETE', '/api/admin/users/' + id + '/mfa');
    if (data.error) {
        showUsersAlert(data.error, 'error');
        return;
    }

    showUsersAlert('2FA reinitialise pour ' + email, 'success');
    loadUsers();
}

// --- Delete user ---
function openDeleteModal(id, email) {
    currentUserId = id;
    currentUserEmail = email;
    document.getElementById('delete-email').textContent = email;
    document.getElementById('modal-delete').classList.add('show');
}

function closeDeleteModal() {
    document.getElementById('modal-delete').classList.remove('show');
}

async function confirmDelete() {
    var btn = document.getElementById('btn-confirm-delete');
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span>';

    var data = await apiCall('DELETE', '/api/admin/users/' + currentUserId);

    if (data.error) {
        closeDeleteModal();
        showUsersAlert(data.error, 'error');
        btn.disabled = false;
        btn.textContent = 'Supprimer';
        return;
    }

    closeDeleteModal();
    showUsersAlert('Utilisateur ' + currentUserEmail + ' supprime', 'success');
    btn.disabled = false;
    btn.textContent = 'Supprimer';
    loadUsers();
}

// --- Helpers ---
function escapeHtml(str) {
    var div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
}

function formatDate(dateStr) {
    var d = new Date(dateStr);
    return d.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit', year: 'numeric' })
        + ' ' + d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
}

// --- Close modals on backdrop click ---
document.querySelectorAll('.modal-overlay').forEach(function(overlay) {
    overlay.addEventListener('click', function(e) {
        if (e.target === overlay) overlay.classList.remove('show');
    });
});

// --- Close modals on Escape ---
document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        document.querySelectorAll('.modal-overlay.show').forEach(function(m) { m.classList.remove('show'); });
    }
});

// --- Init ---
(async function() {
    try {
        var session = await checkAuth();
        if (!session) return;
        renderNavbar('users');
        await setNavbarUser();
        showPage();
        loadUsers();
    } catch(e) {
        console.error('Users init error:', e);
        window.location.href = '/login.html';
    }
})();
