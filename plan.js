/* Weekly planning presentation + local lab adapters. No network sync is simulated as real. */
(() => {
  'use strict';
  const C=PlanCore, store=AppStore.plan;
  const view={week:C.BASE_WEEK,day:C.BASE_WEEK,scheduleOpen:false,filter:'all',reviewFilter:'all',calendarDirection:'pull'};
  const colors=new Proxy({}, {get:(_,name)=>goPersonBg(name)});
  const inks=new Proxy({}, {get:(_,name)=>goPersonText(name)});
  const charts=new Proxy({}, {get:(_,name)=>goPersonInk(name)});
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const fmt=date=>new Date(date+'T12:00:00').toLocaleDateString('en-US',{month:'short',day:'numeric'});
  const weekday=date=>new Date(date+'T12:00:00').toLocaleDateString('en-US',{weekday:'long'});
  const shortDay=date=>weekday(date).slice(0,3);
  const clock=t=>formatTime(t);
  const range=week=>`${fmt(week)} – ${fmt(C.dateAdd(week,6))}`;
  const iconNames={left:'chevron-left',right:'chevron-right',down:'chevron-down',up:'chevron-up',close:'x',calendar:'calendar-days',heart:'heart',list:'list',load:'chart-no-axes-column',spark:'sparkles',arrow:'arrow-right',check:'check',plus:'plus',pull:'download',push:'upload',swap:'arrow-left-right',leaf:'leaf',flag:'flag',clock:'clock-3',repeat:'repeat-2',user:'user-round',users:'users-round',car:'car-front',home:'house',alert:'triangle-alert'};
  const icon=name=>window.appIcon(iconNames[name]||'calendar-days');
  const btn=(label,action,cls='pn-primary',attrs='')=>`<button class="${cls}" data-pn="${action}" ${attrs}>${label}</button>`;
  const avatar=name=>`<span class="pn-avatar ${C.unassigned({owner:name})?'missing':''}" style="--person:${colors[name]||colors.TBD};--person-ink:${inks[name]||inks.TBD}" aria-hidden="true">${name==='Family'?'F':C.unassigned({owner:name})?'?':esc(name[0])}</span>`;
  const getOptions=()=>AppStore.planningOptions();
  const records=()=>AppStore.records();
  const weekRecords=()=>records().filter(e=>e.date>=view.week&&e.date<=C.dateAdd(view.week,6));
  const find=id=>records().find(e=>String(e.id)===String(id));
  const save=()=>AppStore.save();
  const replaceAll=list=>AppStore.replaceRecords(list);
  function patch(id,fields) { replaceAll(records().map(e=>String(e.id)===String(id)?{...e,...fields}:e)); }
  const fingerprint=()=>JSON.stringify(weekRecords().map(e=>[e.id,C.signature(e),e.owner,e.tentative,e.locked]))+JSON.stringify(store.priorities[view.week]||{})+JSON.stringify([state.people,state.parentLocations,state.locations,state.homePlaceName,state.buffer,state.trafficMode,state.dinnerProtection]);
  const reviewed=()=>store.reviewed[view.week]===fingerprint();
  function changeWeek(delta) { view.week=C.dateAdd(view.week,delta*7);view.day=view.week;view.filter='all';view.scheduleOpen=false;render(); }
  function loadChart(load) {
    const max=Math.max(1,...Object.values(load));
    return AppStore.caregivers().map(name=>`<div class="pn-load-row"><span class="pn-load-name">${avatar(name)}${esc(name)}</span><div class="pn-track"><i style="width:${load[name]/max*100}%;--person:${charts[name]}"></i></div><strong>${load[name]}<small> min</small></strong></div>`).join('');
  }
  const kidsOf=e=>(Array.isArray(e.kids)?e.kids:[e.kid].filter(Boolean)).map(k=>k==='All'?'All kids':k);
  const routineKey=e=>e.seriesId?`series:${e.seriesId}`:`pattern:${e.title.trim().toLowerCase()}|${e.location.trim().toLowerCase()}|${kidsOf(e).slice().sort().join(',').toLowerCase()}`;
  function routineGroups() {
    const groups=new Map();
    for(const e of weekRecords()){
      const key=routineKey(e), group=groups.get(key)||{key,title:e.title,location:e.location,kids:kidsOf(e),events:[]};
      group.events.push(e);groups.set(key,group);
    }
    return [...groups.values()].filter(g=>g.events.length>1).sort((a,b)=>b.events.length-a.events.length||a.title.localeCompare(b.title));
  }
  const routineFromValue=value=>routineGroups().find(g=>g.key===decodeURIComponent(value||''));
  const dayTags=events=>events.map(e=>`<span>${shortDay(e.date)}, ${fmt(e.date)}</span>`).join('');
  const kidsTag=e=>{const kids=kidsOf(e).join(', ');return `<span class="go-stop-kids">${icon(kids==='All kids'?'users':'user')} ${esc(kids)}</span>`;};
  function eventRow(e) {
    const status=e.risks[0]?.label, isTBD=C.unassigned(e), group=routineGroups().find(g=>g.key===routineKey(e));
    const dot=e.done?'done':isTBD?'tbd':e.status==='review'?'stale':'';
    const detail=status||group?`${status?esc(status):''}${status&&group?' · ':''}${group?`Repeats ${group.events.length} days`:''}`:'';
    return `<div class="go-stop ${e.done?'done':''} ${isTBD?'tbd alert':''}">
      <div class="go-stop-time ${window.isAllDay&&window.isAllDay(e)?'is-allday':''}">${window.isAllDay&&window.isAllDay(e)?'All day':clock(e.time)}</div>
      <button class="go-stop-marker" data-pn="assign" data-id="${esc(e.id)}" aria-label="${esc(e.title)}: ${isTBD?'assign caregiver':'change '+e.owner}">${isTBD?'':e.done?icon('check'):''}</button>
      <button class="go-stop-body pn-go-event" data-pn="event" data-id="${esc(e.id)}">
        <span class="go-stop-title"><span class="go-stop-dot ${dot}" aria-hidden="true"></span>${esc(e.title)}${isTBD?'<span class="go-stop-flag">Unassigned</span>':''}</span>
        <span class="go-stop-meta">${icon(C.needsTravel(e)?'car':'home')}<span class="go-stop-venue">${esc(e.location)}</span>${kidsTag(e)}</span>
        ${detail?`<span class="go-stop-leave">${detail}</span>`:''}
      </button>
      <button class="go-stop-lead pn-go-person" data-pn="assign" data-id="${esc(e.id)}" aria-label="${esc(e.title)}: ${isTBD?'assign caregiver':'change '+e.owner}">
        <span class="go-stop-driver ${isTBD?'tbd':''}" ${isTBD?'':`style="background:${colors[e.owner]||colors.TBD};color:${inks[e.owner]||inks.TBD};border-color:${inks[e.owner]||inks.TBD}55"`} aria-hidden="true">${isTBD?'?':e.owner==='Family'?'F':esc(e.owner[0])}</span>
        <span class="go-stop-lead-name ${isTBD?'tbd':''}">${isTBD?'Assign':esc(e.owner)}</span>
      </button>
    </div>`;
  }
  function periodRows(events) {
    return ['Morning','Afternoon'].map(label=>{
      const items=events.filter(e=>(C.mins(e.time)<720?'Morning':'Afternoon')===label);
      return items.length?`<section class="go-period" aria-labelledby="pn-${label.toLowerCase()}"><h3 class="go-period-heading" id="pn-${label.toLowerCase()}">${label}</h3><div class="go-period-events">${items.map(eventRow).join('')}</div></section>`:'';
    }).join('');
  }
  function decisionCard(e) {
    return `<article class="pn-decision-card ${C.unassigned(e)?'urgent':''}"><span class="pn-decision-icon">${icon(C.unassigned(e)?'alert':'flag')}</span><div><small>${shortDay(e.date)}, ${fmt(e.date)} · ${clock(e.time)}</small><h3>${esc(e.title)}</h3><p>${esc(kidsOf(e).join(', '))} · ${esc(e.location)}</p></div>${btn(C.unassigned(e)?'Assign':'Review','assign','pn-card-action',`data-id="${esc(e.id)}"`)}</article>`;
  }
  function routineCard(group) {
    const owners=[...new Set(group.events.map(e=>e.owner))], owner=owners.length===1?owners[0]:'Mixed';
    return `<article class="pn-routine-card"><div class="pn-routine-top"><span class="pn-routine-icon">${icon('repeat')}</span><div><small>${group.events.length} weekly handoffs</small><h3>${esc(group.title)}</h3></div>${owner==='Mixed'?'<span class="pn-mixed">Mixed</span>':avatar(owner)}</div><div class="pn-routine-tags">${dayTags(group.events)}</div><p>${esc(group.kids.join(', '))} · ${esc(group.location)}</p>${btn(`Set caregiver for all ${icon('arrow')}`,'routine','pn-routine-action',`data-value="${encodeURIComponent(group.key)}"`)}</article>`;
  }
  function templateButton(t) {
    const template=FamilyCore.normalize(t);
    return btn(`<strong>${esc(template.title)}</strong><small>${clock(template.time)} · ${esc(template.kids.join(', '))}</small>`,'use-template','pn-template-highlight',`data-id="${esc(template.id)}" aria-label="Use ${esc(template.title)}"`);
  }
  function templateHighlights() {
    const templates=state.templates||[];
    return `<section class="pn-template-section" aria-label="Schedule templates"><div class="pn-template-heading"><h2>Start with a shortcut</h2>${btn('All templates','templates','')}</div><div class="pn-template-strip">${templates.slice(0,4).map(templateButton).join('')||'<p class="pn-muted">Save a template in Family for your regular handoffs.</p>'}</div></section>`;
  }
  function useTemplate(id) {
    const template=state.templates.find(t=>String(t.id)===String(id));if(!template)return;
    go('plan');
    openSheet('event',{draft:FamilyCore.eventDraft(template,view.day)});
  }
  function render() {
    if(!['all','Family','TBD',...AppStore.caregivers()].includes(view.filter))view.filter='all';
    const root=document.getElementById('planScreen');if(!root)return;
    const stats=C.summary(weekRecords(),getOptions()), goal=store.priorities[view.week];
    const days=Array.from({length:7},(_,d)=>C.dateAdd(view.week,d));
    const dayList=stats.list.filter(e=>e.date===view.day && (view.filter==='all'||e.owner===view.filter));
    const issues=stats.list.filter(e=>e.status!=='ready'), routines=routineGroups();
    const outgoing=records().filter(e=>e.gcal && store.calendar.exports[e.id]!==C.signature(e)).length;
    const html=`<header class="pn-head"><div><div class="pn-eyebrow">7-day family plan</div><h1>${range(view.week)}</h1></div><div class="pn-icon-group">${btn(icon('left'),'prev','pn-icon','aria-label="Previous week"')}${btn(icon('calendar'),'jump','pn-icon','aria-label="Choose a week"')}${btn(icon('right'),'next','pn-icon','aria-label="Next week"')}</div></header>
      <section class="pn-command" aria-label="Weekly assignment desk"><div class="pn-command-copy"><div class="pn-eyebrow">Assignment desk</div><h2>Choose who handles what.</h2><p>Set recurring routines first, then clear the handoffs that still need a decision.</p></div><div class="pn-command-stats">${btn(`<strong>${stats.missing}</strong>unassigned`,'review','pn-stat','data-value="driver"')}${btn(`<strong>${issues.length}</strong>to review`,'review','pn-stat')}${btn(`<strong>${routines.length}</strong>routines`,'routines','pn-stat')}</div><div class="pn-command-actions">${btn(`${icon('check')} Review assignments`,'review','pn-command-primary')}</div></section>
      <section class="pn-actions"><div class="pn-section-head"><div><div class="pn-eyebrow">Act first</div><h2>${issues.length?'Needs a decision':'Assignments are covered'}</h2></div><span>${issues.length||'Done'}</span></div>${issues.length?`<div class="pn-decision-list">${issues.slice(0,2).map(decisionCard).join('')}</div>${issues.length>2?btn(`Review ${issues.length-2} more ${icon('arrow')}`,'review','pn-more-action'):''}`:`<div class="pn-covered">${icon('check')} Nothing is waiting for a caregiver.</div>`}
      <div class="pn-subsection-head"><div><span class="pn-routine-heading-icon">${icon('repeat')}</span><div><h3>Recurring handoffs</h3><p>One assignment can cover the whole rhythm.</p></div></div></div>${routines.length?`<div class="pn-routine-list">${routines.slice(0,3).map(routineCard).join('')}</div>`:`<div class="pn-covered">No repeated routines in this week yet.</div>`}</section>
      ${templateHighlights()}
      <section class="pn-week-select" aria-label="Choose a day"><div class="pn-section-head compact"><div><div class="pn-eyebrow">Open a day</div><h2>${weekday(view.day)}, ${fmt(view.day)}</h2></div><span>${dayList.length} ${dayList.length===1?'event':'events'}</span></div><div class="pn-day-strip">${days.map(date=>{const list=stats.list.filter(e=>e.date===date),open=list.filter(e=>e.status!=='ready').length;return `<button class="pn-day-chip" data-pn="day" data-date="${date}" aria-pressed="${view.day===date}" aria-label="${weekday(date)}, ${fmt(date)}, ${list.length} ${list.length===1?'event':'events'}, ${open} to review"><strong>${shortDay(date)}</strong><span>${Number(date.slice(-2))}</span><i class="${open?'review':''}"></i></button>`}).join('')}</div></section>
      <section class="pn-schedule"><button class="pn-schedule-toggle" data-pn="toggle-schedule" aria-expanded="${view.scheduleOpen}"><span><strong>${weekday(view.day)}, ${fmt(view.day)} schedule</strong><small>${dayList.length} ${dayList.length===1?'event':'events'} · ${view.scheduleOpen?'Hide the list':'Expand to view'}</small></span>${icon(view.scheduleOpen?'up':'down')}</button>${view.scheduleOpen?`<div class="pn-schedule-body">${btn(`${view.filter==='all'?'Everyone':esc(view.filter)} · ${dayList.length} ${dayList.length===1?'event':'events'} ${icon('down')}`,'filter','pn-filter')}<div class="go-rail">${dayList.length?periodRows(dayList):`<div class="pn-empty">${icon('leaf')}<strong>A little breathing room.</strong>No events in this view.</div>`}</div>${btn(`<span class="go-add-icon">${icon('plus')}</span><span>Add an event</span>`,'add','go-add')}</div>`:''}</section>
      <div class="pn-tools">${btn(`${icon('calendar')}<span><strong>Google Calendar</strong><small>${outgoing?`${outgoing} queued · Preview`:'Pull & push · Preview'}</small></span>`,'calendar','pn-tool')}${btn(`${icon('heart')}<span><strong>Make room for</strong><small>${goal?.enabled?`${goal.days.length} family dinners`:goal?.goal?esc(goal.goal).slice(0,24):'Dinner, meals & priorities'}</small></span>`,'goals','pn-tool')}</div><p class="pn-footnote">Sample schedule · ${new Date(view.week+'T12:00:00').getFullYear()} · travel estimates</p>`;
    if(root._html===html)return;
    const focus=document.activeElement, key=root.contains(focus)?[focus.dataset.pn,focus.dataset.id,focus.dataset.date].join('|'):null;
    root.innerHTML=html;root._html=html;window.refreshAppIcons?.(root);
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
    if(kind==='routines')return {title:'Recurring handoffs',eyebrow:range(view.week),body:routineGroups().length?`<div class="pn-routine-list">${routineGroups().map(routineCard).join('')}</div>`:'<p class="pn-muted">No repeated routines in this week yet.</p>'};
    if(kind==='rules')return {title:'A little breathing room',body:`<p class="pn-muted">Leave this many minutes before the arrival deadline, in addition to estimated travel. This buffer is shared with Go.</p><label class="pn-field"><span>Travel buffer · minutes</span><input class="pn-input" type="number" min="0" max="45" name="buffer" value="${state.buffer}"></label>`,foot:btn('Save buffer','rules-save')};
    if(kind==='assign')return assignmentSheet(data);
    if(kind==='routine')return routineSheet(data);
    if(kind==='event')return eventSheet(data);
    if(kind==='templates')return {title:'Your schedule shortcuts',eyebrow:'Saved in Family',body:`<p class="pn-muted">Choose a template, then confirm its date and details.</p><div class="pn-template-list">${state.templates.map(templateButton).join('')}</div>`,foot:btn('Manage in Family','manage-templates')};
    if(kind==='goals')return goalsSheet();
    if(kind==='calendar')return calendarSheet();
    if(kind==='calendar-result')return {title:'Preview complete',body:`<div class="pn-empty"><div class="pn-success">${icon('check')}</div><strong>${data.count} ${data.direction==='pull'?'sample events pulled':'events reviewed for push'}</strong>${data.direction==='pull'?'New events are flagged until you choose a caregiver.':'Schedule details were recorded in the local preview.'}</div><p class="pn-note">Google Calendar is not connected. No changes were sent to Google.</p>`,foot:btn('Back to calendar','calendar')};
    if(kind==='reviewed')return {title:'Week reviewed',body:`<div class="pn-empty"><div class="pn-success">${icon('check')}</div><strong>A plan you can come back to.</strong>${data.remaining?`${data.remaining} flagged ${data.remaining===1?'event remains':'events remain'} visible. Review saved does not mean every event is ready.`:'All events have a caregiver and no detected planning risks.'}</div>`,foot:btn('Back to the week','close')};
    if(kind==='filter')return {title:'Whose schedule?',body:`<p class="pn-muted">Plan is a family overview. This filter leaves your Go profile unchanged.</p><div class="pn-pills">${['all',...AppStore.caregivers(),'Family','TBD'].map(n=>btn(n==='all'?'Everyone':n==='TBD'?'Unassigned':n,'set-filter','pn-pill',`data-value="${esc(n)}" aria-pressed="${view.filter===n}"`)).join('')}</div>`};
    if(kind==='jump')return {title:'Look ahead',body:`<p class="pn-muted">Choose any date to open its week.</p><label class="pn-field"><span>Date</span><input class="pn-input" name="jumpDate" type="date" value="${view.week}" required></label>${btn('Back to the sample week','base-week','pn-text')}`,foot:btn('Open week','jump-save')};
    if(kind==='delete')return {title:'Remove this event?',body:`<p class="pn-note">${esc(find(data.id)?.title)} will be removed from this date only. Other occurrences stay in the plan.</p>`,foot:btn('Remove this occurrence','delete-confirm','pn-primary',`data-id="${esc(data.id)}"`)+btn('Keep it','back','pn-secondary')};
  }
  function paintSheet() {
    const content=sheetContent();
    let backdrop=document.getElementById('pnBackdrop');
    if(!backdrop){backdrop=document.createElement('div');backdrop.id='pnBackdrop';backdrop.className='pn-backdrop';document.querySelector('.app').append(backdrop);}
    backdrop.innerHTML=`<section class="pn-sheet go-sheet" role="dialog" aria-modal="true" aria-labelledby="pnSheetTitle"><div class="pn-grip go-sheet-grip" aria-hidden="true"></div><header class="pn-sheet-head go-sheet-head"><div><div class="pn-eyebrow go-sheet-eyebrow">${content.eyebrow||'Weekly planning'}</div><h2 id="pnSheetTitle" tabindex="-1">${content.title}</h2></div>${btn(icon('close'),'close','pn-icon go-sheet-close','aria-label="Close planning details"')}</header><div class="pn-sheet-body go-sheet-body">${backStack.length?btn(`${icon('left')} Back`,'back','pn-text'):''}${content.body}</div>${content.foot?`<footer class="pn-sheet-foot go-sheet-foot">${content.foot}<p class="pn-form-error" id="pnError" role="alert" hidden></p></footer>`:''}</section>`;
    window.refreshAppIcons?.();
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
    return {title:'A few things to line up',eyebrow:range(view.week),body:`<p class="pn-muted">${stats.ready} of ${stats.total} ready. Ready means assigned, confirmed, and no detected timing or route risks.</p><div class="pn-pills">${[['all',`All · ${issues.length}`],['driver',`Unassigned · ${stats.missing}`],['overlap','Overlaps'],['tentative','Tentative']].map(([id,label])=>btn(label,'review-filter','pn-pill',`data-value="${id}" aria-pressed="${view.reviewFilter===id}"`)).join('')}</div>${items.length?items.map(e=>`<article class="pn-review-item"><small>${shortDay(e.date)}, ${fmt(e.date)} · ${window.isAllDay && window.isAllDay(e) ? 'All day' : clock(e.time)} · ${esc(e.owner)}</small><h3>${esc(e.title)}</h3><p>${e.risks.map(r=>esc(r.label)).join(' · ')}</p>${btn('Review caregiver ↗','assign','pn-text',`data-id="${esc(e.id)}"`)} ${btn('Edit event','event','pn-text',`data-id="${esc(e.id)}"`)}</article>`).join(''):`<div class="pn-empty">${icon('check')}<strong>Nothing flagged here.</strong>Try another filter or finish your review.</div>`}${btn(`${state.buffer} min travel buffer`,'rules','pn-text')}<p class="pn-muted">Suggestions use sample routes and schedule rules. No AI service or live traffic is connected.</p>`,foot:btn(issues.length?'Save review · keep flags':'Mark week reviewed','review-save')};
  }
  function assignmentSheet(data) {
    const e=find(data.id); if(!e)return {title:'Event no longer available',body:'',foot:btn('Back to plan','close')};
    if(!data.owner)data.owner=e.owner;
    const all=records(),candidates=AppStore.caregivers().map(n=>C.candidate(e,n,all,getOptions()));
    const choice=candidates.find(c=>c.name===data.owner);
    return {title:'Who can take this one?',eyebrow:`${shortDay(e.date)}, ${fmt(e.date)} · ${window.isAllDay && window.isAllDay(e) ? 'All day' : clock(e.time)}`,body:`<p class="pn-note"><strong>${esc(e.title)}</strong><br>${esc(e.location)} · ${esc((e.kids||[e.kid||'All']).join(', '))}</p>${candidates.map(c=>`<button class="pn-candidate" data-pn="candidate" data-value="${c.name}" aria-pressed="${data.owner===c.name}">${avatar(c.name)}<span><strong>${c.name}</strong><small class="${c.conflict||c.unknown?'pn-warning':''}">${esc(c.reason)}</small></span>${data.owner===c.name?icon('check'):''}</button>`).join('')}${btn('Leave unassigned','candidate','pn-pill',`data-value="TBD" aria-pressed="${data.owner==='TBD'}"`)}<label class="pn-check-label"><input type="checkbox" name="tentative" ${data.tentative??e.tentative?'checked':''}>Tentative · keep a flag until confirmed</label><label class="pn-check-label"><input type="checkbox" name="locked" ${data.locked??e.locked?'checked':''}>Keep this assignment when rebalancing</label>${choice?.conflict?'<p class="pn-note">This caregiver has a schedule conflict. You can save a tentative assignment, but the risk stays flagged.</p>':''}<p class="pn-muted">Travel is estimated from sample routes. Caregiver availability is based on the events in this plan.</p>`,foot:btn(data.owner==='TBD'?'Keep unassigned':`Save ${data.owner}`,'assign-save')};
  }
  function routineSheet(data) {
    const group=routineFromValue(data.key);if(!group)return {title:'Routine no longer available',body:'',foot:btn('Back to plan','close','pn-primary go-btn primary')};
    const owners=[...new Set(group.events.map(e=>e.owner))];
    if(!data.owner)data.owner=owners.length===1?owners[0]:'TBD';
    const candidates=AppStore.caregivers().map(name=>{
      const checks=group.events.map(e=>C.candidate(e,name,records(),getOptions()));
      const conflicts=checks.filter(c=>c.conflict||c.unknown).length;
      return {name,conflicts,reason:conflicts?`${conflicts} ${conflicts===1?'occurrence needs':'occurrences need'} review`:`Available for all ${group.events.length} occurrences`};
    });
    return {title:'Assign the whole routine',eyebrow:`${group.events.length} recurring handoffs`,body:`<div class="pn-routine-summary"><span class="pn-routine-icon">${icon('repeat')}</span><div><h3>${esc(group.title)}</h3><p>${esc(group.kids.join(', '))} · ${esc(group.location)}</p><div class="pn-routine-tags">${dayTags(group.events)}</div></div></div><div class="go-sec-head"><label>Choose one caregiver</label><span>Applies to every day above</span></div>${candidates.map(c=>`<button class="pn-candidate" data-pn="routine-candidate" data-value="${c.name}" aria-pressed="${data.owner===c.name}">${avatar(c.name)}<span><strong>${c.name}</strong><small class="${c.conflicts?'pn-warning':''}">${c.reason}</small></span>${data.owner===c.name?icon('check'):''}</button>`).join('')}${btn('Leave the routine unassigned','routine-candidate','pn-pill',`data-value="TBD" aria-pressed="${data.owner==='TBD'}"`)}<label class="pn-check-label"><input type="checkbox" name="routineLocked" ${data.locked===false?'':'checked'}>Keep this routine assignment fixed</label><p class="pn-muted">This updates all ${group.events.length} occurrences in the current week together. You can still edit an individual occurrence later.</p>`,foot:btn(data.owner==='TBD'?'Keep routine unassigned':`Assign all ${group.events.length} to ${data.owner}`,'routine-save','pn-primary go-btn primary')};
  }
  function eventSheet(data) {
    const e=data.id?find(data.id):null;
    const d=data.draft||(data.draft=e?{...e,repeat:'none',count:1}:{title:'',date:view.day,time:'16:00',endTime:'17:00',owner:'TBD',kids:AppStore.children().slice(0,1),location:AppStore.home(),mode:'Drive',repeat:'none',count:4,kind:'drive'});
    const ownerCards=[...AppStore.caregivers(),'Family','TBD'].map(n=>`<label class="go-card ${n==='TBD'?'is-other':''}"><input class="pn-choice-input" type="radio" name="owner" value="${esc(n)}" ${d.owner===n?'checked':''}><i class="${n==='TBD'?'tbd':''}" ${n==='TBD'?'':`style="background:${colors[n]};color:${inks[n]}"`}>${n==='TBD'?'?':n==='Family'?'F':n[0]}</i><b>${n==='TBD'?'Decide later':esc(n)}</b></label>`).join('');
    const kidPills=AppStore.children().map(n=>`<label class="go-pill"><input class="pn-choice-input" type="checkbox" name="kids" value="${esc(n)}" ${(d.kids||[]).includes(n)||(d.kids||[]).includes('All')?'checked':''}>${icon('user')} ${esc(n)}</label>`).join('');
    return {title:e?'Edit this handoff':'Plan a handoff',eyebrow:e?'Edit selected dates':'Add to the week',body:`<form id="pnEventForm" class="pn-event-form"><section><div class="go-sec-head"><label>What is happening?</label><span>Keep it scannable</span></div><input class="go-field" aria-label="Event title" name="title" value="${esc(d.title)}" maxlength="100" placeholder="Soccer, school pickup, family dinner…" required></section>
      <section><div class="go-sec-head"><label>When & where</label><span>${weekday(d.date)}, ${fmt(d.date)}</span></div><div class="go-panel"><label class="go-row"><span class="go-mini">Date</span><input class="go-field" type="date" name="date" value="${d.date}" required></label><fieldset class="pn-repeat-days"><legend>Days this week</legend>${Array.from({length:7},(_,i)=>{const date=C.dateAdd(C.monday(d.date),i);return `<label><input type="checkbox" name="weekdays" value="${i}" ${(d.weekdays||[C.daysBetween(C.monday(d.date),d.date)]).includes(i)?'checked':''}><strong>${shortDay(date)}</strong><span data-repeat-date="${i}">${fmt(date)}</span></label>`;}).join('')}</fieldset><p class="pn-muted">Choose one or more dates in this week.${e?' Saving updates this event and adds or updates the selected dates; other dates stay unchanged.':''}</p><div class="go-two"><label><span class="go-mini">Starts</span><input class="go-field" type="time" name="time" value="${d.time}" required></label><label><span class="go-mini">Ends</span><input class="go-field" type="time" name="endTime" value="${d.endTime}" required></label></div><label class="go-row"><span class="go-mini">Location</span><input class="go-field" name="location" value="${esc(d.location)}" list="pnPlaces" maxlength="100" placeholder="Choose a place" required><datalist id="pnPlaces">${state.locations.map(p=>`<option value="${esc(p.name)}">`).join('')}</datalist></label></div></section>
      <section><div class="go-sec-head"><label>Caregiver</label><span>Who owns this handoff?</span></div><div class="go-cards pn-owner-cards">${ownerCards}</div></section>
      <section><div class="go-sec-head"><label>Kids involved</label><span>Shown as tags in the schedule</span></div><div class="pn-kid-pills">${kidPills}</div></section>
      ${!e?`<section class="go-panel pn-repeat-panel"><div class="go-sec-head"><label>${icon('repeat')} Repeat this task</label><span>Set the rhythm once</span></div><div class="go-two"><label><span class="go-mini">Repeat</span><select class="go-field" name="repeat"><option value="none" ${d.repeat!=='weekly'?'selected':''}>Does not repeat</option><option value="weekly" ${d.repeat==='weekly'?'selected':''}>Every week</option></select></label><label><span class="go-mini">Weeks</span><input class="go-field" type="number" min="1" max="52" name="count" value="${d.count||4}"></label></div><p class="pn-muted">Repeats on selected days for this many weeks, starting on or after the date above. Each occurrence stays editable.</p></section>`:''}
      <details class="pn-disclosure"><summary>More options</summary><label class="pn-field"><span>Activity type</span><select class="pn-input" name="kind">${[['drive','Drive'],['cook','Cook'],['lead','Lead / at home'],['placeholder','Placeholder']].map(([v,t])=>`<option value="${v}" ${(d.kind||(!C.needsTravel(d)?'lead':'drive'))===v?'selected':''}>${t}</option>`).join('')}</select></label><label class="pn-field"><span>Notes</span><textarea class="pn-input" name="notes" rows="2" maxlength="500">${esc(d.notes||'')}</textarea></label><label class="pn-check-label"><input type="checkbox" name="tentative" ${d.tentative?'checked':''}>Caregiver is tentative</label><label class="pn-check-label"><input type="checkbox" name="locked" ${d.locked?'checked':''}>Keep this caregiver assignment fixed</label><label class="pn-check-label"><input type="checkbox" name="gcal" ${d.gcal?'checked':''}>Queue for Google Calendar</label></details></form>`,foot:btn(e?'Save changes':'Add to the plan','event-save','pn-primary go-btn primary')+(e?btn('Remove this occurrence','delete','pn-danger',`data-id="${esc(e.id)}"`):'')};
  }
  function goalsSheet() {
    const p=store.priorities[view.week]||{enabled:state.dinnerProtection,days:[0,1,2,3,4,5,6],time:'18:30',goal:'',meals:''};
    return {title:'Make room for what matters',eyebrow:range(view.week),body:`<form id="pnGoalsForm"><label class="pn-check-label"><input type="checkbox" name="enabled" ${p.enabled?'checked':''}>Protect family dinner</label><p class="pn-muted">Flag travel or events that cross this 45-minute window. Enabling this also turns on dinner protection in Settings.</p><div class="pn-goal-days">${dayAbbrs.map((d,i)=>`<label>${d}<span>${fmt(C.dateAdd(view.week,i))}</span><input type="checkbox" name="days" value="${i}" aria-label="Dinner on ${dayNames[i]}, ${fmt(C.dateAdd(view.week,i))}" ${p.days.includes(i)?'checked':''}></label>`).join('')}</div><label class="pn-field"><span>Dinner starts</span><input class="pn-input" name="time" type="time" value="${p.time}"></label><label class="pn-field"><span>One priority for this week</span><input class="pn-input" name="goal" value="${esc(p.goal)}" placeholder="An evening walk together" maxlength="100"></label><label class="pn-field"><span>Meal ideas</span><textarea class="pn-input" name="meals" rows="3" maxlength="1000" placeholder="Monday: taco bowls\nWednesday: leftovers\nFriday: pizza together">${esc(p.meals)}</textarea></label><p class="pn-muted">Dinner protection flags conflicts; it does not move events or create calendar entries.</p></form>`,foot:btn('Save priorities','goals-save')};
  }
  function incoming() {
    // Explicit sample CalendarProvider. Stable external IDs make pulling idempotent.
    return [{id:990000001,calendarId:'sample:library',date:C.dateAdd(C.BASE_WEEK,2),title:'Library makers club',time:'16:00',endTime:'16:45',location:'Community Center',kids:AppStore.children().slice(0,1),mode:'Drive',kind:'drive'},
      {id:990000002,calendarId:'sample:conference',date:C.dateAdd(C.BASE_WEEK,4),title:'Teacher conference',time:'15:00',endTime:'15:30',location:'Oak Ridge Elementary',kids:AppStore.children().slice(0,1),mode:'Drive',kind:'drive'}];
  }
  function calendarSheet() {
    const pulling=view.calendarDirection==='pull';
    const items=pulling?incoming().filter(e=>!store.calendar.pulled.includes(e.calendarId)):records().filter(e=>e.gcal&&store.calendar.exports[e.id]!==C.signature(e));
    return {title:'Keep calendars in step',eyebrow:'Google Calendar · not connected',body:`<p class="pn-note">Try the pull and push review with sample events. Google Calendar is not connected; this preview changes only the local plan.</p><div class="pn-toggle pn-calendar-direction">${btn(`${icon('pull')} Pull into Plan`,'calendar-pull','',`aria-pressed="${pulling}"`)}${btn(`${icon('push')} Push to Calendar`,'calendar-push','',`aria-pressed="${!pulling}"`)}</div><p class="pn-muted">${pulling?'Review incoming schedule details. New events arrive unassigned; existing caregiver and completion details are preserved.':'Review titles, dates, times, and places. Caregiver, completion, and private notes stay in Heli-Pad.'}</p>${items.length?items.map(e=>`<label class="pn-check-label pn-review-item"><input type="checkbox" name="calendarSelection" value="${esc(e.id)}" checked><span><strong>${esc(e.title)}</strong><br><span class="pn-muted">${fmt(e.date)}, ${e.date.slice(0,4)} · ${window.isAllDay && window.isAllDay(e) ? 'All day' : `${clock(e.time)}–${clock(e.endTime)}`} · ${esc(e.location)}</span></span></label>`).join(''):`<div class="pn-empty">${icon('calendar')}<strong>${pulling?'Sample inbox is clear.':'Nothing queued.'}</strong>${pulling?'Both sample events are already in the plan.':'Tick “Queue schedule for Google Calendar” when adding or editing an event.'}</div>`}<p class="pn-muted">${store.calendar.lastReview?`Last preview review: ${new Date(store.calendar.lastReview).toLocaleString()}`:'No calendar review yet.'}</p>`,foot:items.length?btn(pulling?'Pull selected sample events':'Preview selected push','calendar-apply'):btn('Back to the week','close')};
  }
  function readForm(id) { return new FormData(document.getElementById(id)); }
  function formError(message) { const el=document.getElementById('pnError');if(el){el.hidden=false;el.textContent=message;} }
  function saveEvent() {
    const form=document.getElementById('pnEventForm');if(!form.reportValidity())return;
    const f=readForm('pnEventForm'),old=sheet.data.id?find(sheet.data.id):null;
    const fields={title:f.get('title').trim(),date:f.get('date'),time:f.get('time'),endTime:f.get('endTime'),location:f.get('location').trim(),owner:f.get('owner'),kind:f.get('kind'),kids:f.getAll('kids'),notes:f.get('notes')||'',tentative:f.has('tentative'),locked:f.has('locked'),gcal:f.has('gcal'),repeat:f.get('repeat')||'none',count:Number(f.get('count')||1),weekdays:f.getAll('weekdays').map(Number)};
    if(!fields.location)return formError('Choose a location.');
    fields.kid=fields.kids.join(', ');
    fields.mode=fields.kind==='drive'?'Drive':'Home';fields.color=ownerColor(fields.owner);
    try {
      const batch=C.occurrences(fields), seriesId=old?.seriesId||(batch.length>1?`series-${crypto.randomUUID()}`:undefined);
      let nextId=Math.max(Date.now(),...records().map(e=>Number(e.id)||0))+1;
      const selectedDates=new Set(batch.map(e=>e.date));
      const related=old?.seriesId?records().filter(e=>e.seriesId===old.seriesId&&selectedDates.has(e.date)):[];
      const replacedIds=new Set([old?.id,...related.map(e=>e.id)]);
      const all=records().filter(e=>!replacedIds.has(e.id));
      const retainedDate=batch.some(e=>e.date===old?.date)?old.date:batch[0].date;
      for(const e of batch){
        const {repeat,count,weekdays,...record}=e;
        const existing=related.find(item=>item.date===e.date)||(old&&e.date===retainedDate?old:null);
        all.push({...existing,...record,id:existing?.id||nextId++,done:existing?.done||false,...(seriesId?{seriesId}:{}),...(existing?.calendarId?{calendarId:existing.calendarId}:{})});
      }
      view.week=C.monday(batch[0].date);view.day=batch[0].date;view.filter='all';
      replaceAll(all);closeSheet();toast(old?'Event updated':`${batch.length} ${batch.length===1?'event':'events'} added`);
    } catch(err){formError(err.message);}
  }
  function handle(action,button) {
    const id=button.dataset.id,value=button.dataset.value;
    if(action==='prev')return changeWeek(-1);
    if(action==='next')return changeWeek(1);
    if(action==='day'){view.day=button.dataset.date;view.scheduleOpen=false;render();return;}
    if(action==='toggle-schedule'){view.scheduleOpen=!view.scheduleOpen;render();return;}
    if(action==='close')return closeSheet();if(action==='back')return goBack();
    if(action==='review-filter'){view.reviewFilter=value;paintSheet();return;}
    if(action==='review'){view.reviewFilter=value||'all';openSheet('review');return;}
    if(action==='review-save'){const stats=C.summary(weekRecords(),getOptions());store.reviewed[view.week]=fingerprint();save();render();openSheet('reviewed',{remaining:stats.total-stats.ready});return;}
    if(['calendar','goals','jump','filter','routines'].includes(action)){openSheet(action);return;}
    if(action==='rules'){openSheet('rules',{},true);return;}
    if(action==='rules-save'){const n=Number(document.querySelector('[name=buffer]').value);if(!Number.isInteger(n)||n<0||n>45)return formError('Choose a buffer from 0 to 45 minutes.');AppStore.setSetting('buffer',n);goBack();return;}
    if(action==='templates'){openSheet('templates');return;}
    if(action==='use-template')return useTemplate(id);
    if(action==='manage-templates'){closeSheet();state.familyActivePanel='events';go('family');return;}
    if(action==='add'){openSheet('event');return;}
    if(action==='routine'){openSheet('routine',{key:value},Boolean(sheet));return;}
    if(action==='event'||action==='assign'||action==='delete'){openSheet(action,{id},Boolean(sheet));return;}
    if(action==='set-filter'){view.filter=value;closeSheet();render();return;}
    if(action==='base-week'){view.week=C.BASE_WEEK;view.day=view.week;closeSheet();render();return;}
    if(action==='jump-save'){const date=document.querySelector('[name=jumpDate]').value;if(!date)return formError('Choose a date.');view.week=C.monday(date);view.day=date;closeSheet();render();return;}
    if(action==='candidate'){
      sheet.data.tentative=document.querySelector('[name=tentative]').checked;sheet.data.locked=document.querySelector('[name=locked]').checked;sheet.data.owner=value;paintSheet();return;
    }
    if(action==='routine-candidate'){
      sheet.data.locked=document.querySelector('[name=routineLocked]')?.checked!==false;sheet.data.owner=value;paintSheet();return;
    }
    if(action==='assign-save'){
      patch(sheet.data.id,{owner:sheet.data.owner,tentative:sheet.data.owner!=='TBD'&&document.querySelector('[name=tentative]').checked,locked:document.querySelector('[name=locked]').checked,color:ownerColor(sheet.data.owner)});goBack();toast('Assignment saved');return;
    }
    if(action==='routine-save'){
      const group=routineFromValue(sheet.data.key);if(!group)return closeSheet();
      const ids=new Set(group.events.map(e=>String(e.id))),owner=sheet.data.owner;
      replaceAll(records().map(e=>ids.has(String(e.id))?{...e,owner,tentative:false,locked:document.querySelector('[name=routineLocked]')?.checked!==false,color:ownerColor(owner)}:e));
      closeSheet();toast(`${group.events.length} recurring assignments updated`);return;
    }
    if(action==='event-save')return saveEvent();
    if(action==='delete-confirm'){replaceAll(records().filter(e=>String(e.id)!==String(id)));closeSheet();toast('Occurrence removed');return;}
    if(action==='goals-save'){
      const f=readForm('pnGoalsForm'),days=f.getAll('days').map(Number),time=f.get('time');
      if(f.has('enabled')&&(!days.length||!time))return formError('Choose dinner days and a start time.');
      store.priorities[view.week]={enabled:f.has('enabled'),days,time:time||'18:30',goal:f.get('goal').trim(),meals:f.get('meals').trim()};AppStore.commit('settings',()=>{if(f.has('enabled'))state.dinnerProtection=true;});closeSheet();toast('Weekly priorities saved');return;
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
  document.addEventListener('change',e=>{
    const form=e.target.closest('#pnEventForm');if(!form)return;

    if(e.target.name==='date'&&e.target.value){
      const start=C.monday(e.target.value);
      const checked=[...form.querySelectorAll('[name=weekdays]:checked')];
      if(checked.length===1){checked[0].checked=false;form.querySelector(`[name=weekdays][value="${C.daysBetween(start,e.target.value)}"]`).checked=true;}
      form.querySelectorAll('[data-repeat-date]').forEach(el=>el.textContent=fmt(C.dateAdd(start,Number(el.dataset.repeatDate))));
      form.querySelector('.go-sec-head + .go-panel')?.previousElementSibling.querySelector('span')?.replaceChildren(document.createTextNode(`${weekday(e.target.value)}, ${fmt(e.target.value)}`));
    }
  });
  let suppressClickUntil=0;
  document.addEventListener('click',e=>{if(Date.now()<suppressClickUntil && e.target.closest('.pn-screen')){e.preventDefault();return;}const button=e.target.closest('[data-pn]');if(button)handle(button.dataset.pn,button);});
  // Gesture accelerators have visible arrow buttons and never commit edits.
  let swipe=null;
  document.addEventListener('pointerdown',e=>{if(e.target.closest('.pn-hero'))swipe={x:e.clientX,y:e.clientY};});
  document.addEventListener('pointerup',e=>{if(!swipe)return;const dx=e.clientX-swipe.x,dy=e.clientY-swipe.y;swipe=null;if(Math.abs(dx)>65&&Math.abs(dy)<35){e.preventDefault();suppressClickUntil=Date.now()+350;changeWeek(dx<0?1:-1);}});
  document.addEventListener('pointercancel',()=>{swipe=null;});
  AppStore.registerDraft(()=>sheet?.data?.draft);
  AppStore.subscribe(reason=>{if(reason==='people'&&sheet)closeSheet();});
  window.HeliPlan={records,useTemplate};
  window.renderPlanConcept=render;
  window.closePlanSheet=closeSheet;
  render();
  if(location.hash==='#plan')go('plan');
})();
