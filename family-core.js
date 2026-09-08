/* Shared template rules. No calendar writes or AI network calls. */
(function(root){
  'use strict';
  let childNames=()=>['Soni','Maya','Noah'];
  const configure=options=>{childNames=options.children;};
  const minutes=t=>/^\d{2}:\d{2}$/.test(t||'')?Number(t.slice(0,2))*60+Number(t.slice(3)):NaN;
  const time=n=>`${String(Math.floor(n/60)).padStart(2,'0')}:${String(n%60).padStart(2,'0')}`;
  function children(value){
    const list=Array.isArray(value.kids)?value.kids:String(value.kid||'All').split(/,\s*/);
    return list.includes('All')?[...childNames()]:childNames().filter(k=>list.includes(k));
  }
  function normalize(t){
    const defaults={tpl_1:'07:35',tpl_2:'17:15',tpl_3:'15:20',tpl_4:'16:00',tpl_5:'13:40',tpl_6:'18:30'};
    const start=t.time||defaults[t.id]||'16:00';
    const end=t.endTime||time(Math.min(1439,minutes(start)+Number(t.duration||60)));
    const kids=children(t);
    return {...t,time:start,endTime:end,kids,kid:kids.join(', '),owner:t.owner||'TBD',mode:t.mode||(t.location==='Home'?'Home':'Drive'),duration:minutes(end)-minutes(start)};
  }
  function validate(t){
    if(!t.title?.trim())throw Error('Give this template a name.');
    if(!t.location?.trim())throw Error('Choose a saved location.');
    if(!t.kids?.length)throw Error('Choose at least one child.');
    const a=minutes(t.time),b=minutes(t.endTime);
    if(!Number.isFinite(a)||!Number.isFinite(b)||a<0||b>=1440||b<=a||Number(t.time.slice(3))>59||Number(t.endTime.slice(3))>59)throw Error('Choose an end time after the start time on the same day.');
    const normalized=normalize(t);
    if(!normalized.kids.length)throw Error('Choose at least one current child.');
    return normalized;
  }
  const signature=t=>{const n=normalize(t);return JSON.stringify([n.title.trim().toLowerCase(),n.location,n.time,n.endTime,[...n.kids].sort(),n.mode]);};
  function suggestions(events,templates){
    const saved=new Set(templates.map(signature)),groups=new Map();
    for(const event of events){
      if(event.allDay||!event.time||!event.endTime)continue;
      const key=signature(event); if(saved.has(key))continue;
      if(!groups.has(key))groups.set(key,[]);
      groups.get(key).push(event);
    }
    return [...groups.entries()].filter(([,list])=>list.length>=2).map(([key,list])=>{
      const owners=[...new Set(list.map(e=>e.owner))];
      return {key,count:list.length,draft:normalize({...list[0],id:undefined,owner:owners.length===1?owners[0]:'TBD'})};
    }).sort((a,b)=>b.count-a.count||a.draft.title.localeCompare(b.draft.title)).slice(0,3);
  }
  function eventDraft(template,date){
    const t=normalize(template);
    return {title:t.title,date,time:t.time,endTime:t.endTime,kids:[...t.kids],kid:t.kid,owner:t.owner,location:t.location,mode:t.mode,kind:t.mode==='Home'?'lead':'drive',repeat:'none',count:1,notes:t.notes||'',gcal:false,tentative:false,locked:false};
  }
  const api={get KIDS(){return childNames();},configure,normalize,validate,suggestions,eventDraft,signature};
  if(typeof module!=='undefined'&&module.exports)module.exports=api;
  else root.FamilyCore=api;
})(typeof window!=='undefined'?window:globalThis);
