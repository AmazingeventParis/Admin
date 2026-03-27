const express = require('express');
const path = require('path');
const fs = require('fs');
const http = require('http');
const { execSync } = require('child_process');
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

// --- Server Stats helpers ---
function readRam() {
  try {
    const meminfo = fs.readFileSync('/proc/meminfo', 'utf-8');
    const memTotal = parseInt((meminfo.match(/MemTotal:\s+(\d+)/) || [])[1] || 0);
    const memAvailable = parseInt((meminfo.match(/MemAvailable:\s+(\d+)/) || [])[1] || 0);
    const totalGB = memTotal / 1024 / 1024;
    const usedGB = (memTotal - memAvailable) / 1024 / 1024;
    return { total_gb: Math.round(totalGB * 10) / 10, used_gb: Math.round(usedGB * 10) / 10, percent: Math.round((usedGB / totalGB) * 100) };
  } catch (e) { return { total_gb: 0, used_gb: 0, percent: 0 }; }
}

function readCpuSample() {
  const stat = fs.readFileSync('/proc/stat', 'utf-8');
  const parts = stat.split('\n')[0].replace(/^cpu\s+/, '').split(/\s+/).map(Number);
  const idle = parts[3] + (parts[4] || 0);
  return { idle, total: parts.reduce((a, b) => a + b, 0) };
}

function readDisk() {
  try {
    // List all physical partitions (/dev/*), pick the largest one
    const df = execSync('df -k 2>/dev/null', { encoding: 'utf-8' });
    const lines = df.trim().split('\n').slice(1);
    let best = null;
    for (const line of lines) {
      const cols = line.trim().split(/\s+/);
      if (cols.length < 5) continue;
      // Only real devices (skip overlay, tmpfs, etc.)
      if (cols[0].startsWith('/dev/')) {
        const totalKB = parseInt(cols[1]);
        const usedKB = parseInt(cols[2]);
        if (!best || totalKB > best.totalKB) {
          best = { totalKB, usedKB };
        }
      }
    }
    if (best) {
      return {
        total_gb: Math.round(best.totalKB / 1024 / 1024 * 10) / 10,
        used_gb: Math.round(best.usedKB / 1024 / 1024 * 10) / 10,
        percent: Math.round(best.usedKB / best.totalKB * 100)
      };
    }
  } catch (e) {}
  return { total_gb: 0, used_gb: 0, percent: 0 };
}

// --- Docker Container Monitoring ---
let dockerAvailable = false;
let containerStatsCache = [];
let dockerDiskCache = { volumes: [], imagesMB: 0 };

// Coolify API fallback config
const COOLIFY_API = process.env.COOLIFY_API || 'http://coolify:8000';
const COOLIFY_TOKEN = process.env.COOLIFY_TOKEN || '1|FNcssp3CipkrPNVSQyv3IboYwGsP8sjPskoBG3ux98e5a576';

function dockerGet(urlPath) {
  return new Promise((resolve, reject) => {
    const req = http.request(
      { socketPath: '/var/run/docker.sock', path: urlPath, method: 'GET' },
      (res) => {
        let body = '';
        res.on('data', chunk => body += chunk);
        res.on('end', () => {
          try { resolve(JSON.parse(body)); } catch (e) { reject(e); }
        });
      }
    );
    req.on('error', reject);
    req.setTimeout(15000, () => { req.destroy(); reject(new Error('timeout')); });
    req.end();
  });
}

function containerName(c) {
  const labels = c.Labels || {};
  if (labels['coolify.name']) return labels['coolify.name'];
  if (labels['com.docker.compose.service']) return labels['com.docker.compose.service'];
  const img = (c.Image || '').split('/').pop().split(':')[0].split('@')[0];
  if (img) return img;
  return (c.Names || ['/unknown'])[0].replace(/^\//, '');
}

function dockerCpuPercent(s) {
  if (!s.cpu_stats?.cpu_usage || !s.precpu_stats?.cpu_usage) return 0;
  const cd = s.cpu_stats.cpu_usage.total_usage - s.precpu_stats.cpu_usage.total_usage;
  const sd = (s.cpu_stats.system_cpu_usage || 0) - (s.precpu_stats.system_cpu_usage || 0);
  const n = s.cpu_stats.online_cpus || 1;
  return sd > 0 ? Math.round(cd / sd * n * 1000) / 10 : 0;
}

function dockerMemMB(s) {
  if (!s.memory_stats) return 0;
  const used = (s.memory_stats.usage || 0) - (s.memory_stats.stats?.inactive_file || 0);
  return Math.round(used / 1024 / 1024 * 10) / 10;
}

async function collectDockerStats() {
  try {
    const list = await dockerGet('/containers/json');
    if (!Array.isArray(list)) return;
    const results = await Promise.allSettled(list.map(async (c) => {
      const s = await dockerGet('/containers/' + c.Id + '/stats?stream=false');
      return { name: containerName(c), cpu: dockerCpuPercent(s), memMB: dockerMemMB(s) };
    }));
    containerStatsCache = results
      .filter(r => r.status === 'fulfilled')
      .map(r => r.value);
  } catch (e) {
    console.error('Docker stats collection error:', e.message);
  }
}

// Fallback: collect stats via Coolify execute API (runs docker stats on host)
async function collectDockerStatsViaCoolify() {
  try {
    const SERVER_UUID = 's0cw4wsowg8wkok4wkwsko44';
    const resp = await fetch(`${COOLIFY_API}/api/v1/servers/${SERVER_UUID}/commands`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${COOLIFY_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        command: "docker stats --no-stream --format '{{.Name}}\\t{{.MemUsage}}\\t{{.CPUPerc}}'"
      }),
    });
    if (!resp.ok) throw new Error(`Coolify API ${resp.status}`);
    const data = await resp.json();
    const output = data.result || data.output || '';
    if (!output) return;

    const lines = output.trim().split('\n').filter(l => l.trim());
    containerStatsCache = lines.map(line => {
      const parts = line.split('\t');
      const name = (parts[0] || '').trim();
      const memStr = (parts[1] || '').trim();
      const cpuStr = (parts[2] || '').trim();

      // Parse mem: "1.2GiB / 62.4GiB" or "256MiB / 62.4GiB"
      let memMB = 0;
      const memMatch = memStr.match(/([\d.]+)(MiB|GiB|KiB)/);
      if (memMatch) {
        memMB = parseFloat(memMatch[1]);
        if (memMatch[2] === 'GiB') memMB *= 1024;
        if (memMatch[2] === 'KiB') memMB /= 1024;
      }

      // Parse cpu: "1.23%"
      const cpu = parseFloat(cpuStr) || 0;

      return { name, cpu: Math.round(cpu * 10) / 10, memMB: Math.round(memMB * 10) / 10 };
    }).filter(c => c.name);
  } catch (e) {
    // Silently fail - will retry next interval
    if (containerStatsCache.length === 0) {
      console.log('Coolify stats fallback unavailable:', e.message);
    }
  }
}

async function collectDockerDisk() {
  try {
    const df = await dockerGet('/system/df');
    const vols = (df.Volumes || [])
      .map(v => ({ name: v.Name, mb: Math.round((v.UsageData?.Size || 0) / 1024 / 1024) }))
      .filter(v => v.mb > 0)
      .sort((a, b) => b.mb - a.mb);
    const imgMB = Math.round((df.Images || []).reduce((s, i) => s + (i.Size || 0), 0) / 1024 / 1024);
    dockerDiskCache = { volumes: vols, imagesMB: imgMB };
  } catch (e) {
    console.error('Docker disk collection error:', e.message);
  }
}

(function initDockerMonitoring() {
  if (fs.existsSync('/var/run/docker.sock')) {
    dockerAvailable = true;
    console.log('Docker monitoring enabled (socket)');
    collectDockerStats();
    collectDockerDisk();
    setInterval(collectDockerStats, 5000);
    setInterval(collectDockerDisk, 60000);
  } else {
    // Fallback: use Coolify API to run docker stats on the host
    dockerAvailable = true;
    console.log('Docker socket not found — using Coolify API fallback');
    collectDockerStatsViaCoolify();
    setInterval(collectDockerStatsViaCoolify, 10000);
  }
})();

// --- Remote Server Stats (Shootnbox 79.137.88.192 via monitor agent) ---
const SHOOTNBOX_MONITOR_URL = 'http://79.137.88.192:3333/stats?secret=swipego-monitor-2026';

async function readRemoteStats() {
  try {
    const resp = await fetch(SHOOTNBOX_MONITOR_URL);
    if (!resp.ok) return null;
    return await resp.json();
  } catch (e) {
    console.error('Remote stats error:', e.message);
    return null;
  }
}

// SSE stream for remote server (Shootnbox)
app.get('/api/server-stats-remote/stream', async (req, res, next) => {
  const token = req.query.token || req.headers.authorization?.replace('Bearer ', '');
  if (!token) return res.status(401).json({ error: 'Token manquant' });
  const { data: { user }, error } = await supabaseAdmin.auth.getUser(token);
  if (error || !user) return res.status(401).json({ error: 'Token invalide' });
  req.user = user;
  next();
}, (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'X-Accel-Buffering': 'no'
  });
  res.write(':\n\n');

  const sendStats = async () => {
    try {
      const stats = await readRemoteStats();
      if (stats) {
        res.write('data: ' + JSON.stringify({ ...stats, timestamp: Date.now() }) + '\n\n');
      }
    } catch (e) {
      console.error('Remote SSE error:', e.message);
    }
  };

  sendStats();
  const interval = setInterval(sendStats, 5000);
  req.on('close', () => clearInterval(interval));
});

// --- Server Stats SSE stream (real-time) ---
// EventSource can't set headers, so accept token as query param too
app.get('/api/server-stats/stream', async (req, res, next) => {
  const token = req.query.token || req.headers.authorization?.replace('Bearer ', '');
  if (!token) return res.status(401).json({ error: 'Token manquant' });
  const { data: { user }, error } = await supabaseAdmin.auth.getUser(token);
  if (error || !user) return res.status(401).json({ error: 'Token invalide' });
  req.user = user;
  next();
}, (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'X-Accel-Buffering': 'no'
  });
  res.write(':\n\n');

  let prevCpu = readCpuSample();
  let diskCache = readDisk();
  let diskTick = 0;

  const interval = setInterval(() => {
    try {
      const curCpu = readCpuSample();
      const idleDelta = curCpu.idle - prevCpu.idle;
      const totalDelta = curCpu.total - prevCpu.total;
      const cpuPercent = totalDelta > 0 ? Math.round((1 - idleDelta / totalDelta) * 100) : 0;
      prevCpu = curCpu;

      // Disk changes slowly — refresh every 30 ticks (~30s)
      if (diskTick++ % 30 === 0) diskCache = readDisk();

      const data = {
        cpu: { percent: cpuPercent },
        ram: readRam(),
        disk: diskCache,
        containers: dockerAvailable ? containerStatsCache : null,
        dockerDisk: dockerAvailable ? dockerDiskCache : null,
        timestamp: Date.now()
      };
      res.write('data: ' + JSON.stringify(data) + '\n\n');
    } catch (e) {
      console.error('SSE stats error:', e.message);
    }
  }, 1000);

  req.on('close', () => clearInterval(interval));
});

// --- Server Stats (single request fallback) ---
app.get('/api/server-stats', requireAuth, async (req, res) => {
  try {
    const s1 = readCpuSample();
    await new Promise(r => setTimeout(r, 200));
    const s2 = readCpuSample();
    const idleDelta = s2.idle - s1.idle;
    const totalDelta = s2.total - s1.total;
    const cpuPercent = totalDelta > 0 ? Math.round((1 - idleDelta / totalDelta) * 100) : 0;
    res.json({
      cpu: { percent: cpuPercent },
      ram: readRam(),
      disk: readDisk(),
      containers: dockerAvailable ? containerStatsCache : null,
      dockerDisk: dockerAvailable ? dockerDiskCache : null,
      timestamp: Date.now()
    });
  } catch (err) {
    res.status(500).json({ error: 'Erreur lecture stats serveur' });
  }
});

// --- API Keys Registry (protected) ---
// Priority: data/apis.json (local/volume) > APIS_DATA env var (base64) > empty
app.get('/api/apis', requireAuth, (req, res) => {
  try {
    const apisPath = path.join(__dirname, 'data', 'apis.json');
    let apis = [];
    if (fs.existsSync(apisPath)) {
      apis = JSON.parse(fs.readFileSync(apisPath, 'utf-8'));
    } else if (process.env.APIS_DATA) {
      apis = JSON.parse(Buffer.from(process.env.APIS_DATA, 'base64').toString('utf-8'));
    }
    res.json({ apis });
  } catch (err) {
    console.error('Error reading apis data:', err);
    res.status(500).json({ error: 'Erreur de lecture des donnees APIs' });
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
