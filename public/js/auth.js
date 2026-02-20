// Auth guard — include on all protected pages
// Redirects to /login.html if not authenticated with AAL2 (password + TOTP)

async function checkAuth() {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) {
        window.location.href = '/login.html';
        return null;
    }

    // Check MFA assurance level
    const { data: { currentLevel } } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
    const { data: { totp } } = await supabase.auth.mfa.listFactors();
    const verifiedFactors = (totp || []).filter(f => f.status === 'verified');

    if (verifiedFactors.length === 0 || currentLevel !== 'aal2') {
        // Not fully authenticated — redirect to login for 2FA
        window.location.href = '/login.html';
        return null;
    }

    return session;
}

async function getAccessToken() {
    const { data: { session } } = await supabase.auth.getSession();
    return session?.access_token;
}

async function logout() {
    await supabase.auth.signOut();
    window.location.href = '/login.html';
}

function showPage() {
    document.getElementById('page-loading')?.remove();
    document.getElementById('page-content')?.style.removeProperty('display');
}

function renderNavbar(activePage) {
    const session = null; // Will be set after auth
    const nav = document.getElementById('navbar');
    if (!nav) return;

    const links = nav.querySelector('.navbar-links');
    if (links) {
        links.querySelectorAll('a').forEach(a => {
            const href = a.getAttribute('href');
            if (href === '/' && activePage === 'dashboard') a.classList.add('active');
            else if (href === '/users.html' && activePage === 'users') a.classList.add('active');
            else a.classList.remove('active');
        });
    }
}

// Set user email in navbar
async function setNavbarUser() {
    const { data: { user } } = await supabase.auth.getUser();
    const el = document.getElementById('navbar-email');
    if (el && user) el.textContent = user.email;
}
