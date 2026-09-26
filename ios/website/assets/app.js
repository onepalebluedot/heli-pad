(() => {
  'use strict';

  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
  const icons = () => window.lucide && window.lucide.createIcons();

  /** Minutes after midnight → "3:29 PM", the way the app prints times. */
  const fmt = (mins, withPeriod = true) => {
    const h24 = Math.floor(mins / 60) % 24;
    const m = ((mins % 60) + 60) % 60;
    const h = h24 % 12 || 12;
    return `${h}:${String(m).padStart(2, '0')}${withPeriod ? (h24 < 12 ? ' AM' : ' PM') : ''}`;
  };

  /** Runs `start` while the element is on screen and `stop` when it leaves. */
  const whileVisible = (el, start, stop, threshold = 0.25) => {
    if (!el) return;
    new IntersectionObserver(entries => {
      entries.forEach(e => (e.isIntersecting ? start() : stop()));
    }, { threshold }).observe(el);
  };

  /* ------------------------------------------------------------------
   * Opening reveal. The centre panel widens with scroll; the nav stays out
   * of the way until the title has landed, as on the page that inspired it.
   * ------------------------------------------------------------------ */
  const intro = $('#intro');
  const nav = $('#nav');
  let ticking = false;
  const readVh = () => parseFloat(document.documentElement.style.getPropertyValue('--vh')) || window.innerHeight / 100;
  let stableVh = readVh();

  const onScroll = () => {
    ticking = false;
    const rect = intro.getBoundingClientRect();
    // Measured against the load-time height (--vh), not innerHeight: a toolbar
    // collapsing mid-scroll changes innerHeight and made the reveal lurch.
    const travel = intro.offsetHeight - stableVh * 100;
    const raw = clamp(-rect.top / (travel * 0.85), 0, 1);
    // Ease-in-out so the panel lingers at both ends instead of sliding linearly.
    const p = raw < 0.5 ? 2 * raw * raw : 1 - Math.pow(-2 * raw + 2, 2) / 2;
    intro.style.setProperty('--p', p.toFixed(4));

    const pastIntro = rect.bottom <= 68;
    nav.classList.toggle('is-hidden', !pastIntro && p < 0.85);
    nav.classList.toggle('is-dark', !pastIntro);
    nav.classList.toggle('is-solid', pastIntro);
  };
  window.addEventListener('scroll', () => {
    if (!ticking) { ticking = true; requestAnimationFrame(onScroll); }
  }, { passive: true });
  window.addEventListener('resize', () => requestAnimationFrame(() => { stableVh = readVh(); onScroll(); }));
  onScroll();

  /* ------------------------------------------------------------------
   * Image switching. Each [data-cycle] group steps through its images while
   * visible; groups are staggered so the triptych never cuts all at once.
   * ------------------------------------------------------------------ */
  $$('[data-cycle]').forEach((group, gi) => {
    const imgs = $$('img', group);
    if (imgs.length < 2 || reduceMotion) return;
    let i = 0, timer = null, delay = null;
    const period = group.classList.contains('panel-center') ? 3200 : group.classList.contains('band-media') ? 4200 : 4600;
    const step = () => {
      imgs[i].classList.remove('is-on');
      i = (i + 1) % imgs.length;
      imgs[i].classList.add('is-on');
    };
    whileVisible(group, () => {
      if (timer || delay) return;
      delay = setTimeout(() => { delay = null; timer = setInterval(step, period); }, gi * 700);
    }, () => {
      clearTimeout(delay); delay = null;
      clearInterval(timer); timer = null;
    }, 0.05);
  });

  /* ------------------------------------------------------------------
   * Go screen mockup. A small re-creation of GoDialCardView: the ring holds
   * the run-up (minutes/60), the card tone carries urgency.
   * ------------------------------------------------------------------ */
  const TONES = {
    ontrack: { card: '#234d3d', deep: '#a3e635', bright: '#ffd866' },
    soon: { card: '#55532e', deep: '#ffd866', bright: '#f59e0b' },
    now: { card: '#814d3c', deep: '#f97316', bright: '#ef4444' },
    clear: { card: '#235746', deep: '#7cae5f', bright: '#caeaa4' }
  };
  let gradSeq = 0;

  const dialSVG = () => {
    const id = `ring${++gradSeq}`;
    const ticks = Array.from({ length: 12 }, (_, i) => {
      const a = i * Math.PI / 6, major = i % 3 === 0;
      const r1 = 86 - (major ? 12 : 8), r2 = 83;
      return `<line x1="${100 + r1 * Math.cos(a)}" y1="${100 + r1 * Math.sin(a)}" x2="${100 + r2 * Math.cos(a)}" y2="${100 + r2 * Math.sin(a)}" stroke="rgba(255,255,255,${major ? .35 : .18})" stroke-width="${major ? 2 : 1.2}"/>`;
    }).join('');
    return `<svg viewBox="0 0 200 200" aria-hidden="true">
      <defs><linearGradient id="${id}" x1="0" y1="0" x2="1" y2="1"><stop class="g1" offset="0"/><stop class="g2" offset="1"/></linearGradient>
      <radialGradient id="${id}b"><stop class="b1" offset="0" stop-opacity=".65"/><stop class="b1" offset=".5" stop-opacity=".18"/><stop class="b1" offset="1" stop-opacity="0"/></radialGradient></defs>
      ${ticks}
      <circle cx="100" cy="100" r="86" fill="none" stroke="rgba(255,255,255,.14)" stroke-width="12"/>
      <circle class="arc" cx="100" cy="100" r="86" fill="none" stroke="url(#${id})" stroke-width="12" stroke-linecap="round" pathLength="100" stroke-dasharray="100" stroke-dashoffset="100" transform="rotate(-90 100 100)"/>
      <g class="bead"><circle r="22" fill="url(#${id}b)"/><circle class="bead-core" r="8.5"/><circle r="3.5" fill="#fff"/></g>
    </svg>`;
  };

  const railRow = (r) => `
    <div class="rail-row${r.done ? ' done' : ''}">
      <span class="t">${r.t}</span>
      <span class="disc disc-${r.who}">${r.init}</span>
      <div><b>${r.title}</b><span class="m">${r.meta}</span>${r.leave ? `<span class="l">Leave ${r.leave}</span>` : ''}</div>
      <span class="tick"><i data-lucide="check"></i></span>
    </div>`;

  const TRIP = { start: 16 * 60, drive: 23, buffer: 5 };
  const LEAVE = TRIP.start - TRIP.drive - TRIP.buffer; // 3:32 PM

  const screenShell = (card, rows, statusTime) => `
    <div class="sb" aria-hidden="true" style="position:absolute;top:calc(18*var(--u));left:calc(34*var(--u));right:calc(28*var(--u));display:flex;justify-content:space-between;font-weight:700;font-size:calc(15*var(--u))"><span class="sb-time">${statusTime}</span><span style="display:flex;gap:calc(5*var(--u))"><i data-lucide="signal"></i><i data-lucide="wifi"></i><i data-lucide="battery-full"></i></span></div>
    <div class="app-top"><span class="who"><span class="disc disc-me">A</span>All <i data-lucide="chevron-down"></i></span><span class="house">RIVERA · PAD</span><span class="gear"><i data-lucide="settings"></i></span></div>
    <div class="masthead">
      <div><p class="app-eyebrow">TODAY</p><p class="app-date">Tuesday, Oct 6</p></div>
      <div class="wx"><span class="wx-top"><i data-lucide="sun"></i>58°–71°</span><small>Sunny</small></div>
    </div>
    ${card}
    <p class="rail-head">Today's family relay</p>
    <div class="rail">${rows.map(railRow).join('')}</div>
    <div class="app-tabs"><span class="tab-ico on"><i data-lucide="zap"></i>Go</span><span class="tab-ico"><i data-lucide="calendar-days"></i></span><span class="tab-ico"><i data-lucide="message-circle"></i></span><span class="tab-ico"><i data-lucide="users"></i></span><span class="tab-ico"><i data-lucide="list-checks"></i></span></div>`;

  const tripCard = () => `
    <div class="go-card">
      <div class="go-top">
        <div class="dial">${dialSVG()}<div class="dial-center"><span class="dial-num"></span><span class="dial-unit"></span></div></div>
        <div class="route">
          <div class="node node-leave"><i></i><div><b>${fmt(LEAVE)}</b><small>LEAVE</small></div></div>
          <div class="leg"><span class="leg-line"></span><div class="leg-meta"><em>${TRIP.drive} min</em><span class="gps">LIVE GPS</span></div></div>
          <div class="node node-arrive"><i></i><div><b>${fmt(TRIP.start)}</b><small>ARRIVE</small></div></div>
        </div>
      </div>
      <div class="go-title"><h4>Soccer practice</h4><p><i data-lucide="car-front"></i>Riverside Fields <i data-lucide="chevron-right"></i></p></div>
      <div class="go-badge"><span><i data-lucide="user"></i>Maya</span></div>
      <div class="go-actions"><span class="dir"><i data-lucide="navigation"></i>Directions</span><span class="chk"><i data-lucide="check"></i></span></div>
    </div>`;

  const clearCard = () => `
    <div class="go-card is-clear" style="--card:#235746">
      <div class="go-top">
        <div class="dial">${dialSVG()}<div class="dial-center"><span class="dial-num word">✓</span><span class="dial-unit">ALL CLEAR</span></div></div>
        <div class="clear-copy"><h4>All clear</h4><p>Every handoff is marked done for today.</p></div>
      </div>
    </div>`;

  const RELAY = [
    { t: '7:45 AM', who: 'dad', init: 'D', title: 'School drop-off', meta: 'Maple Elementary (Maya, Leo)' },
    { t: '4:00 PM', who: 'mom', init: 'M', title: 'Soccer practice', meta: 'Riverside Fields (Maya)', leave: fmt(LEAVE) },
    { t: '5:15 PM', who: 'nani', init: 'N', title: 'Piano lesson', meta: 'Oak St Music (Leo)', leave: '4:58 PM' }
  ];

  /** Paints a dial for a tone and fill fraction (0…1). */
  const paintDial = (root, toneKey, fraction) => {
    const tone = TONES[toneKey];
    const card = $('.go-card', root);
    card.style.setProperty('--card', tone.card);
    $$('.g1', root).forEach(s => s.setAttribute('stop-color', tone.deep));
    $$('.g2', root).forEach(s => s.setAttribute('stop-color', tone.bright));
    $$('.b1', root).forEach(s => s.setAttribute('stop-color', tone.bright));
    $('.bead-core', root).setAttribute('fill', tone.bright);
    const arc = $('.arc', root);
    arc.style.strokeDashoffset = String(100 - fraction * 100);
    arc.style.opacity = fraction < 0.01 ? '0' : '1';
    const bead = $('.bead', root);
    const showBead = fraction > 0.015 && fraction < 0.995;
    bead.style.opacity = showBead ? '1' : '0';
    const a = fraction * 2 * Math.PI - Math.PI / 2;
    bead.setAttribute('transform', `translate(${100 + 86 * Math.cos(a)} ${100 + 86 * Math.sin(a)})`);
  };

  /** Sets the Go card to "n minutes until you leave", matching the app's tone rules. */
  const setMinutes = (root, mins) => {
    const tone = mins <= 0 ? 'now' : mins <= 15 ? 'soon' : 'ontrack';
    paintDial(root, tone, clamp(mins / 60, 0, 1));
    const num = $('.dial-num', root), unit = $('.dial-unit', root);
    if (mins <= 0) {
      num.textContent = 'NOW'; num.className = 'dial-num word gold'; unit.textContent = 'leave';
    } else {
      num.textContent = String(mins); num.className = 'dial-num'; unit.textContent = 'min · to leave';
    }
    const sb = $('.sb-time', root);
    if (sb) sb.textContent = fmt(LEAVE - mins, false);
  };

  const goScreens = {};
  $$('[data-go]').forEach(el => {
    const kind = el.dataset.go;
    if (kind === 'done') {
      el.innerHTML = screenShell(clearCard(), RELAY.map(r => ({ ...r, leave: null })), '6:52');
    } else {
      el.innerHTML = screenShell(tripCard(), RELAY.map((r, i) => ({ ...r, done: i === 0 })), fmt(LEAVE - 24, false));
    }
    goScreens[kind] = el;
  });
  icons();
  if (goScreens.done) paintDial(goScreens.done, 'clear', 1);

  /* Hero loop: the countdown runs, the leave alert drops in at ten minutes,
     and the card warms from forest to olive to clay as the minutes go. */
  const heroToast = $('#heroToast');
  if (goScreens.hero) {
    const hero = goScreens.hero;
    let mins = 24, timer = null;
    setMinutes(hero, reduceMotion ? 10 : mins);
    if (reduceMotion) heroToast.classList.add('is-in');
    const tick = () => {
      mins -= 1;
      if (mins < -3) {
        mins = 24;
        heroToast.classList.remove('is-in');
      }
      setMinutes(hero, Math.max(mins, 0));
      if (mins === 10) heroToast.classList.add('is-in');
      if (mins === 2) heroToast.classList.remove('is-in');
    };
    if (!reduceMotion) {
      whileVisible(hero.closest('.hero-art'), () => { if (!timer) timer = setInterval(tick, 750); },
        () => { clearInterval(timer); timer = null; }, 0.2);
    }
  }

  /* ------------------------------------------------------------------
   * Lock screen: the check-in, then the driver alert, then the one that
   * matters — "Leave in 10 minutes" — lands on top.
   * ------------------------------------------------------------------ */
  const stack = $('#lockStack');
  if (stack) {
    const notes = $$('.notif', stack);
    const byAt = at => notes.find(n => n.dataset.at === String(at));
    const clockEls = [$('#lockClock'), $('#lockClockSmall')];
    const setClock = t => clockEls.forEach(el => { if (el) el.textContent = t; });
    let timers = [];
    const clear = () => { timers.forEach(clearTimeout); timers = []; };
    const run = () => {
      clear();
      notes.forEach(n => n.classList.remove('is-in'));
      setClock('3:21');
      timers.push(setTimeout(() => byAt(2).classList.add('is-in'), 500));
      timers.push(setTimeout(() => byAt(1).classList.add('is-in'), 1400));
      timers.push(setTimeout(() => { setClock('3:22'); byAt(0).classList.add('is-in'); }, 2800));
      timers.push(setTimeout(run, 9000));
    };
    if (reduceMotion) {
      notes.forEach(n => n.classList.add('is-in')); setClock('3:22');
    } else {
      whileVisible(stack.closest('.phone'), run, clear, 0.35);
    }
  }

  /* ------------------------------------------------------------------
   * Drive-time lab. Leave-by = start − drive − buffer; the alert is ten
   * minutes before that (NotificationService.leadMinutes).
   * ------------------------------------------------------------------ */
  const lab = $('.drive-lab');
  if (lab) {
    const START = 16 * 60, AXIS0 = 15 * 60, SPAN = 60, LEAD = 10;
    const x = t => `${((t - AXIS0) / SPAN) * 100}%`;
    const els = {
      leave: $('#leaveBy'), buzz: $('#buzzAt'), cap: $('#vizCaption'),
      lead: $('#segLead'), drive: $('#segDrive'), buffer: $('#segBuffer'),
      bell: $('#markBell'), go: $('#markLeave'), car: $('#segDrive .car-track')
    };
    const val = name => Number($(`input[name="${name}"]:checked`, lab).value);
    const update = () => {
      const drive = val('road'), buffer = val('buffer');
      const leave = START - drive - buffer, buzz = leave - LEAD;
      els.leave.textContent = fmt(leave);
      els.buzz.textContent = fmt(buzz);
      els.cap.textContent = `${drive} min drive${buffer ? ` + ${buffer} min buffer` : ''} → leave at ${fmt(leave, false)}. The alert lands at ${fmt(buzz, false)}.`;
      Object.assign(els.lead.style, { left: x(buzz), width: `${(LEAD / SPAN) * 100}%` });
      Object.assign(els.drive.style, { left: x(leave), width: `${(drive / SPAN) * 100}%` });
      Object.assign(els.buffer.style, { left: x(leave + drive), width: `${(buffer / SPAN) * 100}%`, opacity: buffer ? 1 : 0 });
      els.bell.style.setProperty('--x', x(buzz));
      els.go.style.setProperty('--x', x(leave));
      $('span', els.go).textContent = fmt(leave, false);
      $('span', els.bell).textContent = fmt(buzz, false);
      // Restart the car so each change reads as a new trip.
      els.car.style.animation = 'none'; void els.car.offsetWidth; els.car.style.animation = '';
    };
    let auto = null, userTouched = false;
    const roads = $$('input[name="road"]', lab);
    const stopAuto = () => { clearInterval(auto); auto = null; };
    lab.addEventListener('change', () => update());
    lab.addEventListener('pointerdown', () => { userTouched = true; stopAuto(); });
    lab.addEventListener('keydown', () => { userTouched = true; stopAuto(); });
    update();
    if (!reduceMotion) {
      whileVisible(lab, () => {
        if (userTouched || auto) return;
        auto = setInterval(() => {
          const i = roads.findIndex(r => r.checked);
          roads[(i + 1) % roads.length].checked = true;
          update();
        }, 3400);
      }, stopAuto, 0.4);
    }
  }

  /* ------------------------------------------------------------------
   * Week tabs. Auto-advance while on screen until someone picks one.
   * ------------------------------------------------------------------ */
  const tabs = $$('[role="tab"]');
  if (tabs.length) {
    const DUR = 7000;
    let current = 0, timer = null, userPicked = false, inView = false, goTimer = null;

    const runGo = on => {
      clearInterval(goTimer); goTimer = null;
      const go = goScreens.tabs;
      if (!go) return;
      let m = 16;
      setMinutes(go, reduceMotion ? 12 : m);
      if (on && !reduceMotion) goTimer = setInterval(() => { m = Math.max(0, m - 1); setMinutes(go, m); if (m === 0) clearInterval(goTimer); }, DUR / 18);
    };
    const runDone = () => {
      const rows = $$('.rail-row', goScreens.done);
      rows.forEach(r => r.classList.remove('done'));
      rows.forEach((r, i) => setTimeout(() => r.classList.add('done'), reduceMotion ? 0 : 500 + i * 700));
    };

    const select = (i, focus = false) => {
      current = i;
      tabs.forEach((t, j) => {
        const on = j === i;
        t.setAttribute('aria-selected', String(on));
        t.tabIndex = on ? 0 : -1;
        t.classList.remove('is-running');
        $(`#${t.getAttribute('aria-controls')}`).hidden = !on;
      });
      if (focus) tabs[i].focus();
      const id = tabs[i].id;
      runGo(id === 'tab-go');
      if (id === 'tab-done') runDone();
      schedule();
    };
    const schedule = () => {
      clearTimeout(timer); timer = null;
      if (userPicked || !inView || reduceMotion) return;
      const t = tabs[current];
      t.style.setProperty('--dur', `${DUR}ms`);
      void t.offsetWidth;
      t.classList.add('is-running');
      timer = setTimeout(() => select((current + 1) % tabs.length), DUR);
    };

    tabs.forEach((t, i) => {
      t.addEventListener('click', () => { userPicked = true; select(i); });
      t.addEventListener('keydown', e => {
        const k = e.key;
        let n = null;
        if (k === 'ArrowDown' || k === 'ArrowRight') n = (i + 1) % tabs.length;
        if (k === 'ArrowUp' || k === 'ArrowLeft') n = (i - 1 + tabs.length) % tabs.length;
        if (k === 'Home') n = 0;
        if (k === 'End') n = tabs.length - 1;
        if (n !== null) { e.preventDefault(); userPicked = true; select(n, true); }
      });
    });
    whileVisible($('.tabs'), () => { inView = true; if (!timer) select(current); },
      () => { inView = false; clearTimeout(timer); timer = null; tabs.forEach(t => t.classList.remove('is-running')); }, 0.35);
    runGo(false);
  }

  /* ------------------------------------------------------------------
   * Scroll-in reveals.
   * ------------------------------------------------------------------ */
  const revealIO = new IntersectionObserver(entries => {
    entries.forEach(e => {
      if (!e.isIntersecting) return;
      e.target.classList.add('is-in');
      revealIO.unobserve(e.target);
    });
  }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });
  $$('.reveal').forEach((el, i) => {
    if (el.classList.contains('card')) el.style.transitionDelay = `${(i % 3) * 90}ms`;
    revealIO.observe(el);
  });

  /* ------------------------------------------------------------------
   * Alpha sign-up.
   * ------------------------------------------------------------------ */
  const form = $('#joinForm');
  if (form) {
    const status = $('#formStatus');
    const button = $('button[type="submit"]', form);
    const label = $('.btn-label', button);
    const emailOK = v => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v);

    form.addEventListener('input', e => e.target.removeAttribute('aria-invalid'));
    form.addEventListener('submit', async e => {
      e.preventDefault();
      const nameInput = form.elements.namedItem('name');
      const emailInput = form.elements.namedItem('email');
      const name = nameInput.value.trim();
      const email = emailInput.value.trim();
      status.textContent = '';
      if (!name) { nameInput.setAttribute('aria-invalid', 'true'); nameInput.focus(); status.textContent = 'Please add your name.'; return; }
      if (!emailOK(email)) { emailInput.setAttribute('aria-invalid', 'true'); emailInput.focus(); status.textContent = 'That email doesn’t look quite right.'; return; }

      button.disabled = true;
      label.textContent = 'Sending…';
      try {
        const res = await fetch(form.dataset.endpoint, {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ name, email, website: form.elements.namedItem('website').value })
        });
        if (!res.ok) {
          // Only a 400 carries a message written for the person filling the form.
          const body = res.status === 400 ? await res.json().catch(() => ({})) : {};
          throw new Error(body.error || 'Something went wrong on our side. Please try again in a moment.');
        }
        $('#joinName').textContent = name.split(/\s+/)[0];
        form.hidden = true;
        const done = $('#joinDone');
        done.hidden = false;
        done.focus();
      } catch (err) {
        status.textContent = err instanceof TypeError
          ? 'We couldn’t reach the sign-up service. Please try again in a moment.'
          : err.message;
      } finally {
        button.disabled = false;
        label.textContent = 'Request an invite';
      }
    });
  }
})();
