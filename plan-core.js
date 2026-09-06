/* Pure planning use cases. Calendar schedule fields and app-owned overlays stay separate. */
(function(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.PlanCore = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function() {
  'use strict';
  const BASE_WEEK = '2026-08-03'; // Same dated sample week as Go.
  const CREW = ['Mom', 'Dad', 'Nani', 'Grandma'];
  const mins = t => { const [h,m] = t.split(':').map(Number); return h*60+m; };
  const dateAdd = (date, days) => { const d = new Date(date+'T12:00:00'); d.setDate(d.getDate()+days); return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`; };
  const daysBetween = (a,b) => Math.round((Date.parse(b+'T12:00:00Z')-Date.parse(a+'T12:00:00Z'))/86400000);
  const monday = date => dateAdd(date, -((new Date(date+'T12:00:00').getDay()+6)%7));
  const needsTravel = e => e.mode !== 'Home' && e.location !== 'Home' && !['cook','placeholder'].includes(e.kind);
  const unassigned = e => !e.owner || ['TBD','Unassigned'].includes(e.owner);
  const end = e => { const t=mins(e.endTime); return t<=mins(e.time) ? t+1440:t; };
  const intersects = (a,b,c,d) => a<d && c<b;
  const route = (a,b,options) => a===b ? 0 : options.routes[a]?.[b] ?? null;
  const owned = (e,name) => e.owner===name || e.owner==='Family';
  function candidate(event, name, events, options) {
    const start=mins(event.time), finish=end(event), buffer=Number(options.buffer ?? 12);
    const others=events.filter(e=>e.date===event.date && e.id!==event.id && owned(e,name));
    const prior=others.filter(e=>end(e)<=start).sort((a,b)=>end(b)-end(a))[0];
    const origin=prior ? prior.location : start<540 ? 'Home' : options.origins[name] || 'Home';
    const eta=needsTravel(event) ? route(origin,event.location,options):0;
    const leave=eta===null ? start:start-eta-(needsTravel(event)?buffer:0);
    const overlap=others.find(e=>intersects(leave,finish,mins(e.time),end(e)));
    const slack=prior && eta!==null ? leave-end(prior):null;
    // Check the onward journey too; fixing one trip must not break the next.
    const next=others.filter(e=>mins(e.time)>=finish).sort((a,b)=>mins(a.time)-mins(b.time))[0];
    const nextEta=next && needsTravel(next) ? route(event.location,next.location,options):0;
    const onwardSlack=next && nextEta!==null ? mins(next.time)-nextEta-(needsTravel(next)?buffer:0)-finish:null;
    const unknown=eta===null || (next && nextEta===null);
    const conflict=Boolean(overlap || (slack!==null && slack<0) || (onwardSlack!==null && onwardSlack<0));
    return {name,origin,eta,leave,slack,onwardSlack,unknown,conflict,
      reason:overlap ? `Overlaps ${overlap.title}` : onwardSlack!==null && onwardSlack<0 ? `${Math.abs(onwardSlack)} min short before ${next.title}` : slack!==null && slack<0 ? `${Math.abs(slack)} min short after ${prior.title}` : unknown ? 'Route needs checking' : `${eta} min ${needsTravel(event)?'travel':'travel needed'}${prior?' from '+origin:''}`};
  }
  function analyze(events, options) {
    return events.map(event=> {
      const missing=unassigned(event), detail=candidate(event,missing?'Mom':event.owner,events,options);
      const risks=[];
      if(missing) risks.push({type:'driver', label:needsTravel(event)?'Needs driver':'Needs caregiver'});
      if(!missing && detail.conflict) risks.push({type:'overlap',label:detail.reason});
      if(!missing && !detail.conflict && detail.slack!==null && detail.slack<10) risks.push({type:'tight',label:`${detail.slack} min spare after travel + buffer`});
      if(detail.unknown) risks.push({type:'route',label:'Check the route'});
      if(!missing && detail.eta>=25) risks.push({type:'long',label:`${detail.eta} min drive`});
      const priority=options.priorities?.[monday(event.date)];
      if(priority?.enabled && priority.days?.includes((new Date(event.date+'T12:00:00').getDay()+6)%7) && needsTravel(event) && intersects(detail.leave,end(event),mins(priority.time),mins(priority.time)+45)) risks.push({type:'dinner',label:'Crosses family dinner'});
      const tentative=Boolean(event.tentative) && !missing;
      if(tentative) risks.push({type:'tentative',label:'Driver is tentative'});
      return {...event,detail,risks,status:missing?'missing':risks.length?'review':'ready'};
    });
  }
  function summary(events,options) {
    const list=analyze(events,options);
    return {list,total:list.length,ready:list.filter(e=>e.status==='ready').length,missing:list.filter(e=>e.status==='missing').length,review:list.filter(e=>e.status==='review').length};
  }
  function loads(events,options) {
    const result=Object.fromEntries(CREW.map(n=>[n,0]));
    for(const e of events) if(result[e.owner]!==undefined && needsTravel(e)) result[e.owner]+=candidate(e,e.owner,events,options).eta||0;
    return result;
  }
  function proposals(events,options) {
    let draft=events.map(e=>({...e}));
    const changes=[];
    for(const e of [...draft].sort((a,b)=>a.date.localeCompare(b.date)||a.time.localeCompare(b.time))) {
      if(e.done || e.owner==='Family' || e.tentative || e.locked || !needsTravel(e)) continue;
      const old=candidate(e,e.owner || 'Mom',draft,options), load=loads(draft,options);
      const pool=CREW.map(n=>candidate(e,n,draft,options)).filter(c=>!c.conflict&&!c.unknown);
      pool.sort((a,b)=>(a.eta+load[a.name]*.12)-(b.eta+load[b.name]*.12));
      const best=pool[0];
      if(!best || best.name===e.owner) continue;
      const saving=old.eta===null ? 0:old.eta-best.eta;
      const balancing=load[e.owner]-load[best.name]>=35 && best.eta<=old.eta+3;
      if(!unassigned(e)&&!old.conflict&&saving<5&&!balancing) continue;
      const beforeScore=summary(draft,options).list.filter(x=>x.risks.some(r=>r.type==='overlap')).length;
      const trial=draft.map(x=>x.id===e.id?{...x,owner:best.name,tentative:false}:x);
      if(summary(trial,options).list.filter(x=>x.risks.some(r=>r.type==='overlap')).length>beforeScore) continue;
      changes.push({id:e.id,date:e.date,title:e.title,time:e.time,from:e.owner||'TBD',to:best.name,eta:best.eta,saving,
        reason:unassigned(e)?'Covers an open handoff':old.conflict?'Clears a schedule overlap':saving>=5?`${saving} min less driving`:'Shares the driving more evenly'});
      draft=trial;
    }
    return {changes,before:loads(events,options),after:loads(draft,options),events:draft};
  }
  function occurrences(draft) {
    if(!/^\d{4}-\d{2}-\d{2}$/.test(draft.date) || !Number.isFinite(Date.parse(draft.date))) throw Error('Choose a date.');
    if(!draft.title.trim()) throw Error('Give this event a name.');
    if(!/^([01]\d|2[0-3]):[0-5]\d$/.test(draft.time) || !/^([01]\d|2[0-3]):[0-5]\d$/.test(draft.endTime) || mins(draft.endTime)<=mins(draft.time)) throw Error('End time must be after start time on the same day.');
    const count=draft.repeat==='weekly'?Number(draft.count):1;
    if(!Number.isInteger(count)||count<1||count>52) throw Error('Choose 1 to 52 occurrences.');
    return Array.from({length:count},(_,i)=>({...draft,date:dateAdd(draft.date,i*7)}));
  }
  const schedule = e => ({date:e.date,title:e.title,time:e.time,endTime:e.endTime,location:e.location});
  const signature = e => JSON.stringify(schedule(e));
  function pull(records,incoming) {
    const merged=records.map(e=>({...e}));
    for(const item of incoming) {
      const existing=merged.find(e=>e.calendarId===item.calendarId);
      // Preserve assignee, completion, buffers and notes on an updated schedule.
      if(existing) Object.assign(existing,schedule(item));
      else merged.push({...item,owner:'TBD',done:false,tentative:false});
    }
    return merged;
  }
  return {BASE_WEEK,CREW,mins,dateAdd,daysBetween,monday,needsTravel,unassigned,candidate,analyze,summary,loads,proposals,occurrences,schedule,signature,pull};
});
