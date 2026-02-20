const express = require('express');
const path = require('path');
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
