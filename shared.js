/* Nextwork - modulo compartido
   Cliente Supabase, helpers de escape/accesibilidad, y el nav de avatar
   (menu desplegable + badge de notificaciones en vivo) que antes estaba
   duplicado a mano en cada pagina. Cargar despues del script de
   supabase-js y antes del script propio de cada pagina. */

const NW_SUPABASE_URL = 'https://vkewxmrutpjmdrxsqdea.supabase.co';
const NW_SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZrZXd4bXJ1dHBqbWRyeHNxZGVhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg1MjUwMTYsImV4cCI6MjA5NDEwMTAxNn0.Ety8tIitQKW_3hEaH0obDnmewPx2Opx_ZPmUmIP9ZU0';

function nwCreateClient() {
  return window.supabase.createClient(NW_SUPABASE_URL, NW_SUPABASE_KEY);
}

function nwEscapeHtml(str) {
  if (str == null) return '';
  return String(str).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function nwInitials(name) {
  return (name || '?').split(' ').map(n => n[0]).slice(0, 2).join('').toUpperCase();
}

/* ── AVATAR + MENU DESPLEGABLE ── */
const NW_NAV_LINKS = {
  dashboard: { href: 'dashboard.html', label: '📊 Mi Dashboard' },
  perfil: { href: 'perfil-publico.html', label: '👤 Ver mi perfil' },
  mensajes: { href: 'mensajes.html', label: '💬 Mensajes' }
};

function nwRenderAvatarNav(sb, el, session, profile, opts) {
  opts = opts || {};
  const skip = opts.skip || [];
  const name = profile.name || '';
  const ini = nwInitials(name);
  const altName = nwEscapeHtml(name) || 'usuario';
  const photoHtml = profile.photo
    ? `<img src="${nwEscapeHtml(profile.photo)}" alt="Foto de perfil de ${altName}" style="width:100%;height:100%;object-fit:cover">`
    : ini;
  const links = Object.keys(NW_NAV_LINKS)
    .filter(k => skip.indexOf(k) === -1)
    .map(k => `<a href="${NW_NAV_LINKS[k].href}" role="menuitem" style="display:block;padding:10px 16px;font-size:13px;color:#0f0e0c;text-decoration:none">${NW_NAV_LINKS[k].label}</a>`)
    .join('');

  el.innerHTML = `<div style="position:relative">
    <div onclick="nwToggleAvatarMenu(event)" onkeydown="if(event.key==='Enter'||event.key===' '){event.preventDefault();nwToggleAvatarMenu(event);}" role="button" tabindex="0" aria-haspopup="true" aria-expanded="false" aria-label="Menú de cuenta de ${altName}" style="display:flex;align-items:center;gap:8px;cursor:pointer">
      <div style="position:relative;width:34px;height:34px;flex-shrink:0">
        <span id="nav-notif-badge" style="display:none;position:absolute;top:-3px;right:-3px;min-width:15px;height:15px;padding:0 3px;background:#dc2626;border-radius:8px;border:2px solid #fff;color:#fff;font-size:9px;font-weight:700;align-items:center;justify-content:center" aria-label="Notificaciones sin leer"></span>
        <div style="width:100%;height:100%;border-radius:50%;background:${profile.color || '#2d6b4a'};display:flex;align-items:center;justify-content:center;font-weight:700;font-size:13px;color:#fff;border:2px solid #4d9e72;overflow:hidden">${photoHtml}</div>
      </div>
      <span style="font-size:13px;font-weight:500;color:#3d3b36">${nwEscapeHtml((name || '').split(' ')[0])}</span>
    </div>
    <div id="avatar-dropdown" role="menu" aria-label="Menú de cuenta" style="display:none;position:absolute;right:0;top:44px;background:#fff;border:1px solid #dedad1;border-radius:12px;box-shadow:0 10px 32px rgba(0,0,0,.14);min-width:180px;z-index:300;overflow:hidden">
      ${links}
      <div onclick="nwLogout()" onkeydown="if(event.key==='Enter'){nwLogout();}" role="menuitem" tabindex="0" style="padding:10px 16px;font-size:13px;color:#b91c1c;cursor:pointer;border-top:1px solid #dedad1">🚪 Cerrar sesión</div>
    </div>
  </div>`;

  nwLoadUnreadBadge(sb, session.user.id);
  nwSubscribeNotifBadge(sb, session.user.id);
}

async function nwLoadUnreadBadge(sb, userId) {
  try {
    const { count } = await sb.from('notifications').select('*', { count: 'exact', head: true }).eq('recipient_id', userId).eq('read', false);
    const el = document.getElementById('nav-notif-badge');
    if (!el) return;
    el.textContent = count > 9 ? '9+' : count;
    el.style.display = count > 0 ? 'flex' : 'none';
  } catch (e) {}
}

let NW_NOTIF_CHANNEL = null;
function nwSubscribeNotifBadge(sb, userId) {
  if (NW_NOTIF_CHANNEL) return;
  NW_NOTIF_CHANNEL = sb.channel('notif-badge-' + userId)
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'notifications', filter: `recipient_id=eq.${userId}` }, () => {
      const el = document.getElementById('nav-notif-badge');
      if (!el) return;
      const cur = el.textContent === '9+' ? 10 : (parseInt(el.textContent) || 0);
      const nxt = cur + 1;
      el.textContent = nxt > 9 ? '9+' : nxt;
      el.style.display = 'flex';
    })
    .subscribe();
}

function nwToggleAvatarMenu(e) {
  e.stopPropagation();
  const dd = document.getElementById('avatar-dropdown');
  const trigger = e.currentTarget;
  if (!dd) return;
  const willOpen = dd.style.display !== 'block';
  dd.style.display = willOpen ? 'block' : 'none';
  if (trigger) trigger.setAttribute('aria-expanded', String(willOpen));
}
document.addEventListener('click', () => {
  const dd = document.getElementById('avatar-dropdown');
  if (dd) dd.style.display = 'none';
});
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    const dd = document.getElementById('avatar-dropdown');
    if (dd) dd.style.display = 'none';
  }
});

async function nwLogout() {
  const sb = nwCreateClient();
  await sb.auth.signOut();
  try { localStorage.removeItem('nw_profile'); } catch (e) {}
  window.location.href = 'index.html';
}

/* ── SUBIDA DE IMAGENES A SUPABASE STORAGE ──
   Antes las fotos se guardaban como base64 directo en columnas de texto
   de Postgres (bucket "nextwork-uploads", ver sql/storage_uploads.sql).
   Comprime/redimensiona en el navegador antes de subir para no mandar
   fotos de camara de 12MB como si fueran de perfil de 40px. */
function nwCompressImage(file, maxDim) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    const reader = new FileReader();
    reader.onload = (e) => { img.src = e.target.result; };
    reader.onerror = () => reject(new Error('No se pudo leer el archivo'));
    img.onload = () => {
      let { width, height } = img;
      const limit = maxDim || 1000;
      if (width > limit || height > limit) {
        if (width > height) { height = Math.round(height * limit / width); width = limit; }
        else { width = Math.round(width * limit / height); height = limit; }
      }
      const canvas = document.createElement('canvas');
      canvas.width = width; canvas.height = height;
      canvas.getContext('2d').drawImage(img, 0, 0, width, height);
      canvas.toBlob((blob) => blob ? resolve(blob) : reject(new Error('No se pudo procesar la imagen')), 'image/webp', 0.82);
    };
    img.onerror = () => reject(new Error('Archivo de imagen inválido'));
    reader.readAsDataURL(file);
  });
}

async function nwUploadImage(sb, file, userId, context, maxDim) {
  const blob = await nwCompressImage(file, maxDim);
  const path = `${userId}/${context}-${Date.now()}.webp`;
  const { error } = await sb.storage.from('nextwork-uploads').upload(path, blob, { contentType: 'image/webp', upsert: false });
  if (error) throw error;
  const { data } = sb.storage.from('nextwork-uploads').getPublicUrl(path);
  return data.publicUrl;
}

/* ── MATCH SCORE: compatibilidad real, calculada con datos del perfil ──
   No es el motor de IA con embeddings (eso lo construye por separado el
   equipo) -- es un algoritmo de reglas, transparente y explicable, sobre
   señales estructuradas que ya existen en cada perfil: habilidades, rol,
   universidad, empresa, ubicacion, y las dos señales que son el corazon
   real de "matching por afinidad": si lo que uno OFRECE calza con lo que
   el otro BUSCA (vision/collab), y si sus visiones se parecen.
   Usado en dashboard.html, perfil-publico.html y crear-perfil.html --
   antes cada uno mostraba un numero al azar (Math.random()) en vez de
   esto. */
const NW_ROLE_BUCKETS={
  tech:['developer','desarrollador','engineer','ingenier','programador','backend','frontend','full-stack','fullstack','software','devops','data scientist','data engineer'],
  design:['diseñador','designer','diseño','ux','ui ','brand'],
  business:['founder','fundador','ceo','cofounder','cofundador','business','ventas','sales','marketing','growth','bizdev'],
  product:['product manager','product owner','producto']
};
function nwDetectRoleBucket(role){
  const r=(role||'').toLowerCase();
  for(const bucket in NW_ROLE_BUCKETS){
    if(NW_ROLE_BUCKETS[bucket].some(k=>r.includes(k)))return bucket;
  }
  return 'other';
}
const NW_MATCH_STOPWORDS=new Set(['de','la','el','en','y','a','que','un','una','para','con','los','las','del','al','es','soy','busco','quiero','me','mi','su','sus','como','por','se','lo','más','muy','este','esta','tengo','hay','the','and','for']);
function nwMeaningfulWords(text){
  return (text||'').toLowerCase().replace(/[^a-z0-9áéíóúñ\s]/gi,' ').split(/\s+/).filter(w=>w.length>3&&!NW_MATCH_STOPWORDS.has(w));
}
function nwWordOverlapCount(a,b){
  const setA=new Set(nwMeaningfulWords(a));
  return nwMeaningfulWords(b).filter(w=>setA.has(w)).length;
}
const NW_BUCKET_LABEL={tech:'tecnología',design:'diseño',business:'negocio',product:'producto'};

function nwComputeMatchScore(me,other){
  let score=0;
  const reasons=[];

  const mySkills=new Set((me.skills||[]).map(s=>(s||'').toLowerCase()));
  const sharedSkills=(other.skills||[]).filter(s=>mySkills.has((s||'').toLowerCase()));
  if(sharedSkills.length){
    score+=Math.min(sharedSkills.length,5)*3;
    reasons.push(`Comparten ${sharedSkills.length===1?'la habilidad':sharedSkills.length+' habilidades'}: ${sharedSkills.slice(0,3).join(', ')}`);
  }

  const myBucket=nwDetectRoleBucket(me.role);
  const otherBucket=nwDetectRoleBucket(other.role);
  if(myBucket!=='other'&&otherBucket!=='other'){
    if(myBucket!==otherBucket){
      score+=15;
      reasons.push(`Perfiles complementarios: ${me.role||'tu rol'} + ${other.role||'su rol'}`);
    } else {
      score+=6;
      reasons.push(`Ambos con perfil de ${NW_BUCKET_LABEL[otherBucket]}`);
    }
  }

  const offerMeetsNeed=nwWordOverlapCount(me.offer,other.vision)+nwWordOverlapCount(other.offer,me.vision)+nwWordOverlapCount(me.offer,other.collab)+nwWordOverlapCount(other.offer,me.collab);
  if(offerMeetsNeed>0){
    score+=Math.min(offerMeetsNeed,6)*2;
    reasons.push('Lo que uno ofrece calza con lo que el otro busca');
  }

  const visionOverlap=nwWordOverlapCount(me.vision,other.vision);
  if(visionOverlap>0){
    score+=Math.min(visionOverlap,5)*2;
    reasons.push('Visión similar sobre lo que buscan construir');
  }

  if(me.university&&other.university&&me.university.trim().toLowerCase()===other.university.trim().toLowerCase()){
    score+=5;
    reasons.push(`Ambos de ${other.university}`);
  }
  if(me.company&&other.company&&me.company.trim().toLowerCase()===other.company.trim().toLowerCase()){
    score+=5;
    reasons.push(`Ambos en ${other.company}`);
  }
  if(me.location&&other.location&&me.location.trim().toLowerCase()===other.location.trim().toLowerCase()){
    score+=6;
    reasons.push(`Ambos en ${other.location}`);
  }

  const pct=Math.max(40,Math.min(97,Math.round(40+score)));
  return {pct,reasons,score};
}

/* Orquestador: revisa sesion, pinta el avatar si hay sesion, y siempre
   llama onSession(session, profile) (con null si no hay sesion o perfil)
   para que la pagina siga con su propia logica. */
async function nwInitNavAuth(opts) {
  opts = opts || {};
  const sb = opts.sb || nwCreateClient();
  const el = document.getElementById(opts.elId || 'nav-auth');
  const { data: { session } } = await sb.auth.getSession();
  if (!el || !session) {
    if (opts.onSession) opts.onSession(null, null, sb);
    return { sb, session: null, profile: null };
  }
  const { data: p } = await sb.from('profiles').select(opts.select || 'name,color,photo').eq('id', session.user.id).single();
  if (!p) {
    if (opts.onSession) opts.onSession(session, null, sb);
    return { sb, session, profile: null };
  }
  nwRenderAvatarNav(sb, el, session, p, opts);
  if (opts.onSession) opts.onSession(session, p, sb);
  return { sb, session, profile: p };
}
