// --- Elements ---
var alertEl = document.getElementById('alert');
var stepLogin = document.getElementById('step-login');
var stepSetup = document.getElementById('step-2fa-setup');
var stepVerify = document.getElementById('step-2fa-verify');

var currentFactorId = null;
var currentChallengeId = null;

// --- Check if already fully logged in ---
(async function checkExistingSession() {
    try {
        var { data: { session } } = await supabase.auth.getSession();
        if (!session) return;

        var { data: { totp } } = await supabase.auth.mfa.listFactors();
        var verifiedFactors = (totp || []).filter(function(f) { return f.status === 'verified'; });

        if (verifiedFactors.length > 0) {
            var { data: { currentLevel } } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
            if (currentLevel === 'aal2') {
                window.location.href = '/';
                return;
            }
            currentFactorId = verifiedFactors[0].id;
            await startChallenge();
            showStep('verify');
            setupTOTPInputs('verify-totp-inputs');
        } else {
            // No 2FA — need to set it up
            await enrollTOTP();
            showStep('setup');
            setupTOTPInputs('setup-totp-inputs');
        }
    } catch(e) {
        console.error('Session check error:', e);
    }
})();

// --- Helpers ---
function showAlert(msg, type) {
    alertEl.textContent = msg;
    alertEl.className = 'alert show alert-' + type;
    setTimeout(function() { alertEl.className = 'alert'; }, 5000);
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
    var container = document.getElementById(containerId);
    var inputs = container.querySelectorAll('.totp-digit');

    inputs.forEach(function(input, i) {
        input.addEventListener('input', function(e) {
            var val = e.target.value.replace(/\D/g, '');
            e.target.value = val.slice(-1);
            if (val && i < inputs.length - 1) inputs[i + 1].focus();
        });

        input.addEventListener('keydown', function(e) {
            if (e.key === 'Backspace' && !e.target.value && i > 0) {
                inputs[i - 1].focus();
            }
        });

        input.addEventListener('paste', function(e) {
            e.preventDefault();
            var pasted = (e.clipboardData.getData('text') || '').replace(/\D/g, '').slice(0, 6);
            pasted.split('').forEach(function(ch, j) {
                if (inputs[j]) inputs[j].value = ch;
            });
            var focusIdx = Math.min(pasted.length, inputs.length - 1);
            inputs[focusIdx].focus();
        });
    });

    setTimeout(function() { if (inputs[0]) inputs[0].focus(); }, 100);
}

function getTOTPCode(containerId) {
    var inputs = document.getElementById(containerId).querySelectorAll('.totp-digit');
    return Array.from(inputs).map(function(i) { return i.value; }).join('');
}

function clearTOTPInputs(containerId) {
    var inputs = document.getElementById(containerId).querySelectorAll('.totp-digit');
    inputs.forEach(function(i) { i.value = ''; });
    if (inputs[0]) inputs[0].focus();
}

// --- Step 1: Login ---
document.getElementById('login-form').addEventListener('submit', async function(e) {
    e.preventDefault();
    var btn = document.getElementById('btn-login');
    var email = document.getElementById('email').value.trim();
    var password = document.getElementById('password').value;

    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span> Connexion...';

    var { data, error } = await supabase.auth.signInWithPassword({ email: email, password: password });

    if (error) {
        showAlert(error.message === 'Invalid login credentials'
            ? 'Email ou mot de passe incorrect'
            : error.message, 'error');
        btn.disabled = false;
        btn.textContent = 'Se connecter';
        return;
    }

    // Check MFA factors
    var { data: { totp } } = await supabase.auth.mfa.listFactors();
    var verifiedFactors = (totp || []).filter(function(f) { return f.status === 'verified'; });

    if (verifiedFactors.length > 0) {
        currentFactorId = verifiedFactors[0].id;
        await startChallenge();
        showStep('verify');
        setupTOTPInputs('verify-totp-inputs');
    } else {
        await enrollTOTP();
        showStep('setup');
        setupTOTPInputs('setup-totp-inputs');
    }

    btn.disabled = false;
    btn.textContent = 'Se connecter';
});

// --- Enroll TOTP ---
async function enrollTOTP() {
    var { data, error } = await supabase.auth.mfa.enroll({
        factorType: 'totp',
        friendlyName: 'Telephone'
    });

    if (error) {
        showAlert('Erreur lors de la configuration 2FA: ' + error.message, 'error');
        return;
    }

    currentFactorId = data.id;

    // Generate clean PNG QR code with qrcode lib
    var totpUri = data.totp.uri;
    var secret = data.totp.secret;
    var canvas = document.getElementById('qr-canvas');

    try {
        await QRCode.toCanvas(canvas, totpUri, {
            width: 260,
            margin: 2,
            color: { dark: '#000000', light: '#ffffff' }
        });
    } catch(e) {
        console.error('QR generation error:', e);
        // Fallback: use Supabase SVG
        if (data.totp.qr_code) {
            canvas.style.display = 'none';
            var img = document.createElement('img');
            img.src = data.totp.qr_code;
            img.width = 260;
            img.height = 260;
            img.alt = 'QR Code 2FA';
            canvas.parentNode.insertBefore(img, canvas);
        }
    }

    // Show secret key for manual entry
    var secretDisplay = document.getElementById('totp-secret-display');
    if (secretDisplay && secret) {
        secretDisplay.textContent = secret;
        secretDisplay.addEventListener('click', function() {
            navigator.clipboard.writeText(secret).then(function() {
                secretDisplay.style.borderColor = '#3fb950';
                setTimeout(function() { secretDisplay.style.borderColor = '#30363d'; }, 1500);
            });
        });
    }
}

// --- Start challenge ---
async function startChallenge() {
    var { data, error } = await supabase.auth.mfa.challenge({ factorId: currentFactorId });
    if (error) {
        showAlert('Erreur challenge 2FA: ' + error.message, 'error');
        return;
    }
    currentChallengeId = data.id;
}

// --- Step 2: Verify setup ---
document.getElementById('btn-verify-setup').addEventListener('click', async function() {
    var code = getTOTPCode('setup-totp-inputs');
    if (code.length !== 6) {
        showAlert('Entrez les 6 chiffres', 'error');
        return;
    }

    var btn = document.getElementById('btn-verify-setup');
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span> Verification...';

    await startChallenge();

    var { data, error } = await supabase.auth.mfa.verify({
        factorId: currentFactorId,
        challengeId: currentChallengeId,
        code: code
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
document.getElementById('btn-verify-totp').addEventListener('click', async function() {
    var code = getTOTPCode('verify-totp-inputs');
    if (code.length !== 6) {
        showAlert('Entrez les 6 chiffres', 'error');
        return;
    }

    var btn = document.getElementById('btn-verify-totp');
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span> Verification...';

    var { data, error } = await supabase.auth.mfa.verify({
        factorId: currentFactorId,
        challengeId: currentChallengeId,
        code: code
    });

    if (error) {
        showAlert('Code incorrect. Reessayez.', 'error');
        clearTOTPInputs('verify-totp-inputs');
        btn.disabled = false;
        btn.textContent = 'Verifier';
        await startChallenge();
        return;
    }

    window.location.href = '/';
});

// --- Allow Enter key on TOTP inputs ---
document.querySelectorAll('.totp-digit').forEach(function(input) {
    input.addEventListener('keydown', function(e) {
        if (e.key === 'Enter') {
            var wrapper = input.closest('.login-step');
            if (wrapper.id === 'step-2fa-setup') {
                document.getElementById('btn-verify-setup').click();
            } else if (wrapper.id === 'step-2fa-verify') {
                document.getElementById('btn-verify-totp').click();
            }
        }
    });
});
