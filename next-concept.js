/* Design concept only. Existing local event data, edit and assignment flows.
   Preview time is separate from the other concepts and is never persisted. */
(() => {
  const view = { offset: 0, kid: 'All', time: '14:40', showDone: false };
  const crew = ['Mom', 'Dad', 'Nani', 'Grandma'];
  const initials = { Mom: 'M', Dad: 'D', Nani: 'N', Grandma: 'G', Family: 'All', TBD: '?' };
  const colors = { Mom: '#e7ddc9', Dad: '#dce7d4', Nani: '#eadce5', Grandma: '#dde6ea', Family: '#eae7c5' };
  const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const day = () => (getTodayIndex() + view.offset) % 7;
  const now = () => view.offset ? -1 : (view.time ? timeToMinutes(view.time) : getNowMinutes());
  const kids = event => goKidsOf(event).includes('All') ? ['Soni', 'Maya', 'Noah'] : goKidsOf(event);
  const kidLabel = event => kids(event).length === 3 ? 'All children' : kids(event).join(' & ');
  const isTravel = event => event.mode !== 'Home' && event.location !== 'Home';
  const time = mins => formatTime(minutesToTime(Math.max(0, mins)));
  const depart = event => Math.max(0, event.departBy ?? timeToMinutes(event.time));
  const scoped = event => (state.currentUser === 'All' || event.lead === state.currentUser || ['Family', 'TBD'].includes(event.lead)) && (view.kid === 'All' || kids(event).includes(view.kid));
  const badge = name => `<span class="nx-driver" style="--nx-person-bg:${colors[name] || '#f0dcc6'}">${escape(initials[name] || name[0])}</span>`;
  const shortTitle = title => title.replace('Football Practice Pickup', 'Football pickup').replace('Taco Bowls & Family Dinner', 'Family dinner');
  const sun = `<svg class="nx-sun" viewBox="0 0 64 64" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true"><circle cx="32" cy="32" r="14"/><path d="M32 4v7m0 42v7M4 32h7m42 0h7M12 12l5 5m30 30 5 5M12 52l5-5m30-30 5-5M20 6l3 7m18 38 3 7M6 44l7-3m38-18 7-3M6 20l7 3m38 18 7 3M20 58l3-7m18-38 3-7"/></svg>`;

  function timing(event) {
    const clock = now(), start = timeToMinutes(event.time), leave = depart(event);
    if (!view.offset && clock >= start) return { tone: 'check', label: 'Check status', heading: 'Did this handoff happen?', note: `Scheduled for ${formatTime(event.time)}. Confirm it or adjust the plan.` };
    if (event.lead === 'TBD') return { tone: 'soon', label: 'Driver needed', heading: 'Who can take this one?', note: `Arrive by ${formatTime(event.time)}. Review available caregivers below.` };
    if (view.offset) return { tone: 'calm', label: 'Planned', heading: `${isTravel(event) ? 'Leave' : 'Be there'} at ${time(isTravel(event) ? leave : start)}`, note: `${dayNames[day()]} · ${isTravel(event) ? `${event.eta} min travel + ${Math.max(0, start - leave - event.eta)} min buffer` : 'No travel needed'}` };
    if (!isTravel(event)) return { tone: 'calm', label: 'At home', heading: `Together at ${formatTime(event.time)}`, note: 'No drive needed. A little time together.' };
    const untilLeave = leave - clock;
    const arrival = clock + event.eta;
    const margin = start - arrival;
    if (margin < 0) return { tone: 'late', label: 'Running behind', heading: `${-margin} min late if you leave now`, note: `Estimated arrival ${time(arrival)} · due ${formatTime(event.time)}. Check whether someone else can help.` };
    if (untilLeave <= 0) return { tone: 'soon', label: 'Time to go', heading: 'Leave now', note: `Estimated arrival ${time(arrival)}. ${margin ? `Still ${margin} min before the handoff.` : 'You can just make the handoff.'}` };
    return { tone: untilLeave <= 10 ? 'soon' : 'calm', label: untilLeave <= 10 ? 'Get ready' : 'You have time', heading: `Leave in ${untilLeave >= 60 ? `${Math.floor(untilLeave / 60)}h${untilLeave % 60 ? ` ${untilLeave % 60}m` : ''}` : `${untilLeave} min`}`, note: `A ${event.eta} min trip, with ${Math.max(0, start - leave - event.eta)} min to spare when you arrive.` };
  }

  function hero(event, unconfirmed) {
    if (!event) return `<article class="nx-trip"><div class="nx-trip-top"><span class="nx-eyebrow">A little breathing room</span><span class="nx-status">✓ ${view.offset ? 'Day ahead' : 'All done'}</span></div><h2>${view.offset ? 'Nothing on your list.' : 'You’re all caught up.'}</h2><p class="nx-trip-note">${view.kid !== 'All' ? `No remaining handoffs for ${escape(view.kid)} in this view.` : 'No remaining handoffs in this view. You can check the whole family below.'}</p></article>`;
    const status = timing(event), travel = isTravel(event);
    const title = escape(status.heading).replace(/ (AM|PM)$/, ' <small>$1</small>');
    const label = unconfirmed ? 'Unconfirmed handoff' : 'Your next handoff';
    return `<article class="nx-trip" data-tone="${status.tone}" aria-label="Next handoff">
      <div class="nx-trip-top"><span class="nx-eyebrow">${state.currentUser === 'All' ? 'Next family handoff' : label}</span><span class="nx-status"><i></i>${status.label}</span></div>
      <h2>${title}</h2><p class="nx-trip-note">${status.note}</p>
      <div class="nx-passenger"><span class="nx-kid-icon" aria-hidden="true">${kids(event).length > 1 ? '☀' : (kidIcons[kids(event)[0]] || '↗')}</span><div><strong>${escape(kidLabel(event))}</strong><p>${escape(shortTitle(event.title))} · ${escape(event.lead === 'TBD' ? 'driver needed' : event.lead === 'Family' ? 'family time' : `${event.lead} ${travel ? 'takes this one' : 'is responsible'}`)}</p></div></div>
      <div class="nx-route">
        <i class="nx-route-dot"></i><div class="nx-route-place"><strong>${escape(travel ? event.origin : 'At home')}</strong><span>${travel ? `${escape(event.mode)} · ${event.eta} min + buffer` : 'No travel needed'}</span></div><div class="nx-route-time"><strong>${travel ? time(depart(event)) : '—'}</strong><span>${travel ? 'leave by' : 'stay home'}</span></div>
        <i class="nx-route-dot end"></i><div class="nx-route-place"><strong>${escape(event.location)}</strong><span>${travel ? 'Handoff' : 'Starts'}</span></div><div class="nx-route-time"><strong>${formatTime(event.time)}</strong><span>${travel ? 'arrive by' : 'starts at'}</span></div>
      </div><div class="nx-trip-actions"><button class="nx-primary" data-nx-action="${event.lead === 'TBD' ? 'assign' : 'details'}" data-id="${event.id}">${event.lead === 'TBD' ? 'Find a driver' : status.tone === 'check' ? 'Review handoff' : travel ? 'View trip' : 'View appointment'} <span aria-hidden="true">↗</span></button><button class="nx-secondary" data-nx-action="edit" data-id="${event.id}">Edit</button></div>
    </article>`;
  }

  function stop(event, target) {
    const travel = isTravel(event), past = !view.offset && now() >= timeToMinutes(event.time) && !event.done;
    const [clock, period] = formatTime(event.time).split(' ');
    return `<li class="nx-stop ${event.done ? 'is-done' : ''} ${target?.id === event.id ? 'is-next' : ''}"><div class="nx-stop-time">${clock}<span>${period} · ${travel ? 'arrive' : 'starts'}</span></div>
      <button class="nx-stop-main" data-nx-action="details" data-id="${event.id}"><strong>${escape(kidLabel(event))} · ${escape(shortTitle(event.title))}</strong><p>${escape(event.location)}</p><p class="${past || event.conflict || event.lead === 'TBD' ? 'nx-stop-warning' : ''}">${event.done ? '✓ Completed' : past ? 'Check status · not confirmed' : event.lead === 'TBD' ? 'Driver needed' : event.conflict ? 'Schedule overlap · review driver' : travel ? `Leave ${time(depart(event))} · ${escape(event.lead)}` : 'No travel needed'}</p></button>
      <button class="nx-driver" style="--nx-person-bg:${colors[event.lead] || '#f0dcc6'}" data-nx-action="assign" data-id="${event.id}" aria-label="Review driver for ${escape(event.title)}">${escape(initials[event.lead] || '?')}</button></li>`;
  }

  function suggestion(plan, drivers) {
    const pending = plan.filter(e => !e.done && (view.offset || timeToMinutes(e.time) > now()));
    const trouble = pending.find(e => e.lead === 'TBD' || e.conflict);
    if (trouble) {
      const rec = getSmartDriverRecommendation(trouble, drivers, sortedEvents(day())).bestCandidate;
      const viable = rec && !rec.hasConflict && !rec.causesDelay;
      return `<aside class="nx-suggestion"><span class="nx-spark" aria-hidden="true">✳</span><div><h3>${viable ? `Could ${escape(rec.name)} take ${escape(kidLabel(trouble))}?` : 'This handoff needs a second look'}</h3><p>${escape(shortTitle(trouble.title))} at ${formatTime(trouble.time)}. ${viable ? `${escape(rec.name)} has no detected overlap and an estimated ${rec.eta} min trip.` : 'The schedule has a gap or overlap. Compare the caregivers before assigning.'}</p><button data-nx-action="assign" data-id="${trouble.id}">Compare drivers <span aria-hidden="true">↗</span></button></div></aside>`;
    }
    // A review suggestion only: no background reassignment or new optimizer.
    const loads = Object.entries(drivers).sort((a,b) => b[1].driveMinutes-a[1].driveMinutes);
    const busiest = loads[0];
    const candidate = busiest && pending.find(e => e.lead === busiest[0] && isTravel(e));
    const alternative = candidate && getSmartDriverRecommendation(candidate, drivers, sortedEvents(day())).candidates.filter(c => c.name !== candidate.lead && !c.hasConflict && !c.causesDelay).sort((a,b) => (drivers[a.name]?.driveMinutes || 0) - (drivers[b.name]?.driveMinutes || 0))[0];
    if (candidate && alternative && busiest[1].driveMinutes > (drivers[alternative.name]?.driveMinutes || 0) + 10) return `<aside class="nx-suggestion"><span class="nx-spark" aria-hidden="true">✳</span><div><h3>A little less driving for ${escape(busiest[0])}?</h3><p>${escape(alternative.name)} has no detected overlap for ${escape(kidLabel(candidate))}’s ${formatTime(candidate.time)} handoff. Compare the trips before making a change.</p><button data-nx-action="assign" data-id="${candidate.id}">Review a possible swap <span aria-hidden="true">↗</span></button></div></aside>`;
    return '';
  }

  window.renderNextConcept = function() {
    const root = document.getElementById('nextScreen');
    const { plan, drivers } = calculateDayPlan(day());
    const mine = plan.filter(scoped);
    const pending = mine.filter(e => !e.done);
    const unconfirmed = !view.offset ? pending.filter(e => now() >= timeToMinutes(e.time)) : [];
    const future = pending.filter(e => view.offset || now() < timeToMinutes(e.time)).sort((a,b) => depart(a)-depart(b));
    const target = future[0] || unconfirmed[0];
    const completed = mine.filter(e => e.done);
    const entries = view.showDone ? mine : pending;
    const dateNumber = dayDates[getTodayIndex()] + view.offset;
    // Avoid interrupting focus or pointer interaction on the five-second ticker.
    const focusKey = root.contains(document.activeElement) ? document.activeElement.dataset.nxKey : null;
    const html = `<div class="nx-masthead"><div><div class="nx-eyebrow">${dayAbbrs[day()]} · Aug ${dateNumber} · ${view.time ? 'Preview' : 'Live clock'}</div><h1>Your day, together.</h1></div>${sun}</div>
      <div class="nx-days" aria-label="Choose day">${Array.from({length:7}, (_,offset) => `<button class="nx-day" data-nx-action="day" data-value="${offset}" aria-pressed="${view.offset === offset}" aria-label="${dayNames[(getTodayIndex()+offset)%7]}, August ${dayDates[getTodayIndex()]+offset}"><span>${offset === 0 ? 'Today' : dayAbbrs[(getTodayIndex()+offset)%7]}</span><strong>${dayDates[getTodayIndex()]+offset}</strong><i></i></button>`).join('')}</div>
      <div class="nx-scope"><strong>${state.currentUser === 'All' ? 'The whole family' : `${escape(state.currentUser)}’s handoffs`}${view.kid !== 'All' ? ` · ${escape(view.kid)}` : ''}</strong><button class="nx-text-btn" data-nx-action="crew">Switch caregiver ↓</button></div>
      ${hero(target, !future.length && unconfirmed.length)}
      ${unconfirmed.length && future.length ? `<aside class="nx-suggestion"><span class="nx-spark" aria-hidden="true">↺</span><div><h3>${unconfirmed.length} earlier handoff${unconfirmed.length > 1 ? 's' : ''} to confirm</h3><p>${escape(kidLabel(unconfirmed[0]))} · ${escape(shortTitle(unconfirmed[0].title))}, ${formatTime(unconfirmed[0].time)}.</p><button data-nx-action="details" data-id="${unconfirmed[0].id}">Check status</button></div></aside>` : ''}
      <div class="nx-section-title"><h2>${view.offset ? 'The day ahead' : 'The rest of the day'}</h2><span>${pending.length} remaining</span></div>
      <div class="nx-kids" aria-label="Filter by child">${['All','Soni','Maya','Noah'].map(k => `<button class="nx-filter" data-nx-action="kid" data-value="${k}" aria-pressed="${view.kid === k}">${k === 'All' ? 'All children' : k}</button>`).join('')}</div>
      <ol class="nx-agenda">${entries.length ? entries.map(e => stop(e,target)).join('') : '<li class="nx-empty">Nothing else in this view. Check another day or caregiver.</li>'}</ol>
      ${completed.length ? `<button class="nx-text-btn" data-nx-action="completed">${view.showDone ? 'Hide' : 'Show'} ${completed.length} completed</button>` : ''}
      <button class="nx-add" data-nx-action="add">+ Add an appointment</button>
      ${suggestion(plan,drivers)}
      <div class="nx-section-title" id="nxCrewHeading"><h2>Who’s got what?</h2><button class="nx-text-btn" data-nx-action="user" data-value="All">View everyone</button></div>
      <div class="nx-crew-grid">${crew.map(name => {
        const tasks = plan.filter(e => e.lead === name);
        const next = tasks.find(e => !e.done && (view.offset || now() < timeToMinutes(e.time)));
        const total = Object.values(drivers).reduce((n,d) => n+d.driveMinutes,0);
        return `<button class="nx-person" data-nx-action="user" data-value="${name}" aria-pressed="${state.currentUser === name}"><div class="nx-person-head">${badge(name)}${name}<span aria-hidden="true" style="margin-left:auto">↗</span></div><p>${tasks.length} handoff${tasks.length !== 1 ? 's' : ''} · ${drivers[name]?.driveMinutes || 0} min driving</p><span class="nx-person-next">${next ? `${formatTime(next.time)} · ${escape(kidLabel(next))}` : tasks.some(e => !e.done) ? 'Earlier handoff to confirm' : 'No upcoming handoffs'}</span><div class="nx-load"><i style="width:${total ? (drivers[name]?.driveMinutes || 0)/total*100 : 0}%"></i></div></button>`;
      }).join('')}</div>
      <div class="nx-preview"><div class="nx-preview-head"><span>CONCEPT 03 · DESIGN PREVIEW</span><span>${view.time ? `${formatTime(view.time)} sample clock` : 'Live clock'}</span></div><div class="nx-preview-controls" aria-label="Preview clock">${[['14:40','2:40 PM'],['15:00','3:00 PM'],['15:15','3:15 PM'],[null,'Live']].map(([value,label]) => `<button data-nx-action="clock" data-value="${value || ''}" aria-pressed="${view.time === value}">${label}</button>`).join('')}</div></div>`;
    if (root._nextHtml === html) return;
    root._nextHtml = html;
    root.innerHTML = html;
    root.querySelectorAll('button').forEach(el => el.dataset.nxKey = [el.dataset.nxAction, el.dataset.value, el.dataset.id].join(':'));
    if (focusKey) [...root.querySelectorAll('button')].find(el => el.dataset.nxKey === focusKey)?.focus({preventScroll:true});
  };

  let returnFocus;
  function closeSheet() {
    document.getElementById('nxSheet')?.remove();
    returnFocus?.focus({preventScroll:true});
  }
  function showDetails(id) {
    const event = calculateDayPlan(eventDayOf(id)).plan.find(e => e.id === id);
    if (!event) return;
    closeSheet();
    returnFocus = document.activeElement;
    const shell = document.createElement('div');
    shell.id = 'nxSheet'; shell.className = 'nx-sheet-backdrop';
    shell.innerHTML = `<section class="next-sheet" role="dialog" aria-modal="true" aria-labelledby="nxSheetTitle"><div class="nx-sheet-head"><div><div class="nx-eyebrow">${escape(kidLabel(event))} · ${dayNames[eventDayOf(id)]}</div><h2 id="nxSheetTitle">${escape(event.title)}</h2></div><button class="nx-sheet-close" aria-label="Close trip details">×</button></div><div class="nx-sheet-info"><p><strong>${escape(event.location)}</strong></p><p>${formatTime(event.time)} – ${formatTime(event.endTime)}</p><p>${isTravel(event) ? `Leave ${escape(event.origin)} at <strong>${time(depart(event))}</strong>.<br>${event.eta} min estimated travel, plus ${Math.max(0,timeToMinutes(event.time)-depart(event)-event.eta)} min buffer.` : 'No travel needed.'}</p><p>${event.lead === 'TBD' ? 'A caregiver still needs to be assigned.' : `${escape(event.lead)} is assigned.`}</p>${event.conflict ? `<p style="color:#9a482c">Schedule overlap: ${escape(event.conflict)}</p>` : ''}<small>Design preview. Travel times are sample estimates.</small></div><div class="nx-sheet-actions"><button data-sheet-action="done">${event.done ? 'Reopen handoff' : 'Mark handoff complete'}</button><button data-sheet-action="edit">Edit appointment</button><button data-sheet-action="assign">Compare / change caregiver</button></div></section>`;
    document.querySelector('.app').append(shell);
    shell.querySelector('.nx-sheet-close').onclick = closeSheet;
    shell.onclick = e => { if(e.target === shell) closeSheet(); };
    shell.onkeydown = e => {
      if(e.key === 'Escape') closeSheet();
      if(e.key === 'Tab') {
        const buttons = [...shell.querySelectorAll('button')], first = buttons[0], last = buttons[buttons.length-1];
        if(e.shiftKey && document.activeElement === first) {e.preventDefault();last.focus();}
        else if(!e.shiftKey && document.activeElement === last) {e.preventDefault();first.focus();}
      }
    };
    shell.querySelectorAll('[data-sheet-action]').forEach(button => button.onclick = () => {
      const action = button.dataset.sheetAction;
      closeSheet();
      if(action === 'edit') editEvent(id);
      if(action === 'assign') openDriverAssignModal(id);
      if(action === 'done') {
        const record = state.eventsByDay[eventDayOf(id)].find(e => e.id === id);
        record.done = !record.done;
        saveState(); renderAll(); toast(record.done ? 'Handoff completed. Next up is ready.' : 'Handoff reopened.');
      }
    });
    shell.querySelector('.nx-sheet-close').focus();
  }

  document.getElementById('nextScreen').addEventListener('click', e => {
    const button = e.target.closest('[data-nx-action]');
    if(!button) return;
    const { nxAction: action, value, id } = button.dataset;
    if(action === 'details') return showDetails(Number(id));
    if(action === 'edit') return editEvent(Number(id));
    if(action === 'assign') return openDriverAssignModal(Number(id));
    if(action === 'crew') return document.getElementById('nxCrewHeading').scrollIntoView({behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth', block:'start'});
    if(action === 'add') { resetActivityForm(); setModalDay(day()); return openModal('activity'); }
    if(action === 'day') view.offset = Number(value);
    if(action === 'kid') view.kid = value;
    if(action === 'clock') { view.time = value || null; view.offset = 0; }
    if(action === 'completed') view.showDone = !view.showDone;
    if(action === 'user') { state.currentUser = value; view.kid = 'All'; saveState(); renderAll(); document.querySelector('.content').scrollTop = 0; return; }
    renderNextConcept();
    if(action === 'clock') document.querySelector('.content').scrollTop = 0;
  });
  renderNextConcept();
  if(location.hash === '#next') go('next');
})();
