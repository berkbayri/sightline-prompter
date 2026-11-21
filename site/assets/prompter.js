// The live prompter: the app's own drawing rules (iOS/Sources/PrompterUIView.swift, macOS/App/PrompterView.swift,
// Shared/Core/CameraLayout.swift, ScrollEngine.swift, PrompterTypography.swift) in HTML over a still of the screen.
// Everything is laid out at the device's own scale, one point = one CSS pixel, then scaled to the page with a transform:
// so text, line spacing, highlight, plates and margins scale together, and the browser picks the font's optical size
// from the point size as TextKit does (laid out at the page size, SF's large-size cut would make the text narrower). Words come pre-split by the app's ScriptTokenizer (site/render).
(() => {
  'use strict';
  // SF Pro Semibold metrics in em (NSFont): ascender, descender, cap height. The app's line is the font's natural
  // height x 1.30 (lineHeightMultiple); TextKit puts all the extra space above the glyphs, CSS splits it, so the text
  // is pushed down by the difference to land on the app's baseline.
  const ASC = .9668, DESC = .2109, CAP = .7046, LH = (ASC + DESC) * 1.3;
  const PUSH = LH - DESC - ((LH - ASC - DESC) / 2 + ASC);
  const BASE = LH - DESC; // baseline below the line top
  const rm = matchMedia('(prefers-reduced-motion: reduce)');
  let paused = false; // the page's motion button (site.js)

  // CameraLayout.recordingPortrait / recordingLandscape (iPhone 17 Pro, 402 x 874 pt) and NotchPanel + PrompterView.
  const GEOMETRY = {
    p: fs => ({ W: 402, H: 874, x: 24, y: 62, w: 354, h: LH * fs * 3, read: 62 + LH * fs / 2, cam: true }),
    l: fs => {
      const w = Math.max(Math.min(480, (874 - 62 - 62 - 76 - 36) * .67), 120), h = Math.min(LH * fs * 5, 402 - 32);
      return { W: 874, H: 402, x: 74, y: (402 - h) / 2, w, h, read: 201, cam: true };
    },
    // panel 520 x 220 pt; the prompter fills it below the notch inset (32 + 8 pt); text 24 pt in, 12 pt down, line at 35 %
    mac: () => ({ W: 520, H: 220, x: 24, y: 40 + 12, w: 472, h: 180 - 12, clipTop: 40, clipH: 180, read: 40 + 180 * .35, cam: false }),
  };

  // Seconds each word takes to say, and the pause after sentences and clauses (as site/render/Sources/main.swift).
  const timeline = (words, spaced) => {
    let t = 0;
    return words.map(w => {
      const n = (w.match(/[\p{L}\p{N}]/gu) || []).length;
      t += spaced ? .15 + .052 * n : .145 * Math.max(n, 1);
      const end = t, last = w.slice(-1);
      if ('.!?。！？'.includes(last)) t += .45; else if (',;:，、；：'.includes(last)) t += .2;
      return end;
    });
  };

  // PrompterTypography.encode and scrimAlpha: black plate opacity giving white text 7:1 over the measured luma.
  const encode = l => l <= .0031308 ? 12.92 * l : 1.055 * Math.pow(l, 1 / 2.4) - .055;
  const scrim = luma => luma > 0 ? Math.min(Math.max(1 - encode(1.05 / 7 - .05) / luma, .12), .65) : .12;

  class Prompter {
    constructor(el) {
      this.el = el;
      const data = JSON.parse(el.dataset.prompter);
      this.kind = data.o; this.words = data.w; this.spaced = data.sp; this.fs = data.pt;
      this.ends = timeline(this.words, this.spaced);
      this.cursor = -1; this.offset = 0; this.target = null; this.t = -.6; this.last = 0; this.on = false;
      this.build();
      this.bg = el.parentElement.querySelector('img.lp-bg');
      if (this.bg && !this.bg.complete) this.bg.addEventListener('load', () => this.layout(), { once: true });
      new ResizeObserver(() => this.layout()).observe(el);
      new IntersectionObserver(([e]) => { this.on = e.isIntersecting; this.run(); }, { rootMargin: '100px' }).observe(el);
      rm.addEventListener('change', () => this.run());
    }

    build() {
      const el = this.el;
      el.innerHTML = '';
      this.stage = document.createElement('div'); this.stage.className = 'lp-stage';
      this.cv = document.createElement('canvas'); this.cv.className = 'lp-plates';
      this.clip = document.createElement('div'); this.clip.className = 'lp-clip';
      this.move = document.createElement('div'); this.move.className = 'lp-move';
      this.hl = document.createElement('i'); this.hl.className = 'lp-hl';
      this.text = document.createElement('p'); this.text.className = 'lp-text';
      this.spans = this.words.map((w, i) => {
        const s = document.createElement('span');
        s.textContent = w;
        this.text.append(s);
        // ScriptTokenizer words; spaced languages get the space back
        if (this.spaced && i < this.words.length - 1) this.text.append(' ');
        return s;
      });
      for (const side of ['a', 'b']) { const t = document.createElement('i'); t.className = 'lp-tick ' + side; this.clip.append(t); }
      this.move.append(this.hl, this.text);
      this.clip.append(this.move);
      this.stage.append(this.cv, this.clip);
      el.append(this.stage);
      if (this.kind !== 'mac') el.classList.add('cam');
    }

    setSize(pt, animated) {
      if (Math.abs(pt - this.fs) < .01) return;
      // not laid out yet (off screen or not in the page): the first layout uses the new size
      if (!this.rects || !this.rects.length) { this.fs = pt; return; }
      // PrompterUIView.setTextSize: the word on the reading line stays on it; an automatic change cross-fades
      const anchor = this.cursor < 0 ? 0 : this.cursor;
      if (animated && !rm.matches) {
        this.el.classList.add('lp-fade');
        setTimeout(() => this.el.classList.remove('lp-fade'), 300);
      }
      this.fs = pt;
      this.layout();
      this.offset = this.clamp(this.targetFor(anchor));
      this.target = null;
      this.paint();
    }

    layout() {
      const g = GEOMETRY[this.kind](this.fs), sc = this.el.clientWidth / g.W, u = 1;
      if (!sc) return;
      this.g = g; this.u = u; this.sc = sc;
      this.el.style.setProperty('--fs', this.fs);
      Object.assign(this.stage.style, { width: g.W + 'px', height: g.H + 'px', transform: `scale(${sc})` });
      const clipTop = g.clipTop ?? g.y, clipH = g.clipH ?? g.h + .3 * this.fs;
      Object.assign(this.clip.style, { top: clipTop * u + 'px', height: clipH * u + 'px' });
      // the 0.6 em feather at the band's top and bottom (camera mode only); the Mac panel clips at its edges
      const f = g.cam ? Math.min(.6 * this.fs / clipH, .5) * 100 : 0;
      this.clip.style.setProperty('--f', f + '%');
      Object.assign(this.move.style, { left: g.x * u + 'px', width: g.w * u + 'px', top: (g.y - clipTop) * u + 'px' });
      this.text.style.transform = `translateY(${PUSH * this.fs * u}px)`;
      // reading line ticks: 10 pt in the margins on both sides of the column, at the reading line
      const ty = (g.read - clipTop) * u;
      this.clip.querySelector('.a').style.cssText = `left:${(g.x - 12) * u}px;top:${ty}px`;
      this.clip.querySelector('.b').style.cssText = `left:${(g.x + g.w + 2) * u}px;top:${ty}px`;
      // word positions in points from the text top: line index x line height (all lines share one height)
      const box = this.text.getBoundingClientRect(), lh = LH * this.fs;
      this.rects = this.spans.map(s => {
        const r = s.getClientRects()[0] || s.getBoundingClientRect();
        // screen rects are scaled by the transform; an inline box starts half the leading below its line top
        const line = Math.round(((r.top - box.top) / sc - (LH - ASC - DESC) / 2 * this.fs) / lh);
        return { line: Math.max(line, 0), x: (r.left - box.left) / sc, w: r.width / sc };
      });
      this.lines = [];
      for (const r of this.rects) {
        const L = this.lines[r.line] || (this.lines[r.line] = { minX: Infinity, maxX: -Infinity });
        L.minX = Math.min(L.minX, r.x); L.maxX = Math.max(L.maxX, r.x + r.w);
      }
      const lastLine = this.rects.length ? this.rects[this.rects.length - 1].line : 0;
      this.maxOffset = Math.max(0, g.y + (lastLine + .5) * LH * this.fs - g.read);
      this.cv.width = Math.round(g.W * sc * devicePixelRatio); this.cv.height = Math.round(g.H * sc * devicePixelRatio);
      this.lumas = null;
      if (this.cursor < 0) this.setCursor(rm.matches ? Math.min(4, this.words.length - 1) : 0, true);
      else this.offset = this.clamp(this.offset);
      this.paint();
    }

    clamp(v) { return Math.min(Math.max(v, 0), this.maxOffset); }
    // ScrollEngine target: the word's vertical centre on the reading line
    targetFor(i) { const g = this.g; if (!this.rects[i]) return 0; return g.y + (this.rects[i].line + .5) * LH * this.fs - g.read; }

    setCursor(i, jump) {
      i = Math.min(Math.max(i, 0), this.words.length - 1);
      if (i === this.cursor) return;
      this.cursor = i;
      // read words dim, the current one in the highlight colour, the rest white
      this.spans.forEach((s, k) => { s.className = k < i ? 'r' : k === i ? 'c' : ''; });
      const t = this.targetFor(i);
      if (jump) { this.offset = this.clamp(t); this.target = null; } else this.target = t;
    }

    // Encoded luma behind a line, 90th percentile of an 8 x 8 grid (FrameAnalyzer.luma), from the still's own pixels.
    luma(rect) {
      if (!this.lumas) {
        this.lumas = new Map();
        try {
          const img = this.bg, c = document.createElement('canvas');
          c.width = img.naturalWidth; c.height = img.naturalHeight;
          const x = c.getContext('2d', { willReadFrequently: true });
          x.drawImage(img, 0, 0);
          this.px = { x, k: img.naturalWidth / this.g.W };
        } catch (e) { this.px = null; }
      }
      if (!this.px) return 0;
      const key = Math.round(rect.y) + ':' + Math.round(rect.h);
      if (this.lumas.has(key)) return this.lumas.get(key);
      const { x, k } = this.px, v = [];
      try {
        for (let i = 0; i < 8; i++) for (let j = 0; j < 8; j++) {
          const p = x.getImageData(Math.floor((rect.x + rect.w * (i + .5) / 8) * k), Math.floor((rect.y + rect.h * (j + .5) / 8) * k), 1, 1).data;
          v.push((.299 * p[0] + .587 * p[1] + .114 * p[2]) / 255);
        }
      } catch (e) { return 0; }
      v.sort((a, b) => a - b);
      const l = v[Math.min(Math.floor(v.length * .9), v.length - 1)];
      this.lumas.set(key, l);
      return l;
    }

    // PrompterUIView.drawPlates: one rounded plate per visible line (glyph band inflated .6 em across, .22 em up and
    // down), blurred as a whole (sigma .3 em), its opacity graded line to line from the picture behind each line.
    plates() {
      const g = this.g, u = this.u, fs = this.fs, c = this.cv.getContext('2d'), k = this.sc * devicePixelRatio;
      c.setTransform(1, 0, 0, 1, 0, 0);
      c.clearRect(0, 0, this.cv.width, this.cv.height);
      if (!g.cam || !this.bg) return;
      const top = g.y - this.offset, rects = [];
      this.lines.forEach((L, i) => {
        if (!L) return;
        const ly = top + i * LH * fs;
        if (ly + LH * fs < g.y - 40 || ly > g.y + g.h + 40) return;
        const y0 = ly + BASE * fs - CAP * fs - .14 * fs, y1 = ly + BASE * fs + .2 * fs;
        rects.push({ x: g.x + L.minX / u - .6 * fs, y: y0 - .22 * fs, w: L.maxX / u - L.minX / u + 1.2 * fs, h: y1 - y0 + .44 * fs });
      });
      if (!rects.length) return;
      const sigma = .3 * fs, radius = .5 * fs, t0 = rects[0].y - 2 * sigma, t1 = Math.max(rects[rects.length - 1].y + rects[rects.length - 1].h + 2 * sigma, t0 + 1);
      const layer = document.createElement('canvas');
      layer.width = this.cv.width; layer.height = this.cv.height;
      const o = layer.getContext('2d');
      o.setTransform(k, 0, 0, k, 0, 0);
      o.shadowColor = '#000'; o.shadowBlur = 2 * sigma * k; o.shadowOffsetX = -10000 * k;
      o.fillStyle = '#000';
      o.beginPath();
      for (const r of rects) o.roundRect(r.x + 10000, r.y, r.w, r.h, radius);
      o.fill();
      o.shadowColor = 'transparent';
      o.globalCompositeOperation = 'destination-in';
      const grad = o.createLinearGradient(0, t0, 0, t1), alphas = rects.map(r => scrim(this.luma(r)));
      grad.addColorStop(0, `rgba(0,0,0,${alphas[0]})`);
      rects.forEach((r, i) => grad.addColorStop(Math.min(Math.max((r.y + r.h / 2 - t0) / (t1 - t0), 0), 1), `rgba(0,0,0,${alphas[i]})`));
      grad.addColorStop(1, `rgba(0,0,0,${alphas[alphas.length - 1]})`);
      o.fillStyle = grad;
      o.fillRect(0, 0, g.W, g.H);
      c.drawImage(layer, 0, 0);
    }

    paint() {
      if (!this.g) return;
      const u = this.u, fs = this.fs;
      this.move.style.transform = `translateY(${-this.offset * u}px)`;
      const r = this.rects[this.cursor];
      if (r) {
        // the current-word highlight: cap top - .14 em to baseline + .2 em, .12 em past the word, .2 em corners
        const y = (r.line * LH + BASE - CAP - .14) * fs * u;
        Object.assign(this.hl.style, { left: r.x - .12 * fs * u + 'px', top: y + 'px', width: r.w + .24 * fs * u + 'px', height: (CAP + .34) * fs * u + 'px' });
      }
      this.plates();
    }

    run() {
      const go = this.on && !rm.matches && !document.hidden && !paused;
      if (go && !this.raf) { this.last = 0; this.raf = requestAnimationFrame(f => this.tick(f)); }
      if (!go && this.raf) { cancelAnimationFrame(this.raf); this.raf = 0; }
    }

    tick(now) {
      const dt = this.last ? Math.min((now - this.last) / 1000, .1) : 1 / 60;
      this.last = now;
      this.t += dt;
      // the word being read: the first not yet finished, seen 0.15 s late like recognition; then a rest and again
      if (this.t > this.ends[this.ends.length - 1] + 2.4) { this.t = -.6; this.cursor = -1; this.setCursor(0, true); }
      else {
        const i = this.ends.findIndex(e => e > this.t - .15);
        this.setCursor(i < 0 ? this.ends.length - 1 : i);
      }
      // ScrollEngine.tick: ease toward the target at rate 8, at most 1200 pt/s, done within half a point
      if (this.target !== null) {
        const goal = this.clamp(this.target), limit = 1200 * dt;
        this.offset += Math.min(Math.max((goal - this.offset) * (1 - Math.exp(-dt * 8)), -limit), limit);
        if (Math.abs(goal - this.offset) < .5) { this.offset = goal; this.target = null; }
      }
      this.paint();
      this.raf = requestAnimationFrame(f => this.tick(f));
    }
  }

  const all = [...document.querySelectorAll('[data-prompter]')].map(el => (el.prompter = new Prompter(el)));
  // site.js clones scenes (the reduced-motion distance row); clones get their own prompter
  window.SPPrompter = el => { const p = new Prompter(el); el.prompter = p; all.push(p); return p; };
  document.addEventListener('visibilitychange', () => all.forEach(p => p.run()));
  document.addEventListener('sp-motion', e => { paused = e.detail; all.forEach(p => p.run()); });
  if (document.fonts) document.fonts.ready.then(() => all.forEach(p => p.layout()));
})();
