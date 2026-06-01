/* ============================================================
   NEXTWORK — front-end interactions (visual mock)
   ============================================================ */

/* ── SCROLL PROGRESS + ACTIVE NAV ── */
const progress = document.getElementById('scroll-progress');
const navEl = document.querySelector('nav');
window.addEventListener('scroll', () => {
  const h = document.documentElement;
  const pct = (h.scrollTop / (h.scrollHeight - h.clientHeight)) * 100;
  progress.style.width = pct + '%';
  if (navEl) navEl.classList.toggle('scrolled', h.scrollTop > 8);
  updateActiveNav();
}, { passive: true });

function updateActiveNav() {
  const sections = ['how', 'match', 'roadmap'];
  const links = document.querySelectorAll('.nav-links a[data-section]');
  let current = '';
  sections.forEach(id => {
    const el = document.getElementById(id);
    if (el && el.getBoundingClientRect().top <= 90) current = id;
  });
  links.forEach(a => a.classList.toggle('active', a.dataset.section === current && current !== ''));
}

/* ── MOBILE MENU ── */
function toggleMenu() {
  document.getElementById('mobile-menu').classList.toggle('open');
  document.getElementById('hamburger').classList.toggle('open');
}
function closeMenu() {
  document.getElementById('mobile-menu').classList.remove('open');
  document.getElementById('hamburger').classList.remove('open');
}

/* ── REVEAL ON SCROLL ── */
const io = new IntersectionObserver(entries => {
  entries.forEach(e => { if (e.isIntersecting) e.target.classList.add('visible'); });
}, { threshold: 0.12 });
document.querySelectorAll('.reveal, .stagger').forEach(el => io.observe(el));

/* ── COUNT-UP STATS ── */
const countObserver = new IntersectionObserver(entries => {
  entries.forEach(e => {
    if (!e.isIntersecting) return;
    const el = e.target;
    const target = parseInt(el.dataset.count);
    if (!target) return;
    const suffix = el.dataset.suffix || '';
    let curr = 0;
    const step = Math.ceil(target / 38);
    const timer = setInterval(() => {
      curr = Math.min(curr + step, target);
      el.textContent = curr + suffix;
      if (curr >= target) clearInterval(timer);
    }, 32);
    countObserver.unobserve(el);
  });
}, { threshold: 0.5 });
document.querySelectorAll('.stat-n[data-count]').forEach(el => countObserver.observe(el));

/* ── TOAST ── */
function showToast(msg, type = '') {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.className = 'toast show ' + (type || '');
  clearTimeout(t._timer);
  t._timer = setTimeout(() => t.classList.remove('show'), 3200);
}

/* ── FAQ ACCORDION ── */
function toggleFaq(btn) {
  const item = btn.closest('.faq-item');
  const isOpen = item.classList.contains('open');
  document.querySelectorAll('.faq-item.open').forEach(el => {
    el.classList.remove('open');
    el.querySelector('.faq-a').style.maxHeight = null;
  });
  if (!isOpen) {
    item.classList.add('open');
    const a = item.querySelector('.faq-a');
    a.style.maxHeight = a.scrollHeight + 'px';
  }
}

/* ── MODAL T&C ── */
function openTC() {
  document.getElementById('tc-modal').classList.add('open');
  document.body.style.overflow = 'hidden';
}
function closeTC() {
  document.getElementById('tc-modal').classList.remove('open');
  document.body.style.overflow = '';
}
function closeTCifOverlay(e) {
  if (e.target === document.getElementById('tc-modal')) closeTC();
}
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeTC(); });

/* ── CONTACT (EmailJS) ── */
emailjs.init('qCCiB5C-ktvGFIFyt');

async function sendContact() {
  const email   = document.getElementById('contact-email').value.trim();
  const subject = document.getElementById('contact-subject').value.trim();
  const message = document.getElementById('contact-message').value.trim();
  if (!email || !subject || !message) { showToast('Completa todos los campos', 'error'); return; }

  const btn = document.querySelector('.contact-send-btn');
  btn.disabled = true;
  btn.textContent = 'Enviando…';

  try {
    await emailjs.send('service_kr7yft1', 'template_mec1fwa', {
      from_name: email,
      from_email: email,
      subject: subject,
      message: message,
    });
    showToast('¡Mensaje enviado! Te respondemos pronto.', 'success');
    document.getElementById('contact-email').value = '';
    document.getElementById('contact-subject').value = '';
    document.getElementById('contact-message').value = '';
  } catch (e) {
    showToast('Error al enviar. Escríbenos a Team@nextwork.cl', 'error');
  }
  btn.disabled = false;
  btn.textContent = 'Enviar a Team@nextwork.cl';
}

/* ============================================================
   MATCHING ENGINE (mock)
   ============================================================ */
const matchProfiles = {
  dev: [
    { name: 'Sebastián Reyes', role: 'Product Manager · 5 años exp.', location: 'Santiago, CL', initials: 'SR', color: '#185fa5', tags: ['Product Strategy', 'Agile', 'B2B SaaS', 'Growth'], seeking: 'Un tech lead para co-fundar una startup EdTech' },
    { name: 'Isidora Campos', role: 'Business Developer · 4 años exp.', location: 'Buenos Aires, AR', initials: 'IC', color: '#b8762a', tags: ['Ventas B2B', 'Partnerships', 'GTM', 'Latam'], seeking: 'Dev con visión de negocio para escalar startup' },
    { name: 'Felipe Muñoz', role: 'Diseñador UX/UI · 6 años exp.', location: 'Medellín, CO', initials: 'FM', color: '#7d4b9d', tags: ['Figma', 'Design Systems', 'Mobile', 'User Research'], seeking: 'Fullstack para construir producto digital de impacto' },
  ],
  design: [
    { name: 'Matías González', role: 'Dev Fullstack · 7 años exp.', location: 'Santiago, CL', initials: 'MG', color: '#2d6b4a', tags: ['React', 'Node.js', 'AWS', 'Startups'], seeking: 'Diseñador/a con foco en conversión y producto' },
    { name: 'Camila Rojas', role: 'Growth Hacker · 3 años exp.', location: 'Lima, PE', initials: 'CR', color: '#b8762a', tags: ['SEO', 'Paid Ads', 'Funnel', 'Analytics'], seeking: 'Diseñador/a para construir marca con propósito' },
    { name: 'Diego Vargas', role: 'Founder en stealth · ex-Google', location: 'CDMX, MX', initials: 'DV', color: '#1a6b6b', tags: ['Producto', 'Fintech', 'UX Strategy', 'Funding'], seeking: 'Lead designer para lanzar MVP en Q3' },
  ],
  marketing: [
    { name: 'Valentina Soto', role: 'CEO ClimateTech · 2 años exp.', location: 'Santiago, CL', initials: 'VS', color: '#2d6b4a', tags: ['Impacto Social', 'B2B', 'SaaS', 'Inversión'], seeking: 'CMO o growth lead con visión de largo plazo' },
    { name: 'Andrés Pérez', role: 'Founder · SaaS para pymes', location: 'Bogotá, CO', initials: 'AP', color: '#185fa5', tags: ['B2B', 'Automatización', 'Ventas', 'Pymes'], seeking: 'Marketing estratégico para escalar en Latam' },
    { name: 'Natalia Herrera', role: 'Directora de Producto · ex-Falabella', location: 'Santiago, CL', initials: 'NH', color: '#7d4b9d', tags: ['E-commerce', 'Producto', 'Data', 'Equipos'], seeking: 'Estratega de marketing para redefinir la marca' },
  ],
  founder: [
    { name: 'Tomás Ibáñez', role: 'Dev Backend Senior · 8 años exp.', location: 'Santiago, CL', initials: 'TI', color: '#2d6b4a', tags: ['Python', 'APIs', 'Escala', 'Infraestructura'], seeking: 'Co-founder técnico para proyecto de alto impacto' },
    { name: 'Renata Morales', role: 'Inversora Ángel · ex-Cornershop', location: 'Santiago, CL', initials: 'RM', color: '#b8762a', tags: ['Startups', 'Early Stage', 'Latam', 'Mentoring'], seeking: 'Founders con tracción y visión clara' },
    { name: 'Javier Cruz', role: 'CFO Freelance · Startups Latam', location: 'Buenos Aires, AR', initials: 'JC', color: '#1a6b6b', tags: ['Finanzas', 'Cap Table', 'Fundraising', 'Due Diligence'], seeking: 'Co-founder con idea validada para ir a Serie A' },
  ],
  default: [
    { name: 'Andrea Molina', role: 'Consultora de Innovación · 6 años exp.', location: 'Santiago, CL', initials: 'AM', color: '#7d4b9d', tags: ['Innovación', 'Metodologías Ágiles', 'Equipos', 'Proyectos'], seeking: 'Socio/a con habilidades complementarias y ambición' },
    { name: 'Pablo Leiva', role: 'Full-Stack Developer · Independiente', location: 'Valparaíso, CL', initials: 'PL', color: '#185fa5', tags: ['React', 'Node', 'Proyectos propios', 'Open Source'], seeking: 'Personas apasionadas con proyectos reales' },
    { name: 'Mariana Vidal', role: 'Diseñadora & Founder · Studio MV', location: 'Montevideo, UY', initials: 'MV', color: '#b8762a', tags: ['Branding', 'UX', 'Emprendimiento', 'Creatividad'], seeking: 'Equipo multidisciplinar para proyecto ambicioso' },
  ]
};

function detectCategory(role, skills, vision) {
  const text = (role + ' ' + skills + ' ' + vision).toLowerCase();
  if (/dev|program|código|backend|frontend|react|node|python|software|ingenier|fullstack|stack/.test(text)) return 'dev';
  if (/diseñ|ux|ui|figma|visual|brand|product design|ilustr|graphic/.test(text)) return 'design';
  if (/market|growth|seo|redes|contenido|comunidad|ads|ventas|sales|comunic/.test(text)) return 'marketing';
  if (/founder|co-fund|startup|emprendedor|ceo|cto|lanz|idea|negocio/.test(text)) return 'founder';
  return 'default';
}

function buildWhyText(profile, userName, userRole, userSkills, colabType) {
  const name = userName || 'tú';
  const firstSkill = (userSkills.split(',')[0] || 'tu área').trim();
  const whyMap = {
    '#185fa5': `${name} aporta la visión técnica que ${profile.name} necesita para ejecutar su hoja de ruta. La experiencia de ${profile.name} en producto y estrategia complementa perfectamente las habilidades en ${firstSkill}. Juntos cubren el 100% del stack fundador.`,
    '#b8762a': `${profile.name} ha desarrollado redes comerciales en Latam que acelerarían el trabajo de ${name}. Donde ${name} tiene profundidad técnica y creativa, ${profile.name} tiene la conexión con el mercado. Un match complementario de alto valor.`,
    '#2d6b4a': `La combinación de ${firstSkill} con la experiencia de ${profile.name} en ${profile.tags[0]} crea un perfil difícil de encontrar. ${profile.name} busca exactamente el tipo de colaboración que ${name} propone: ${colabType || 'trabajo de alto impacto'}.`,
    '#7d4b9d': `${profile.name} lleva tiempo buscando alguien con el perfil de ${name}: alguien que combine visión y ejecución. Su experiencia en ${profile.tags[1]} se alinea con lo que ${name} describe. La afinidad de valores es lo que más destaca.`,
    '#1a6b6b': `Ambos comparten una visión orientada al impacto real, no solo a la facturación. ${profile.name} aporta ${profile.tags[0]} y ${profile.tags[2]}, dos áreas donde la combinación genera sinergia inmediata. Alto potencial de escala.`,
  };
  return whyMap[profile.color] || `${name} y ${profile.name} comparten una visión compatible y habilidades complementarias. ${profile.name} aporta ${profile.tags[0]} y ${profile.tags[1]}, cubriendo las brechas del perfil. La afinidad de objetivos hace de este uno de los matches más sólidos del algoritmo.`;
}

async function runMatch() {
  const name = document.getElementById('m-name').value.trim();
  const role = document.getElementById('m-role').value.trim();
  const skills = document.getElementById('m-skills').value.trim();
  const type = document.getElementById('m-type').value;
  const vision = document.getElementById('m-vision').value.trim();

  if (!role || !skills || !vision) {
    showToast('Completa tu rol, habilidades y qué buscas', 'error');
    if (!role) document.getElementById('m-role').focus();
    else if (!skills) document.getElementById('m-skills').focus();
    else document.getElementById('m-vision').focus();
    return;
  }

  const btn = document.getElementById('match-btn');
  const resultEl = document.getElementById('match-result');
  const loadingEl = document.getElementById('mr-loading');
  const outputEl = document.getElementById('mr-output');

  btn.disabled = true;
  resultEl.classList.add('show');
  loadingEl.style.display = 'block';
  outputEl.style.display = 'none';
  outputEl.innerHTML = '';

  await new Promise(r => setTimeout(r, 1900 + Math.random() * 700));

  const cat = detectCategory(role, skills, vision);
  const pool = matchProfiles[cat] || matchProfiles.default;
  const m = pool[Math.floor(Math.random() * pool.length)];
  const pct = 82 + Math.floor(Math.random() * 15);
  const why = buildWhyText(m, name, role, skills, type);

  outputEl.innerHTML = `
    <div class="mr-card">
      <div class="mr-header">
        <div class="mr-av" style="background:${m.color}">${m.initials}</div>
        <div>
          <p class="mr-name">${m.name}</p>
          <p class="mr-role">${m.role} · ${m.location}</p>
        </div>
        <div class="mr-pct">${pct}<small>match</small></div>
      </div>
      <div class="compat-bar"><div class="compat-fill" id="compat-fill"></div></div>
      <div class="mr-tags">${m.tags.map(t => `<span class="mr-tag">${t}</span>`).join('')}</div>
      <div class="mr-why"><strong>Por qué hacen match:</strong> ${why}</div>
      <p class="mr-seeking">BUSCA · "${m.seeking}"</p>
    </div>
    <div class="match-another">
      <button class="match-btn" style="max-width:200px" onclick="runMatch()">Otro match →</button>
      <a href="crear-perfil.html" style="max-width:260px;width:100%"><button class="match-btn" style="width:100%;background:var(--green-deep)">Crear mi perfil →</button></a>
    </div>`;

  loadingEl.style.display = 'none';
  outputEl.style.display = 'block';
  setTimeout(() => {
    const fill = document.getElementById('compat-fill');
    if (fill) fill.style.width = pct + '%';
  }, 100);
  btn.disabled = false;
  showToast('¡Match encontrado! ' + pct + '% de afinidad', 'success');
}

/* ── LIVE COUNTER (Supabase) ── */
(async function loadLiveCount() {
  try {
    const SUPA_URL = 'https://vkewxmrutpjmdrxsqdea.supabase.co';
    const SUPA_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZrZXd4bXJ1dHBqbWRyeHNxZGVhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg1MjUwMTYsImV4cCI6MjA5NDEwMTAxNn0.Ety8tIitQKW_3hEaH0obDnmewPx2Opx_ZPmUmIP9ZU0';
    const sb = window.supabase.createClient(SUPA_URL, SUPA_KEY);
    const { count, error } = await sb.from('waitlist').select('*', { count: 'exact', head: true });
    if (error || count === null) return;
    const el = document.getElementById('live-count');
    if (!el) return;
    let curr = 0;
    const step = Math.max(1, Math.ceil(count / 30));
    const timer = setInterval(() => {
      curr = Math.min(curr + step, count);
      el.textContent = '+' + curr + ' personas';
      if (curr >= count) clearInterval(timer);
    }, 40);
  } catch (e) {}
})();
