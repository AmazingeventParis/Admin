const SUPABASE_URL = 'https://supabase-api.swipego.app';
const SUPABASE_ANON_KEY = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc3MDkyNDEyMCwiZXhwIjo0OTI2NTk3NzIwLCJyb2xlIjoiYW5vbiJ9.JHskPtaedMotI1_Mdm7hRVBE5gezg0jxXwZkn6GF6as';

const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
