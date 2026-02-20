// --- Elements ---
const alertEl = document.getElementById('alert');
const stepLogin = document.getElementById('step-login');
const stepSetup = document.getElementById('step-2fa-setup');
const stepVerify = document.getElementById('step-2fa-verify');

let currentFactorId = null;
let currentChallengeId = null;

// --- Check if already fully logged in ---
(async function checkExistingSession() {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) return;

    const { data: { totp } } = await supabase.auth.mfa.listFactors();
    const verifiedFactors = (totp || []).filter(f => f.status === 'verified');

    if (verifiedFactors.length > 0) {
        // Has 2FA — check assurance level
        const { data: { currentLevel } } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
        if (currentLevel === 'aal2') {
            window.location.href = '/';
            return;
        }
        // AAL1 with verified factors — need to verify 2FA
        currentFactorId = verifiedFactors[0].id;
        await startChallenge();
        showStep('verify');
    } else {
        // No 2FA — need to set it up
        await enrollTOTP();
        showStep('setup');
    }
})();

// --- Helpers ---
function showAlert(msg, type) {
    alertEl.textContent = msg;
    alertEl.className = `alert show alert-${type}`;
    setTimeout(() => { alertEl.className = 'alert'; }, 5000);
}

function showStep(step) {
    stepLogin.classList.remove('active');
    stepSetup.classList.remove('active');
    stepVerify.classList.remove('active');
    if (step === 'login') stepLogin.classList.add('active');
    else if (step === 'setup') stepSetup.classList.add('active');
    else if (step === 'verify') stepVerify.classList.add('active');
}

// --- TOTP digit inputs behavior ---
function setupTOTPInputs(containerId) {
    const container = document.getElementById(containerId);
    const inputs = container.querySelectorAll('.totp-digit');

    inputs.forEach((input, i) => {
        input.addEventListener('input', (e) => {
            const val = e.target.value.replace(/\D/g, '');
            e.target.value = val.slice(-1);
            if (val && i < inputs.length - 1) inputs[i + 1].focus();
        });

        input.addEventListener('keydown', (e) => {
            if (e.key === 'Backspace' && !e.target.value && i > 0) {
                inputs[i - 1].focus();
            }
        });

        input.addEventListener('paste', (e) => {
            e.preventDefault();
            const pasted = (e.clipboardData.getData('text') || '').replace(/\D/g, '').slice(0, 6);
            pasted.split('').forEach((ch, j) => {
                if (inputs[j]) inputs[j].value = ch;
            });
            const focusIdx = Math.min(pasted.length, inputs.length - 1);
            inputs[focusIdx].focus();
        });
    });

    // Focus first input
    setTimeout(() => inputs[0]?.focus(), 100);
}

function getTOTPCode(containerId) {
    const inputs = document.getElementById(containerId).querySelectorAll('.totp-digit');
    return Array.from(inputs).map(i => i.value).join('');
}

function clearTOTPInputs(containerId) {
    const inputs = document.getElementById(containerId).querySelectorAll('.totp-digit');
    inputs.forEach(i => { i.value = ''; });
    inputs[0]?.focus();
}

// --- Step 1: Login ---
document.getElementById('login-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = document.getElementById('btn-login');
    const email = document.getElementById('email').value.trim();
    const password = document.getElementById('password').value;

    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span> Connexion...';

    const { data, error } = await supabase.auth.signInWithPassword({ email, password });

    if (error) {
        showAlert(error.message === 'Invalid login credentials'
            ? 'Email ou mot de passe incorrect'
            : error.message, 'error');
        btn.disabled = false;
        btn.textContent = 'Se connecter';
        return;
    }

    // Check MFA factors
    const { data: { totp } } = await supabase.auth.mfa.listFactors();
    const verifiedFactors = (totp || []).filter(f => f.status === 'verified');

    if (verifiedFactors.length > 0) {
        // Has 2FA — verify
        currentFactorId = verifiedFactors[0].id;
        await startChallenge();
        showStep('verify');
        setupTOTPInputs('verify-totp-inputs');
    } else {
        // No 2FA — setup
        await enrollTOTP();
        showStep('setup');
        setupTOTPInputs('setup-totp-inputs');
    }

    btn.disabled = false;
    btn.textContent = 'Se connecter';
});

// --- Enroll TOTP ---
async function enrollTOTP() {
    const { data, error } = await supabase.auth.mfa.enroll({
        factorType: 'totp',
        friendlyName: 'Telephone'
    });

    if (error) {
        showAlert('Erreur lors de la configuration 2FA: ' + error.message, 'error');
        return;
    }

    currentFactorId = data.id;

    // Display QR code
    const qrContainer = document.getElementById('qr-code');
    if (data.totp?.qr_code) {
        qrContainer.innerHTML = `<img src="${data.totp.qr_code}" alt="QR Code 2FA" width="200" height="200">`;
    }
}

// --- Start challenge ---
async function startChallenge() {
    const { data, error } = await supabase.auth.mfa.challenge({ factorId: currentFactorId });
    if (error) {
        showAlert('Erreur challenge 2FA: ' + error.message, 'error');
        return;
    }
    currentChallengeId = data.id;
}

// --- Step 2: Verify setup ---
document.getElementById('btn-verify-setup').addEventListener('click', async () => {
    const code = getTOTPCode('setup-totp-inputs');
    if (code.length !== 6) {
        showAlert('Entrez les 6 chiffres', 'error');
        return;
    }

    const btn = document.getElementById('btn-verify-setup');
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span> Verification...';

    // Challenge then verify
    await startChallenge();

    const { data, error } = await supabase.auth.mfa.verify({
        factorId: currentFactorId,
        challengeId: currentChallengeId,
        code
    });

    if (error) {
        showAlert('Code incorrect. Reessayez.', 'error');
        clearTOTPInputs('setup-totp-inputs');
        btn.disabled = false;
        btn.textContent = 'Activer la 2FA';
        return;
    }

    window.location.href = '/';
});

// --- Step 3: Verify login ---
document.getElementById('btn-verify-totp').addEventListener('click', async () => {
    const code = getTOTPCode('verify-totp-inputs');
    if (code.length !== 6) {
        showAlert('Entrez les 6 chiffres', 'error');
        return;
    }

    const btn = document.getElementById('btn-verify-totp');
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span> Verification...';

    const { data, error } = await supabase.auth.mfa.verify({
        factorId: currentFactorId,
        challengeId: currentChallengeId,
        code
    });

    if (error) {
        showAlert('Code incorrect. Reessayez.', 'error');
        clearTOTPInputs('verify-totp-inputs');
        btn.disabled = false;
        btn.textContent = 'Verifier';
        // Create a new challenge for retry
        await startChallenge();
        return;
    }

    window.location.href = '/';
});

// --- Allow Enter key on TOTP inputs ---
document.querySelectorAll('.totp-digit').forEach(input => {
    input.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
            const wrapper = input.closest('.login-step');
            if (wrapper.id === 'step-2fa-setup') {
                document.getElementById('btn-verify-setup').click();
            } else if (wrapper.id === 'step-2fa-verify') {
                document.getElementById('btn-verify-totp').click();
            }
        }
    });
});
