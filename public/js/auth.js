// Auth guard — include on all protected pages
// Redirects to /login.html if not authenticated with AAL2 (password + TOTP)

async function checkAuth() {
    try {
        const { data: { session } } = await supabase.auth.getSession();
        if (!session) {
            window.location.href = '/login.html';
            return null;
        }

        // Check MFA assurance level
        const { data: { currentLevel } } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
        const { data: { totp } } = await supabase.auth.mfa.listFactors();
        var verifiedFactors = (totp || []).filter(function(f) { return f.status === 'verified'; });

        if (verifiedFactors.length === 0 || currentLevel !== 'aal2') {
            window.location.href = '/login.html';
            return null;
        }

        return session;
    } catch (err) {
        console.error('Auth check failed:', err);
        window.location.href = '/login.html';
        return null;
    }
}

async function getAccessToken() {
    var { data: { session } } = await supabase.auth.getSession();
    return session?.access_token;
}

async function logout() {
    await supabase.auth.signOut();
    window.location.href = '/login.html';
}

function showPage() {
    var loading = document.getElementById('page-loading');
    if (loading) loading.remove();
    var content = document.getElementById('page-content');
    if (content) content.style.display = '';
}

function renderNavbar(activePage) {
    var nav = document.getElementById('navbar');
    if (!nav) return;

    var links = nav.querySelector('.navbar-links');
    if (links) {
        links.querySelectorAll('a').forEach(function(a) {
            var href = a.getAttribute('href');
            if (href === '/' && activePage === 'dashboard') a.classList.add('active');
            else if (href === '/users.html' && activePage === 'users') a.classList.add('active');
            else a.classList.remove('active');
        });
    }
}

async function setNavbarUser() {
    var { data: { user } } = await supabase.auth.getUser();
    var el = document.getElementById('navbar-email');
    if (el && user) el.textContent = user.email;
}
