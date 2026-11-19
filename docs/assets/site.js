(() => {
  const d = document, root = d.documentElement;
  const store = (k, v) => { try { return v === undefined ? localStorage.getItem(k) : localStorage.setItem(k, v); } catch (e) {} };
  const track = (...a) => window.gtag && gtag(...a);

  // (c) first-visit language redirect: root only, no saved choice, never for bots
  if (location.pathname === '/' && !store('sp-lang') && !/bot|crawl|spider|lighthouse/i.test(navigator.userAgent)) {
    const have = (root.dataset.locales || '').split(',');
    for (const l of navigator.languages || []) {
      const s = l.toLowerCase();
      const c = s.startsWith('zh') ? (/hant|tw|hk|mo/.test(s) ? 'zh-hant' : 'zh-hans') : s.startsWith('pt') ? 'pt-br' : s.slice(0, 2);
      if (c === 'en') break;
      if (have.includes(c)) { location.replace('/' + c + '/' + location.search + location.hash); break; }
    }
  }

  // (a) reading demo: one clock drives every [data-read] block
  const seg = (t, l) => window.Intl && Intl.Segmenter
    ? [...new Intl.Segmenter(l, { granularity: 'word' }).segment(t)]
    : t.split(/(\s+)/).map(s => ({ segment: s, isWordLike: /\S/.test(s) }));
  const words = el => {
    if (!el.querySelector('.w')) {
      const walk = d.createTreeWalker(el, 4), nodes = [];
      while (walk.nextNode()) nodes.push(walk.currentNode);
      for (const n of nodes) {
        if (n.parentNode.closest('.cue')) continue;
        const f = d.createDocumentFragment();
        for (const s of seg(n.data, el.closest('[lang]').lang)) {
          const last = f.lastChild;
          if (!s.isWordLike) {  // punctuation sticks to the word before it
            if (/\S/.test(s.segment) && last && last.className === 'w') last.textContent += s.segment; else f.append(s.segment);
            continue;
          }
          const e = d.createElement('span');
          e.className = 'w'; e.textContent = s.segment; f.append(e);
        }
        n.replaceWith(f);
      }
    }
    return [...el.querySelectorAll('.w')];
  };
  const sets = [...d.querySelectorAll('[data-read]')].map(el => ({ el, w: words(el), i: -1 }));
  const paint = (s, i) => {
    if (s.i === i) return;
    s.i = i;
    s.w.forEach((e, k) => { e.classList.toggle('r', k < i); e.classList.toggle('c', k === i); });
  };
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
    sets.forEach(s => paint(s, Math.floor(s.w.length / 3)));
  } else if (sets.length) {
    let t = 0, timer = 0;
    const run = () => {
      const on = sets.some(s => s.vis) && !d.hidden;
      if (on && !timer) timer = setInterval(tick, 420);
      else if (!on && timer) { clearInterval(timer); timer = 0; }
    };
    const tick = () => { t++; sets.forEach(s => s.vis && paint(s, Math.min(t % (s.w.length + 4), s.w.length))); };
    const io = new IntersectionObserver(es => { es.forEach(e => sets.find(s => s.el === e.target).vis = e.isIntersecting); run(); }, { rootMargin: '80px' });
    sets.forEach(s => { paint(s, 0); io.observe(s.el); });
    d.addEventListener('visibilitychange', run);
  }

  // (e) distance demo: prompter-typography.md formula for an iPhone 16 Pro (ppmm 6.037, xr .526, alpha .40 deg)
  const dist = d.querySelector('[data-dist]');
  if (dist) {
    const range = dist.querySelector('input'), pf = dist.querySelector('.pf'), tan = x => Math.tan(x * Math.PI / 180);
    const render = () => {
      const cm = +range.value, mm = cm * 10, ideal = mm * tan(.4) * 6.037 / .526;
      const pt = Math.round(Math.min(ideal, 370 / (.5 * 13))), alpha = Math.atan(pt * .526 / 6.037 / mm) * 180 / Math.PI;
      const n = Math.max(2, Math.min(3, Math.floor((tan(3) - 4 / mm) / (1.3 * tan(alpha) / .526) + .55)));
      pf.style.setProperty('--s', pt); pf.style.setProperty('--n', n);
      dist.querySelector('[data-cm]').textContent = dist.dataset.fmt.replace('{cm}', cm);
      dist.querySelector('[data-readout-out]').textContent = dist.dataset.readout.replace('{pt}', pt).replace('{n}', n);
      dist.querySelector('[data-cap]').hidden = ideal <= pt + .5;
      range.setAttribute('aria-valuetext', dist.dataset.fmt.replace('{cm}', cm));
    };
    range.addEventListener('input', render); render();
  }

  // (b) case tabs
  const tabs = [...d.querySelectorAll('[role=tab]')];
  const pick = (i, user) => {
    tabs.forEach((t, k) => {
      t.setAttribute('aria-selected', k === i);
      t.tabIndex = k === i ? 0 : -1;
      d.getElementById(t.getAttribute('aria-controls')).hidden = k !== i;
    });
    if (user) { tabs[i].focus(); track('event', 'case_tab', { case: tabs[i].dataset.case }); }
  };
  tabs.forEach((t, i) => {
    t.onclick = () => pick(i, 1);
    t.onkeydown = e => {
      const n = tabs.length, k = { ArrowRight: i + 1, ArrowLeft: i - 1, Home: 0, End: n - 1 }[e.key];
      if (k !== undefined) { e.preventDefault(); pick((k + n) % n, 1); }
    };
  });

  // language menu: remember the choice, then follow the link
  const menu = d.getElementById('lang');
  d.addEventListener('click', e => {
    const a = e.target.closest('a[data-lang]');
    if (a) { store('sp-lang', a.dataset.lang); track('event', 'language_switch', { language: a.dataset.lang }); }
    const s = e.target.closest('a[href*="apps.apple.com"]');
    if (s) track('event', 'app_store_click', { placement: (new URL(s.href).searchParams.get('ct') || '').replace('site-', '') });
    if (menu && !menu.contains(e.target)) menu.open = false;
  });
  d.addEventListener('keydown', e => { if (e.key === 'Escape' && menu) menu.open = false; });

  // (d) Consent Mode v2: the head snippet sets every signal to denied; only analytics can be granted
  const bar = d.getElementById('consent');
  if (bar) {
    const show = () => { bar.hidden = false; };
    if (!store('sp-consent')) show();
    bar.onclick = e => {
      const v = e.target.dataset.c;
      if (!v) return;
      store('sp-consent', v);
      track('consent', 'update', { analytics_storage: v });
      bar.hidden = true;
    };
    d.getElementById('cookie-settings').onclick = show;
  }
})();
