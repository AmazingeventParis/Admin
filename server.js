const express = require('express');
const path = require('path');
const fs = require('fs');
const { createClient } = require('@supabase/supabase-js');

const app = express();
app.use(express.json());

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://supabase-api.swipego.app';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc3MTI3NDIyMCwiZXhwIjo0OTI2OTQ3ODIwLCJyb2xlIjoiYW5vbiJ9.4c5wruvy-jj3M8fSjhmgR4FvdF6za-mgawlkB_B0uB0';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc3MTI3NDIyMCwiZXhwIjo0OTI2OTQ3ODIwLCJyb2xlIjoic2VydmljZV9yb2xlIn0.iqPsHjDWX9X2942nD1lsSin0yNvob06s0qP_FDTShns';

// Admin client (service_role — server-side only)
const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false }
});

// --- Auth middleware ---
async function requireAuth(req, res, next) {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!token) return res.status(401).json({ error: 'Token manquant' });

  const { data: { user }, error } = await supabaseAdmin.auth.getUser(token);
  if (error || !user) return res.status(401).json({ error: 'Token invalide' });

  req.user = user;
  next();
}

// --- API Routes ---

// List users
app.get('/api/admin/users', requireAuth, async (req, res) => {
  const { data, error } = await supabaseAdmin.auth.admin.listUsers();
  if (error) return res.status(500).json({ error: error.message });

  const users = data.users.map(u => ({
    id: u.id,
    email: u.email,
    created_at: u.created_at,
    last_sign_in_at: u.last_sign_in_at,
    mfa_enabled: (u.factors || []).some(f => f.status === 'verified')
  }));

  res.json({ users });
});

// Create user
app.post('/api/admin/users', requireAuth, async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'Email et mot de passe requis' });

  const { data, error } = await supabaseAdmin.auth.admin.createUser({
    email,
    password,
    email_confirm: true
  });

  if (error) return res.status(400).json({ error: error.message });
  res.json({ user: { id: data.user.id, email: data.user.email } });
});

// Delete user
app.delete('/api/admin/users/:id', requireAuth, async (req, res) => {
  const { id } = req.params;

  // Prevent self-deletion
  if (id === req.user.id) return res.status(400).json({ error: 'Impossible de supprimer votre propre compte' });

  const { error } = await supabaseAdmin.auth.admin.deleteUser(id);
  if (error) return res.status(400).json({ error: error.message });

  res.json({ success: true });
});

// Reset password for a user
app.post('/api/admin/users/:id/reset-password', requireAuth, async (req, res) => {
  const { id } = req.params;
  const { password } = req.body;
  if (!password) return res.status(400).json({ error: 'Mot de passe requis' });

  const { error } = await supabaseAdmin.auth.admin.updateUserById(id, { password });
  if (error) return res.status(400).json({ error: error.message });

  res.json({ success: true });
});

// Unenroll MFA factor for a user (admin reset)
app.delete('/api/admin/users/:id/mfa', requireAuth, async (req, res) => {
  const { id } = req.params;

  const { data: { user }, error: fetchErr } = await supabaseAdmin.auth.admin.getUserById(id);
  if (fetchErr) return res.status(400).json({ error: fetchErr.message });

  const factors = user.factors || [];
  for (const factor of factors) {
    // Use REST API directly since SDK has a UUID validation bug
    await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${id}/factors/${factor.id}`, {
      method: 'DELETE',
      headers: {
        'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
        'apikey': SUPABASE_SERVICE_KEY
      }
    });
  }

  res.json({ success: true });
});

// --- Infrastructure API (protected) ---
app.get('/api/infra', requireAuth, (req, res) => {
  res.json({
    serveur: {
      ip: '217.182.89.133',
      ssh: 'ubuntu@217.182.89.133',
      os: 'Ubuntu 24.04',
      specs: 'AMD EPYC 4344P, ADVANCE-2',
      disques: '2x NVMe 960GB RAID 1 (878GB utiles)',
      domaine: '*.swipego.app (wildcard DNS vers 217.182.89.133)'
    },
    coolify: {
      url: 'https://coolify.swipego.app',
      token_api: '1|FNcssp3CipkrPNVSQyv3IboYwGsP8sjPskoBG3ux98e5a576',
      serveur_uuid: 's0cw4wsowg8wkok4wkwsko44',
      projet_uuid: 'c4gw0sos0o4cgws4404s4cwk',
      deploy_api: 'GET http://217.182.89.133:8000/api/v1/deploy?uuid=<app-uuid>&force=true'
    },
    supabase: {
      dashboard: 'https://supabase.swipego.app',
      api: 'https://supabase-api.swipego.app',
      anon_key: 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc3MDkyNDEyMCwiZXhwIjo0OTI2NTk3NzIwLCJyb2xlIjoiYW5vbiJ9.JHskPtaedMotI1_Mdm7hRVBE5gezg0jxXwZkn6GF6as',
      service_role_key: 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc3MDkyNDEyMCwiZXhwIjo0OTI2NTk3NzIwLCJyb2xlIjoic2VydmljZV9yb2xlIn0.Oq-8cU8onT3ElqgqeDOyaUZYpUX1WhqsgScm_VsJDjA',
      dashboard_login: 'd1HAohWr6dYZr9Gp',
      dashboard_password: 'hV3QEImxbdcNWKqn47rrzWjXK9FCZoob',
      postgresql_password: 'JLcL0PtRUlKdG1q7rISAHBMc8RlJIHHd'
    },
    github: {
      organisation: 'AmazingeventParis',
      url: 'https://github.com/AmazingeventParis',
      login: 'AmazingeventParis',
      password: 'SachaEden5LauryTal2Mona!'
    },
    code_server: {
      url: 'https://code.swipego.app',
      password: 'Laurytal2'
    },
    projets_disponibles: [
      'kooki', 'cryptosignals', 'freqtrade', 'focusracer',
      'upload', 'optitourbooth', 'belotte', 'alice', 'admin', 'lcbconnect'
    ]
  });
});

// --- API Keys Registry (protected) ---
// Data loaded from data/apis.json (gitignored — secrets stay off GitHub)
app.get('/api/apis', requireAuth, (req, res) => {
  try {
    const apisPath = path.join(__dirname, 'data', 'apis.json');
    if (!fs.existsSync(apisPath)) {
      return res.json({ apis: [] });
    }
    const apis = JSON.parse(fs.readFileSync(apisPath, 'utf-8'));
    res.json({ apis });
  } catch (err) {
    console.error('Error reading apis.json:', err);
    res.status(500).json({ error: 'Erreur de lecture du fichier apis.json' });
  }
});

// --- Serve static files ---
app.use(express.static(path.join(__dirname, 'public')));

// SPA fallback — serve login for unknown routes
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'login.html'));
});

// --- Start ---
const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Admin Hub running on port ${PORT}`);
});
