(() => {
  const d = document, root = d.documentElement;
  const store = (k, v) => { try { return v === undefined ? localStorage.getItem(k) : localStorage.setItem(k, v); } catch (e) {} };
  const track = (...a) => window.gtag && gtag(...a);

  // (c) first visit to the root: send the visitor to their language once (user decision); bots and saved choices stay put
  const offer = d.getElementById('langbar');
  if (offer && location.pathname === '/' && !store('sp-lang') && !/bot|crawl|spider|slurp|lighthouse|preview/i.test(navigator.userAgent)) {
    const offers = JSON.parse(offer.dataset.offers || '{}');
    for (const l of navigator.languages || []) {
      const s = l.toLowerCase();
      const c = s.startsWith('zh') ? (/hant|tw|hk|mo/.test(s) ? 'zh-hant' : 'zh-hans') : s.startsWith('pt') ? 'pt-br' : s.slice(0, 2);
      if (c === 'en') break;
      if (offers[c]) { store('sp-lang', c); location.replace(offers[c][1] + location.search + location.hash); break; }
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
  const rm = matchMedia('(prefers-reduced-motion: reduce)');
  let paused = rm.matches, run = () => {};
  // The app eases the text towards the reading line: step = (goal - y) * (1 - exp(-8 dt)), at most 1200 pt/s (ScrollEngine.tick).
  // The hero headline stays put, so the reading-line ticks do that move instead.
  const follow = el => {
    let y = null, goal = 0, raf = 0, last = 0;
    const set = () => el.style.setProperty('--ty', y + 'px');
    const step = now => {
      const dt = Math.min((now - last) / 1000, .1), lim = 1200 * dt;
      last = now;
      y += Math.max(-lim, Math.min(lim, (goal - y) * (1 - Math.exp(-8 * dt))));
      if (Math.abs(goal - y) < .5) { y = goal; raf = 0; } else raf = requestAnimationFrame(step);
      set();
    };
    return t => {
      goal = t;
      if (y === null || rm.matches) { y = t; set(); } else if (!raf) { last = performance.now(); raf = requestAnimationFrame(step); }
    };
  };
  const sets = [...d.querySelectorAll('[data-read]')].map(el => {
    const w = words(el), s = { el, w, i: -1 };
    s.cues = [...el.querySelectorAll('.cue')].map(c => ({ c, n: w.filter(e => e.compareDocumentPosition(c) & 4).length }));
    if (el.classList.contains('reading')) {
      const go = follow(el);
      // build.py's --w is a per-character guess; measure the widest line in em so each line fits its column on one row
      s.fit = () => {
        el.classList.add('fit');
        const fs = parseFloat(getComputedStyle(el).fontSize), r = d.createRange();
        const em = Math.max(...[...el.querySelectorAll('.ln')].map(l => { r.selectNodeContents(l); return r.getBoundingClientRect().width / fs; }));
        if (em > 0) el.style.setProperty('--w', (em * 1.06).toFixed(2));  // 6%: the current-word highlight box
      };
      s.fit();
      s.tick = () => { const e = w[Math.min(Math.max(s.i, 0), w.length - 1)]; go(e.offsetTop + e.offsetHeight / 2); };
    }
    return s;
  });
  const paint = (s, i) => {
    if (s.i === i) return;
    s.i = i;
    s.w.forEach((e, k) => { e.classList.toggle('r', k < i); e.classList.toggle('c', k === i); });
    s.cues.forEach(({ c, n }) => c.classList.toggle('r', n < i));  // a cue is "read" once the cursor is past it (PrompterText.cueColor)
    if (s.tick) s.tick();
  };
  addEventListener('resize', () => sets.forEach(s => s.tick && s.tick()));
  if (d.fonts) d.fonts.ready.then(() => sets.forEach(s => { if (s.fit) s.fit(); if (s.tick) s.tick(); }));

  if (rm.matches) {
    sets.forEach(s => paint(s, Math.floor(s.w.length / 3)));
  } else if (sets.length) {
    let t = 0, timer = 0;
    run = () => {
      const on = sets.some(s => s.vis) && !d.hidden && !paused;
      if (on && !timer) timer = setInterval(tick, 420);
      else if (!on && timer) { clearInterval(timer); timer = 0; }
    };
    const tick = () => { t++; sets.forEach(s => s.vis && paint(s, Math.min(t % (s.w.length + 4), s.w.length))); };
    const io = new IntersectionObserver(es => { es.forEach(e => sets.find(s => s.el === e.target).vis = e.isIntersecting); run(); }, { rootMargin: '80px' });
    sets.forEach(s => { paint(s, 0); io.observe(s.el); });
    d.addEventListener('visibilitychange', run);
  }

  const ctl = d.getElementById('motion-ctl');
  if (ctl) {
    if (rm.matches) ctl.hidden = true;
    ctl.onclick = () => {
      paused = !paused;
      ctl.setAttribute('aria-pressed', paused);
      ctl.setAttribute('aria-label', paused ? ctl.dataset.play : ctl.dataset.pause);
      // the live prompters (prompter.js) stop and start with the rest of the motion
      d.dispatchEvent(new CustomEvent('sp-motion', { detail: paused }));
      run();
    };
  }

  // (e) distance scene: scroll progress -> 35 -> 100 -> 45 cm; text size from prompter-typography.md (iPhone 16 Pro: ppmm 6.037, xr .526, alpha .40 deg)
  const scene = d.querySelector('[data-dist]');
  if (scene) {
    const pin = scene.querySelector('.as-pin'), unit = scene.querySelector('.as-unit'), range = unit.querySelector('input'), tan = x => Math.tan(x * Math.PI / 180);
    const KEYS = [[0, 35], [.1, 35], [.55, 100], [.66, 100], [.92, 45], [1, 45]]; // same key points as @keyframes as-needle
    const at = p => {
      let i = 1;
      while (i < KEYS.length - 1 && p > KEYS[i][0]) i++;
      const [a, x] = KEYS[i - 1], [b, y] = KEYS[i];
      return x + (y - x) * Math.min(1, Math.max(0, (p - a) / (b - a)));
    };
    // DistanceSizer on an iPhone 17 Pro in camera mode: PrompterTypography.plan (354 pt column), then the controller's 20 pt x 1.10^n grid; 3 lines
    const snap = s => Math.round(20 * 1.1 ** Math.round(Math.log(s / 20) / Math.log(1.1)) * 2) / 2;
    const render = (u, cm) => {
      const mm = cm * 10, ideal = mm * tan(.4) * 6.037 / .526, cap = 354 / (.5 * 13);
      const pt = snap(Math.max(Math.min(ideal, cap), 20)), n = 3;
      // the frames are the app's own drawing, one per 5 cm
      const step = Math.min(100, Math.max(35, Math.round(cm / 5) * 5));
      u.style.setProperty('--d', ((cm - 35) / 65).toFixed(4));
      const key = pt + '/' + Math.round(cm) + '/' + step;
      if (u.k === key) return;
      u.k = key;
      const pf = u.querySelector('.pf'), a = scene.dataset.fmt.replace('{cm}', Math.round(cm)), b = scene.dataset.readout.replace('{pt}', String(pt).replace('.', scene.dataset.dec || '.')).replace('{n}', n);
      const fr = pf.querySelector('.pf-frame'), lp = pf.querySelector('.lp');
      if (fr) fr.src = fr.dataset.base + step + '.webp';
      // the text at the size the app commits for this distance, eased in like an automatic change
      if (lp && lp.prompter) lp.prompter.setSize(pt, true);
      u.querySelector('[data-cm]').textContent = a;
      u.querySelector('[data-readout-out]').textContent = b;
      u.querySelector('[data-cap]').hidden = ideal <= pt + .5;
      const inp = u.querySelector('input');
      if (inp) inp.setAttribute('aria-valuetext', a + ', ' + b);
    };
    rm.addEventListener('change', () => location.reload());
    if (rm.matches) {
      const row = d.createElement('div');
      row.className = 'as-static';
      [40, 70, 100].forEach(cm => {
        const u = unit.cloneNode(true);
        u.querySelector('.ruler').remove(); u.querySelector('label').remove();
        const lp = u.querySelector('.lp');
        if (lp && window.SPPrompter) window.SPPrompter(lp);
        render(u, cm); row.append(u);
      });
      unit.hidden = true; unit.parentNode.append(row);
    } else {
      let vis = false, raf = 0;
      const frame = () => {
        raf = 0;
        const r = scene.getBoundingClientRect(), span = r.height - pin.offsetHeight;
        const cm = at(span > 0 ? Math.min(1, Math.max(0, -r.top / span)) : 0);
        render(unit, cm); range.value = Math.round(cm);
      };
      const tick = () => { if (!raf) raf = requestAnimationFrame(frame); };
      // the slider overrides the scroll-linked animation until the next scroll
      let used = 0;
      range.addEventListener('input', () => { scene.dataset.manual = ''; render(unit, +range.value); if (!used) { used = 1; track('event', 'demo_distance', { language: root.lang }); } });
      addEventListener('scroll', () => { if (vis) { scene.removeAttribute('data-manual'); tick(); } }, { passive: true });
      addEventListener('resize', tick);
      new IntersectionObserver(([e]) => { vis = e.isIntersecting; if (vis) tick(); }).observe(scene);
      frame();
    }
  }

  // (b) case tabs
  const tabs = [...d.querySelectorAll('[role=tab]')];
  const pick = (i, user) => {
    tabs.forEach((t, k) => {
      t.setAttribute('aria-selected', k === i);
      t.tabIndex = k === i ? 0 : -1;
      d.getElementById(t.getAttribute('aria-controls')).hidden = k !== i;
    });
    if (user) { tabs[i].focus(); tabs[i].scrollIntoView({ inline: 'center', block: 'nearest' }); track('event', 'case_tab', { case: tabs[i].dataset.case }); }
  };
  tabs.forEach((t, i) => {
    t.onclick = () => pick(i, 1);
    t.onkeydown = e => {
      const n = tabs.length, k = { ArrowRight: i + 1, ArrowLeft: i - 1, Home: 0, End: n - 1 }[e.key];
      if (k !== undefined) { e.preventDefault(); pick((k + n) % n, 1); }
    };
  });
  // scrolling walks the four cases: the section pins and each case gets a quarter of the track (wide screens, motion allowed)
  const ct = d.querySelector('.cases-track');
  if (ct && tabs.length) {
    const wide = matchMedia('(min-width: 900px)'), on = () => wide.matches && !rm.matches;
    const span = () => ct.offsetHeight - innerHeight;
    let cur = 0;
    const step = () => {
      if (!on() || span() <= 0) return;
      const i = Math.min(tabs.length - 1, Math.max(0, Math.floor(-ct.getBoundingClientRect().top / span() * tabs.length)));
      if (i !== cur) { cur = i; pick(i); }
      ct.style.setProperty('--cp', Math.min(1, Math.max(0, -ct.getBoundingClientRect().top / span())).toFixed(3));
    };
    addEventListener('scroll', step, { passive: true });
    step();
    // a tab click moves the page into that case's stretch, so scrolling carries on from there
    tabs.forEach((t, i) => t.addEventListener('click', () => {
      if (!on()) return;
      cur = i;
      scrollTo({ top: scrollY + ct.getBoundingClientRect().top + span() * (i + .5) / tabs.length });
    }));
  }

  // scroll reveals: CSS scroll-driven animations (view()) where supported; elsewhere a one-shot IntersectionObserver. Reduced motion: none.
  if (!rm.matches) {
    const RV = '.sec h2, .sec-head p, .split-head p, .tags, .devices .sec-head .store, .plan, .qas, .wall, .pro .note, .pro .store, .close .sub, .close .store, .as-after .note';
    const GROW = '.scene, #connection .story-art, .library .maclib, .crop-dev, .art-privacy';
    const skip = e => e.closest('.hero, .as-pin, .cases-pin');
    const els = [...d.querySelectorAll(RV + ', ' + GROW)].filter(e => !skip(e));
    els.forEach(e => { e.classList.add(e.matches(GROW) ? 'grow' : 'rv'); if (e.matches('p')) e.classList.add('sec-p'); });
    if (!(window.CSS && CSS.supports('animation-timeline', 'view()')) && window.IntersectionObserver) {
      root.classList.add('rv-js');
      const io = new IntersectionObserver(es => es.forEach(e => { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } }), { rootMargin: '0px 0px -8% 0px' });
      els.forEach(e => io.observe(e));
    }
  }

  // language menu: remember the choice, then follow the link
  const menu = d.getElementById('lang');
  d.addEventListener('click', e => {
    const a = e.target.closest('a[data-lang]');
    if (a) { store('sp-lang', a.dataset.lang); track('event', 'language_switch', { language: a.dataset.lang }); }
    const s = e.target.closest('a[href*="apps.apple.com"]');
    if (s) track('event', 'app_store_click', { placement: (new URL(s.href).searchParams.get('ct') || '').replace('site-', ''), language: root.lang, transport_type: 'beacon' });
    if (e.target.closest('.hero .link')) track('event', 'cta_secondary', { language: root.lang });
    if (menu && !menu.contains(e.target)) menu.open = false;
  });
  d.addEventListener('keydown', e => { if (e.key === 'Escape' && menu) menu.open = false; });
  d.addEventListener('toggle', e => { if (e.target.matches && e.target.matches('.qa[open]')) track('event', 'faq_open', { question: [...d.querySelectorAll('.qa')].indexOf(e.target) + 1 }); }, true);
  const pro = d.getElementById('pro');
  if (pro && window.IntersectionObserver) new IntersectionObserver(([e], o) => { if (e.isIntersecting) { track('event', 'pro_section_view', { language: root.lang }); o.disconnect(); } }).observe(pro);

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
