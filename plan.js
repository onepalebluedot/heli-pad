/* Weekly planning presentation + local lab adapters. No network sync is simulated as real. */
(() => {
  'use strict';
  const C=PlanCore, KEY='heli-pad-plan-v1';
  let saved;
  try { saved=JSON.parse(localStorage.getItem(KEY)||'null'); } catch { saved=null; }
  const store={future:[],priorities:{},reviewed:{},calendar:{exports:{},pulled:[],lastReview:null},...saved};
  const view={week:C.BASE_WEEK,day:C.BASE_WEEK,panel:'schedule',filter:'all',reviewFilter:'all',calendarDirection:'pull'};
  const colors={Mom:'#e7ddc9',Dad:'#dce7d4',Nani:'#eadce5',Grandma:'#dde6ea',Family:'#eae7c5',TBD:'#f0dcc6'};
  const charts={Mom:'#bda170',Dad:'#7fa375',Nani:'#bc86a5',Grandma:'#7f9fad'};
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const fmt=date=>new Date(date+'T12:00:00').toLocaleDateString('en-US',{month:'short',day:'numeric'});
  const weekday=date=>new Date(date+'T12:00:00').toLocaleDateString('en-US',{weekday:'long'});
  const shortDay=date=>weekday(date).slice(0,3);
  const clock=t=>formatTime(t);
  const range=week=>`${fmt(week)} – ${fmt(C.dateAdd(week,6))}`;
  const iconPaths={
    left:'<path d="m14 6-6 6 6 6"/>',right:'<path d="m10 6 6 6-6 6"/>',down:'<path d="m6 9 6 6 6-6"/>',close:'<path d="m6 6 12 12M6 18 18 6"/>',
    calendar:'<rect x="4" y="5" width="16" height="16" rx="3"/><path d="M8 3v4m8-4v4M4 11h16m-11 4h2m3 0h2m-7 3h2"/>',
    heart:'<path d="M20.5 5.5a5 5 0 0 0-7 0L12 7l-1.5-1.5a5 5 0 0 0-7 7L12 21l8.5-8.5a5 5 0 0 0 0-7Z"/>',
    list:'<path d="M9 6h12M9 12h12M9 18h12"/><circle cx="3" cy="6" r="1"/><circle cx="3" cy="12" r="1"/><circle cx="3" cy="18" r="1"/>',
    load:'<path d="M4 5h16M4 10h10M4 15h13M4 20h6"/>',spark:'<path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5L12 3Z"/>',
    arrow:'<path d="M5 12h14m-6-6 6 6-6 6"/>',check:'<path d="m5 12 4 4L19 6"/>',plus:'<path d="M12 5v14M5 12h14"/>',
    pull:'<path d="M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5"/>',push:'<path d="M12 16V4m-5 5 5-5 5 5M4 16v5h16v-5"/>',
    swap:'<path d="M3 7h17m-4-4 4 4-4 4M21 17H4m4-4-4 4 4 4"/>',leaf:'<path d="M20 3C8 2 2 8 5 15c4 8 16 4 15-12ZM3 22 15 10"/>',
    flag:'<path d="M5 22V3m0 1c5-4 9 4 15 0v10c-6 4-10-4-15 0"/>',clock:'<circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 2"/>'
  };
  const icon=name=>`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${iconPaths[name]||iconPaths.calendar}</svg>`;
  const btn=(label,action,cls='pn-primary',attrs='')=>`<button class="${cls}" data-pn="${action}" ${attrs}>${label}</button>`;
  const avatar=name=>`<span class="pn-avatar ${C.unassigned({owner:name})?'missing':''}" style="--person:${colors[name]||colors.TBD}" aria-hidden="true">${name==='Family'?'All':C.unassigned({owner:name})?'?':esc(name[0])}</span>`;
  const getOptions=()=>({routes:routeMatrix,origins:state.parentLocations,buffer:state.buffer,priorities:store.priorities});
  function records() {
    const base=Object.entries(state.eventsByDay).flatMap(([d,list])=>list.map(e=>({...e,date:C.dateAdd(C.BASE_WEEK,Number(d))})));
    return [...base,...store.future].sort((a,b)=>a.date.localeCompare(b.date)||a.time.localeCompare(b.time));
  }
  const weekRecords=()=>records().filter(e=>e.date>=view.week&&e.date<=C.dateAdd(view.week,6));
  const find=id=>records().find(e=>String(e.id)===String(id));
  const save=()=>localStorage.setItem(KEY,JSON.stringify(store));
  function replaceAll(list) {
    state.eventsByDay=Object.fromEntries(Array.from({length:7},(_,d)=>[d,[]]));
    store.future=[];
    for(const e of list) {
      const d=C.daysBetween(C.BASE_WEEK,e.date);
      if(d>=0&&d<7) state.eventsByDay[d].push({...e}); else store.future.push({...e});
    }
    saveState();save();renderAll();
  }
  function patch(id,fields) { replaceAll(records().map(e=>String(e.id)===String(id)?{...e,...fields}:e)); }
  const fingerprint=()=>JSON.stringify(weekRecords().map(e=>[e.id,C.signature(e),e.owner,e.tentative,e.locked]))+JSON.stringify(store.priorities[view.week]||{})+state.buffer;
  const reviewed=()=>store.reviewed[view.week]===fingerprint();
  function changeWeek(delta) { view.week=C.dateAdd(view.week,delta*7);view.day=view.week;view.filter='all';render(); }
  function loadChart(load) {
    const max=Math.max(1,...Object.values(load));
    return C.CREW.map(name=>`<div class="pn-load-row"><span class="pn-load-name">${avatar(name)}${name}</span><div class="pn-track"><i style="width:${load[name]/max*100}%;--person:${charts[name]}"></i></div><strong>${load[name]}<small> min</small></strong></div>`).join('');
  }
  function eventRow(e) {
    const status=e.risks[0]?.label;
    return `<div class="pn-row"><div class="pn-row-time">${clock(e.time).replace(' ','<br><small>')}</small></div><span class="pn-marker ${e.status}" aria-hidden="true"></span><button class="pn-event" data-pn="event" data-id="${esc(e.id)}"><strong>${esc(e.title)}</strong><small>${esc((e.kids||[e.kid||'All']).join(' · '))} · ${esc(e.location)}</small>${status?`<small class="pn-warning">${esc(status)}</small>`:''}${e.seriesId?'<small>↻ Weekly · this occurrence</small>':''}</button><button class="pn-person" data-pn="assign" data-id="${esc(e.id)}" aria-label="${esc(e.title)}: ${C.unassigned(e)?'assign caregiver':'change '+e.owner}">${avatar(e.owner)}<span>${C.unassigned(e)?'Needs driver':esc(e.owner)}${e.tentative?' ?':''}</span></button></div>`;
  }
  function render() {
    const root=document.getElementById('planScreen');if(!root)return;
    const stats=C.summary(weekRecords(),getOptions()), goal=store.priorities[view.week];
    const days=Array.from({length:7},(_,d)=>C.dateAdd(view.week,d));
    const max=Math.max(4,...days.map(date=>stats.list.filter(e=>e.date===date).length));
    const dayList=stats.list.filter(e=>e.date===view.day && (view.filter==='all'||e.owner===view.filter));
    const heading=stats.total===0?'A little room to plan.':stats.ready===stats.total?'Your week is covered.':'Let’s line up the week.';
    const outgoing=records().filter(e=>e.gcal && store.calendar.exports[e.id]!==C.signature(e)).length;
    const html=`<header class="pn-head"><div><div class="pn-eyebrow">The family week</div><h1>${range(view.week)}</h1></div><div class="pn-icon-group">${btn(icon('left'),'prev','pn-icon','aria-label="Previous week"')}${btn(icon('calendar'),'jump','pn-icon','aria-label="Choose a week"')}${btn(icon('right'),'next','pn-icon','aria-label="Next week"')}</div></header>
      <section class="pn-hero" aria-label="Week readiness"><div class="pn-hero-top"><div><div class="pn-eyebrow">${reviewed()?'Review saved':'Make room for the week'}</div><h2>${heading}</h2></div><div class="pn-fraction"><strong>${stats.ready}<small> / ${stats.total}</small></strong>ready</div></div>
      <div class="pn-week-graph" aria-label="Daily readiness">${days.map(date=>{const list=stats.list.filter(e=>e.date===date);return `<button class="pn-day" data-pn="day" data-date="${date}" aria-pressed="${view.day===date}" aria-label="${weekday(date)}, ${list.length} ${list.length===1?'event':'events'}, ${list.filter(e=>e.status!=='ready').length} to review"><span class="pn-bars">${list.length?list.map(e=>`<i class="pn-bar ${e.status}" style="height:${(68-3*(max-1))/max}px"></i>`).join(''):'<i class="pn-bar empty"></i>'}</span><span class="pn-day-label">${shortDay(date)}</span><span class="pn-day-number">${Number(date.slice(-2))}</span></button>`}).join('')}</div>
      <div class="pn-legend"><span><i class="pn-dot"></i>Ready</span><span><i class="pn-dot review"></i>Review</span><span><i class="pn-dot missing"></i>Needs driver</span></div>
      ${btn(`<span>${stats.missing?`<span class="pn-action-count">${stats.missing} unassigned</span> · `:''}${stats.review?`${stats.review} to review`:'Review the week'}</span>${icon('arrow')}`,'review','pn-hero-action')}</section>
      <div class="pn-tools">${btn(`${icon('calendar')}<span><strong>Google Calendar</strong><small>${outgoing?`${outgoing} queued · Preview`:'Pull & push · Preview'}</small></span>`,'calendar','pn-tool')}${btn(`${icon('heart')}<span><strong>Make room for</strong><small>${goal?.enabled?`${goal.days.length} family dinners`:goal?.goal?esc(goal.goal).slice(0,24):'Dinner, meals & priorities'}</small></span>`,'goals','pn-tool')}</div>
      <section class="pn-panel"><div class="pn-panel-head"><h2>${view.panel==='load'?'Share the driving':weekday(view.day)}</h2><div class="pn-toggle" aria-label="Plan view">${btn(icon('list'),'schedule','',`aria-label="Schedule view" aria-pressed="${view.panel==='schedule'}"`)}${btn(icon('load'),'load','',`aria-label="Driving load view" aria-pressed="${view.panel==='load'}"`)}</div></div>
      ${view.panel==='schedule'?`${btn(`${view.filter==='all'?'Everyone':esc(view.filter)} · ${dayList.length} ${dayList.length===1?'event':'events'} ${icon('down')}`,'filter','pn-filter')}<div>${dayList.length?dayList.map(eventRow).join(''):`<div class="pn-empty">${icon('leaf')}<strong>A little breathing room.</strong>No events in this view.</div>`}</div>${btn(`${icon('plus')} Add an event`,'add','pn-add')}`:`<p class="pn-muted">Estimated driving for the whole week.</p>${loadChart(C.loads(weekRecords(),getOptions()))}${btn(`${icon('spark')} Review a rebalance`,'rebalance','pn-add')}<p class="pn-muted">Compare each change before applying it.</p>`}</section><p class="pn-footnote">Sample schedule · ${new Date(view.week+'T12:00:00').getFullYear()} · travel estimates</p>`;
    if(root._html===html)return;
    const focus=document.activeElement, key=root.contains(focus)?[focus.dataset.pn,focus.dataset.id,focus.dataset.date].join('|'):null;
    root.innerHTML=html;root._html=html;
    if(key) [...root.querySelectorAll('button')].find(b=>[b.dataset.pn,b.dataset.id,b.dataset.date].join('|')===key)?.focus({preventScroll:true});
  }
  let sheet=null, backStack=[],returnFocus=null;
  function closeSheet() {
    document.getElementById('pnBackdrop')?.remove();
    document.querySelector('.topbar').inert=false;document.querySelector('.content').inert=false;document.querySelector('.bottom-nav').inert=false;
    sheet=null;backStack=[];
    if(returnFocus?.isConnected)returnFocus.focus({preventScroll:true});else document.querySelector('#planScreen button')?.focus({preventScroll:true});
  }
  function openSheet(kind,data={},push=false) {
    if(push&&sheet)backStack.push(sheet); else if(!push)backStack=[];
    if(!sheet)returnFocus=document.activeElement;
    sheet={kind,data};paintSheet();
  }
  function goBack() { if(backStack.length){sheet=backStack.pop();paintSheet();}else closeSheet(); }
  function sheetContent() {
    const {kind,data}=sheet;
    if(kind==='review')return reviewSheet();
    if(kind==='rules')return {title:'A little breathing room',body:`<p class="pn-muted">Leave this many minutes before the arrival deadline, in addition to estimated travel. This buffer is shared with Go.</p><label class="pn-field"><span>Travel buffer · minutes</span><input class="pn-input" type="number" min="0" max="30" name="buffer" value="${state.buffer}"></label>`,foot:btn('Save buffer','rules-save')};
    if(kind==='assign')return assignmentSheet(data);
    if(kind==='rebalance')return rebalanceSheet(data);
    if(kind==='event')return eventSheet(data);
    if(kind==='goals')return goalsSheet();
    if(kind==='calendar')return calendarSheet();
    if(kind==='calendar-result')return {title:'Preview complete',body:`<div class="pn-empty"><div class="pn-success">${icon('check')}</div><strong>${data.count} ${data.direction==='pull'?'sample events pulled':'events reviewed for push'}</strong>${data.direction==='pull'?'New events are flagged until you choose a caregiver.':'Schedule details were recorded in the local preview.'}</div><p class="pn-note">Google Calendar is not connected. No changes were sent to Google.</p>`,foot:btn('Back to calendar','calendar')};
    if(kind==='reviewed')return {title:'Week reviewed',body:`<div class="pn-empty"><div class="pn-success">${icon('check')}</div><strong>A plan you can come back to.</strong>${data.remaining?`${data.remaining} flagged ${data.remaining===1?'event remains':'events remain'} visible. Review saved does not mean every event is ready.`:'All events have a caregiver and no detected planning risks.'}</div>`,foot:btn('Back to the week','close')};
    if(kind==='filter')return {title:'Whose schedule?',body:`<p class="pn-muted">Plan is a family overview. This filter leaves your Go profile unchanged.</p><div class="pn-pills">${['all',...C.CREW,'Family','TBD'].map(n=>btn(n==='all'?'Everyone':n==='TBD'?'Unassigned':n,'set-filter','pn-pill',`data-value="${n}" aria-pressed="${view.filter===n}"`)).join('')}</div>`};
    if(kind==='jump')return {title:'Look ahead',body:`<p class="pn-muted">Choose any date to open its week.</p><label class="pn-field"><span>Date</span><input class="pn-input" name="jumpDate" type="date" value="${view.week}" required></label>${btn('Back to the sample week','base-week','pn-text')}`,foot:btn('Open week','jump-save')};
    if(kind==='delete')return {title:'Remove this event?',body:`<p class="pn-note">${esc(find(data.id)?.title)} will be removed from this date only. Other occurrences stay in the plan.</p>`,foot:btn('Remove this occurrence','delete-confirm','pn-primary',`data-id="${esc(data.id)}"`)+btn('Keep it','back','pn-secondary')};
  }
  function paintSheet() {
    const content=sheetContent();
    let backdrop=document.getElementById('pnBackdrop');
    if(!backdrop){backdrop=document.createElement('div');backdrop.id='pnBackdrop';backdrop.className='pn-backdrop';document.querySelector('.app').append(backdrop);}
    backdrop.innerHTML=`<section class="pn-sheet" role="dialog" aria-modal="true" aria-labelledby="pnSheetTitle"><div class="pn-grip" aria-hidden="true"></div><header class="pn-sheet-head"><div><div class="pn-eyebrow">${content.eyebrow||'Weekly planning'}</div><h2 id="pnSheetTitle" tabindex="-1">${content.title}</h2></div>${btn(icon('close'),'close','pn-icon','aria-label="Close planning details"')}</header><div class="pn-sheet-body">${backStack.length?btn(`${icon('left')} Back`,'back','pn-text'):''}${content.body}</div>${content.foot?`<footer class="pn-sheet-foot">${content.foot}<p class="pn-form-error" id="pnError" role="alert" hidden></p></footer>`:''}</section>`;
    document.querySelector('.topbar').inert=true;document.querySelector('.content').inert=true;document.querySelector('.bottom-nav').inert=true;
    backdrop.onclick=e=>{if(e.target===backdrop)closeSheet();};
    backdrop.onkeydown=e=>{
      if(e.key==='Escape'){e.preventDefault();goBack();return;}
      if(e.key!=='Tab')return;
      const els=[...backdrop.querySelectorAll('button:not(:disabled),input,select,textarea,summary')].filter(x=>x.getClientRects().length),first=els[0],last=els.at(-1);
      if(e.shiftKey&&(document.activeElement===first||document.activeElement.id==='pnSheetTitle')){e.preventDefault();last?.focus();}
      else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus();}
    };
    backdrop.querySelector('#pnSheetTitle').focus({preventScroll:true});
  }
  function reviewSheet() {
    const stats=C.summary(weekRecords(),getOptions()),issues=stats.list.filter(e=>e.status!=='ready');
    const items=issues.filter(e=>view.reviewFilter==='all'||e.risks.some(r=>r.type===view.reviewFilter));
    return {title:'A few things to line up',eyebrow:range(view.week),body:`<p class="pn-muted">${stats.ready} of ${stats.total} ready. Ready means assigned, confirmed, and no detected timing or route risks.</p><div class="pn-pills">${[['all',`All · ${issues.length}`],['driver',`Unassigned · ${stats.missing}`],['overlap','Overlaps'],['tentative','Tentative']].map(([id,label])=>btn(label,'review-filter','pn-pill',`data-value="${id}" aria-pressed="${view.reviewFilter===id}"`)).join('')}</div>${items.length?items.map(e=>`<article class="pn-review-item"><small>${shortDay(e.date)} · ${clock(e.time)} · ${esc(e.owner)}</small><h3>${esc(e.title)}</h3><p>${e.risks.map(r=>esc(r.label)).join(' · ')}</p>${btn('Review caregiver ↗','assign','pn-text',`data-id="${esc(e.id)}"`)} ${btn('Edit event','event','pn-text',`data-id="${esc(e.id)}"`)}</article>`).join(''):`<div class="pn-empty">${icon('check')}<strong>Nothing flagged here.</strong>Try another filter or finish your review.</div>`}${btn(`${icon('spark')} Review rebalancing suggestions`,'rebalance','pn-add')}${btn(`${state.buffer} min travel buffer`,'rules','pn-text')}<p class="pn-muted">Suggestions use sample routes and schedule rules. No AI service or live traffic is connected.</p>`,foot:btn(issues.length?'Save review · keep flags':'Mark week reviewed','review-save')};
  }
  function assignmentSheet(data) {
    const e=find(data.id); if(!e)return {title:'Event no longer available',body:'',foot:btn('Back to plan','close')};
    if(!data.owner)data.owner=e.owner;
    const all=records(),candidates=C.CREW.map(n=>C.candidate(e,n,all,getOptions()));
    const choice=candidates.find(c=>c.name===data.owner);
    return {title:'Who can take this one?',eyebrow:`${shortDay(e.date)} · ${clock(e.time)}`,body:`<p class="pn-note"><strong>${esc(e.title)}</strong><br>${esc(e.location)} · ${esc((e.kids||[e.kid||'All']).join(', '))}</p>${candidates.map(c=>`<button class="pn-candidate" data-pn="candidate" data-value="${c.name}" aria-pressed="${data.owner===c.name}">${avatar(c.name)}<span><strong>${c.name}</strong><small class="${c.conflict||c.unknown?'pn-warning':''}">${esc(c.reason)}</small></span>${data.owner===c.name?icon('check'):''}</button>`).join('')}${btn('Leave unassigned','candidate','pn-pill',`data-value="TBD" aria-pressed="${data.owner==='TBD'}"`)}<label class="pn-check-label"><input type="checkbox" name="tentative" ${data.tentative??e.tentative?'checked':''}>Tentative · keep a flag until confirmed</label><label class="pn-check-label"><input type="checkbox" name="locked" ${data.locked??e.locked?'checked':''}>Keep this assignment when rebalancing</label>${choice?.conflict?'<p class="pn-note">This caregiver has a schedule conflict. You can save a tentative assignment, but the risk stays flagged.</p>':''}<p class="pn-muted">Travel is estimated from sample routes. Caregiver availability is based on the events in this plan.</p>`,foot:btn(data.owner==='TBD'?'Keep unassigned':`Save ${data.owner}`,'assign-save')};
  }
  function rebalanceSheet(data) {
    if(!data.proposal)data.proposal=C.proposals(weekRecords(),getOptions());
    const p=data.proposal;
    return {title:'A lighter week',eyebrow:'Suggested rebalance',body:`<p class="pn-note">${p.changes.length?`${p.changes.length} proposed ${p.changes.length===1?'change':'changes'}. Confirmed locks, tentative assignments, and completed events stay in place.`:'No safer, shorter or more balanced assignments found. Your existing assignments stay in place.'}</p>${p.changes.map(c=>`<article class="pn-review-item"><small>${shortDay(c.date)} · ${clock(c.time)}</small><h3>${esc(c.title)}</h3><div class="pn-swap"><span class="pn-swap-person">${avatar(c.from)}${esc(c.from)}</span>${icon('arrow')}<span class="pn-swap-person">${avatar(c.to)}${c.to}</span></div><p>${c.reason} · ${c.eta} min estimated trip</p></article>`).join('')}<p class="pn-muted">The proposal is checked as a whole, including onward trips. Applying saves only caregiver assignments. These are schedule-based suggestions, not live AI or traffic predictions.</p>`,foot:p.changes.length?btn(`Apply ${p.changes.length} ${p.changes.length===1?'change':'changes'}`,'rebalance-apply')+btn('Keep current plan','back','pn-secondary'):btn('Back','back')};
  }
  function eventSheet(data) {
    const e=data.id?find(data.id):null;
    const d=data.draft||(data.draft=e?{...e,repeat:'none',count:1}:{title:'',date:view.day,time:'16:00',endTime:'17:00',owner:'TBD',kids:['Soni'],location:'Oak Ridge Elementary',mode:'Drive',repeat:'none',count:4,kind:'drive'});
    return {title:e?'Edit event':'Make a little plan',eyebrow:e?.seriesId?'Editing this occurrence only':'One event or a weekly rhythm',body:`<form id="pnEventForm"><label class="pn-field"><span>What</span><input class="pn-input" name="title" value="${esc(d.title)}" maxlength="100" placeholder="Soccer, school pickup, family dinner…" required></label>
      <label class="pn-field"><span>When</span><input class="pn-input" type="date" name="date" value="${d.date}" required></label><div class="pn-form-grid"><label class="pn-field"><span>Starts</span><input class="pn-input" type="time" name="time" value="${d.time}" required></label><label class="pn-field"><span>Ends</span><input class="pn-input" type="time" name="endTime" value="${d.endTime}" required></label></div>
      <label class="pn-field"><span>Where</span><input class="pn-input" name="location" value="${esc(d.location)}" list="pnPlaces" maxlength="100" required><datalist id="pnPlaces">${state.locations.map(p=>`<option value="${esc(p.name)}">`).join('')}</datalist></label>
      <div class="pn-form-grid"><label class="pn-field"><span>Caregiver</span><select class="pn-input" name="owner">${['TBD',...C.CREW,'Family'].map(n=>`<option value="${n}" ${d.owner===n?'selected':''}>${n==='TBD'?'Decide later':n}</option>`).join('')}</select></label><label class="pn-field"><span>Kind</span><select class="pn-input" name="kind">${[['drive','Drive'],['cook','Cook'],['lead','Lead / at home'],['placeholder','Placeholder']].map(([v,t])=>`<option value="${v}" ${(d.kind||(!C.needsTravel(d)?'lead':'drive'))===v?'selected':''}>${t}</option>`).join('')}</select></label></div>
      <details class="pn-disclosure"><summary>Children & details</summary><div class="pn-pills">${['Soni','Maya','Noah'].map(n=>`<label class="pn-check-label"><input type="checkbox" name="kids" value="${n}" ${(d.kids||[]).includes(n)||(d.kids||[]).includes('All')?'checked':''}>${n}</label>`).join('')}</div><label class="pn-field"><span>Notes</span><textarea class="pn-input" name="notes" rows="2" maxlength="500">${esc(d.notes||'')}</textarea></label><label class="pn-check-label"><input type="checkbox" name="tentative" ${d.tentative?'checked':''}>Caregiver is tentative</label><label class="pn-check-label"><input type="checkbox" name="locked" ${d.locked?'checked':''}>Keep assignment when rebalancing</label></details>
      ${!e?`<details class="pn-disclosure"><summary>Repeat this rhythm</summary><div class="pn-form-grid"><label class="pn-field"><span>Repeat</span><select class="pn-input" name="repeat"><option value="none">Does not repeat</option><option value="weekly">Every week</option></select></label><label class="pn-field"><span>Number of occurrences</span><input class="pn-input" type="number" min="1" max="52" name="count" value="4"></label></div><p class="pn-muted">Starts on the selected date. Each occurrence can be edited separately.</p></details>`:''}
      <label class="pn-check-label"><input type="checkbox" name="gcal" ${d.gcal?'checked':''}>Queue schedule for Google Calendar</label><p class="pn-muted">${e?.gcal?'Changes will be queued for another calendar review.':'Unassigned events stay visible in the weekly review.'}</p></form>`,foot:btn(e?'Save changes':'Add to the plan','event-save')+(e?btn('Remove this occurrence','delete','pn-danger',`data-id="${esc(e.id)}"`):'')};
  }
  function goalsSheet() {
    const p=store.priorities[view.week]||{enabled:false,days:[0,2,4],time:'18:30',goal:'',meals:''};
    return {title:'Make room for what matters',eyebrow:range(view.week),body:`<form id="pnGoalsForm"><label class="pn-check-label"><input type="checkbox" name="enabled" ${p.enabled?'checked':''}>Protect family dinner</label><p class="pn-muted">Flag travel or events that cross this 45-minute window.</p><div class="pn-goal-days">${dayAbbrs.map((d,i)=>`<label>${d.slice(0,1)}<input type="checkbox" name="days" value="${i}" aria-label="Dinner on ${dayNames[i]}" ${p.days.includes(i)?'checked':''}></label>`).join('')}</div><label class="pn-field"><span>Dinner starts</span><input class="pn-input" name="time" type="time" value="${p.time}"></label><label class="pn-field"><span>One priority for this week</span><input class="pn-input" name="goal" value="${esc(p.goal)}" placeholder="An evening walk together" maxlength="100"></label><label class="pn-field"><span>Meal ideas</span><textarea class="pn-input" name="meals" rows="3" maxlength="1000" placeholder="Monday: taco bowls\nWednesday: leftovers\nFriday: pizza together">${esc(p.meals)}</textarea></label><p class="pn-muted">Dinner protection flags conflicts; it does not move events or create calendar entries.</p></form>`,foot:btn('Save priorities','goals-save')};
  }
  function incoming() {
    // Explicit sample CalendarProvider. Stable external IDs make pulling idempotent.
    return [{id:990000001,calendarId:'sample:library',date:C.dateAdd(C.BASE_WEEK,2),title:'Library makers club',time:'16:00',endTime:'16:45',location:'Community Center',kids:['Maya'],kid:'Maya',mode:'Drive',kind:'drive'},
      {id:990000002,calendarId:'sample:conference',date:C.dateAdd(C.BASE_WEEK,4),title:'Teacher conference',time:'15:00',endTime:'15:30',location:'Oak Ridge Elementary',kids:['Soni'],kid:'Soni',mode:'Drive',kind:'drive'}];
  }
  function calendarSheet() {
    const pulling=view.calendarDirection==='pull';
    const items=pulling?incoming().filter(e=>!store.calendar.pulled.includes(e.calendarId)):records().filter(e=>e.gcal&&store.calendar.exports[e.id]!==C.signature(e));
    return {title:'Keep calendars in step',eyebrow:'Google Calendar · not connected',body:`<p class="pn-note">Try the pull and push review with sample events. Google Calendar is not connected; this preview changes only the local plan.</p><div class="pn-toggle pn-calendar-direction">${btn(`${icon('pull')} Pull into Plan`,'calendar-pull','',`aria-pressed="${pulling}"`)}${btn(`${icon('push')} Push to Calendar`,'calendar-push','',`aria-pressed="${!pulling}"`)}</div><p class="pn-muted">${pulling?'Review incoming schedule details. New events arrive unassigned; existing caregiver and completion details are preserved.':'Review titles, dates, times, and places. Caregiver, completion, and private notes stay in Heli-Pad.'}</p>${items.length?items.map(e=>`<label class="pn-check-label pn-review-item"><input type="checkbox" name="calendarSelection" value="${esc(e.id)}" checked><span><strong>${esc(e.title)}</strong><br><span class="pn-muted">${fmt(e.date)}, ${e.date.slice(0,4)} · ${clock(e.time)}–${clock(e.endTime)} · ${esc(e.location)}</span></span></label>`).join(''):`<div class="pn-empty">${icon('calendar')}<strong>${pulling?'Sample inbox is clear.':'Nothing queued.'}</strong>${pulling?'Both sample events are already in the plan.':'Tick “Queue schedule for Google Calendar” when adding or editing an event.'}</div>`}<p class="pn-muted">${store.calendar.lastReview?`Last preview review: ${new Date(store.calendar.lastReview).toLocaleString()}`:'No calendar review yet.'}</p>`,foot:items.length?btn(pulling?'Pull selected sample events':'Preview selected push','calendar-apply'):btn('Back to the week','close')};
  }
  function readForm(id) { return new FormData(document.getElementById(id)); }
  function formError(message) { const el=document.getElementById('pnError');if(el){el.hidden=false;el.textContent=message;} }
  function saveEvent() {
    const form=document.getElementById('pnEventForm');if(!form.reportValidity())return;
    const f=readForm('pnEventForm'),old=sheet.data.id?find(sheet.data.id):null;
    const fields={title:f.get('title').trim(),date:f.get('date'),time:f.get('time'),endTime:f.get('endTime'),location:f.get('location').trim(),owner:f.get('owner'),kind:f.get('kind'),kids:f.getAll('kids'),notes:f.get('notes')||'',tentative:f.has('tentative'),locked:f.has('locked'),gcal:f.has('gcal'),repeat:f.get('repeat')||'none',count:Number(f.get('count')||1)};
    if(!fields.location)return formError('Choose a location.');
    if(!fields.kids.length)fields.kids=['All'];fields.kid=fields.kids.join(', ');
    fields.mode=fields.kind==='drive'?'Drive':'Home';fields.color=ownerColor(fields.owner);
    try {
      const batch=C.occurrences(fields), seriesId=batch.length>1?`series-${crypto.randomUUID()}`:old?.seriesId;
      let nextId=Math.max(Date.now(),...records().map(e=>Number(e.id)||0))+1;
      const all=records().filter(e=>e.id!==old?.id);
      for(const e of batch){const {repeat,count,...record}=e;all.push({...old,...record,id:old?.id||nextId++,done:old?.done||false,...(seriesId?{seriesId}:{})});}
      view.week=C.monday(fields.date);view.day=fields.date;view.filter='all';
      replaceAll(all);closeSheet();toast(old?'Event updated':`${batch.length} ${batch.length===1?'event':'weekly events'} added`);
    } catch(err){formError(err.message);}
  }
  function handle(action,button) {
    const id=button.dataset.id,value=button.dataset.value;
    if(action==='prev')return changeWeek(-1);
    if(action==='next')return changeWeek(1);
    if(action==='day'){view.day=button.dataset.date;view.panel='schedule';render();return;}
    if(action==='schedule'||action==='load'){view.panel=action;render();return;}
    if(action==='close')return closeSheet();if(action==='back')return goBack();
    if(action==='review-filter'){view.reviewFilter=value;paintSheet();return;}
    if(action==='review'){view.reviewFilter='all';openSheet('review');return;}
    if(action==='review-save'){const stats=C.summary(weekRecords(),getOptions());store.reviewed[view.week]=fingerprint();save();render();openSheet('reviewed',{remaining:stats.total-stats.ready});return;}
    if(['calendar','goals','jump','filter'].includes(action)){openSheet(action);return;}
    if(action==='rules'){openSheet('rules',{},true);return;}
    if(action==='rules-save'){const n=Number(document.querySelector('[name=buffer]').value);if(!Number.isInteger(n)||n<0||n>30)return formError('Choose a buffer from 0 to 30 minutes.');state.buffer=n;saveState();renderAll();goBack();return;}
    if(action==='add'){openSheet('event');return;}
    if(action==='event'||action==='assign'||action==='delete'){openSheet(action,{id},Boolean(sheet));return;}
    if(action==='set-filter'){view.filter=value;closeSheet();render();return;}
    if(action==='base-week'){view.week=C.BASE_WEEK;view.day=view.week;closeSheet();render();return;}
    if(action==='jump-save'){const date=document.querySelector('[name=jumpDate]').value;if(!date)return formError('Choose a date.');view.week=C.monday(date);view.day=date;closeSheet();render();return;}
    if(action==='candidate'){
      sheet.data.tentative=document.querySelector('[name=tentative]').checked;sheet.data.locked=document.querySelector('[name=locked]').checked;sheet.data.owner=value;paintSheet();return;
    }
    if(action==='assign-save'){
      patch(sheet.data.id,{owner:sheet.data.owner,tentative:sheet.data.owner!=='TBD'&&document.querySelector('[name=tentative]').checked,locked:document.querySelector('[name=locked]').checked,color:ownerColor(sheet.data.owner)});goBack();toast('Assignment saved');return;
    }
    if(action==='rebalance'){openSheet('rebalance',{fingerprint:fingerprint()},Boolean(sheet));return;}
    if(action==='rebalance-apply'){
      if(sheet.data.fingerprint!==fingerprint()){sheet.data={fingerprint:fingerprint()};paintSheet();formError('The plan changed. Review the refreshed proposal.');return;}
      const changes=new Map(sheet.data.proposal.changes.map(c=>[c.id,c]));
      replaceAll(records().map(e=>changes.has(e.id)?{...e,owner:changes.get(e.id).to,tentative:false,color:ownerColor(changes.get(e.id).to)}:e));
      goBack();toast(`${changes.size} assignments updated`);return;
    }
    if(action==='event-save')return saveEvent();
    if(action==='delete-confirm'){replaceAll(records().filter(e=>String(e.id)!==String(id)));closeSheet();toast('Occurrence removed');return;}
    if(action==='goals-save'){
      const f=readForm('pnGoalsForm'),days=f.getAll('days').map(Number),time=f.get('time');
      if(f.has('enabled')&&(!days.length||!time))return formError('Choose dinner days and a start time.');
      store.priorities[view.week]={enabled:f.has('enabled'),days,time:time||'18:30',goal:f.get('goal').trim(),meals:f.get('meals').trim()};save();render();closeSheet();toast('Weekly priorities saved');return;
    }
    if(action==='calendar-pull'||action==='calendar-push'){view.calendarDirection=action==='calendar-pull'?'pull':'push';paintSheet();return;}
    if(action==='calendar-apply'){
      const selected=[...document.querySelectorAll('[name=calendarSelection]:checked')].map(i=>i.value);
      if(!selected.length)return formError('Choose at least one event to review.');
      if(view.calendarDirection==='pull'){
        const items=incoming().filter(e=>selected.includes(String(e.id)));
        store.calendar.pulled=[...new Set([...store.calendar.pulled,...items.map(e=>e.calendarId)])];
        replaceAll(C.pull(records(),items));view.week=C.BASE_WEEK;view.day=items[0].date;
      } else {
        for(const e of records().filter(e=>selected.includes(String(e.id))))store.calendar.exports[e.id]=C.signature(e);
      }
      store.calendar.lastReview=new Date().toISOString();save();render();openSheet('calendar-result',{count:selected.length,direction:view.calendarDirection});return;
    }
  }
  let suppressClickUntil=0;
  document.addEventListener('click',e=>{if(Date.now()<suppressClickUntil && e.target.closest('.pn-screen')){e.preventDefault();return;}const button=e.target.closest('[data-pn]');if(button)handle(button.dataset.pn,button);});
  // Gesture accelerators have visible arrow buttons and never commit edits.
  let swipe=null;
  document.addEventListener('pointerdown',e=>{if(e.target.closest('.pn-hero'))swipe={x:e.clientX,y:e.clientY};});
  document.addEventListener('pointerup',e=>{if(!swipe)return;const dx=e.clientX-swipe.x,dy=e.clientY-swipe.y;swipe=null;if(Math.abs(dx)>65&&Math.abs(dy)<35){e.preventDefault();suppressClickUntil=Date.now()+350;changeWeek(dx<0?1:-1);}});
  document.addEventListener('pointercancel',()=>{swipe=null;});
  window.renderPlanConcept=render;
  window.closePlanSheet=closeSheet;
  render();
  if(location.hash==='#plan')go('plan');
})();
