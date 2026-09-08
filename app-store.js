/* The shared mutation boundary for the HTML lab. Screens never own a second roster or plan. */
(function(root,factory){
  const api=factory();
  if(typeof module==='object'&&module.exports)module.exports=api;else root.AppStoreFactory=api;
})(typeof globalThis!=='undefined'?globalThis:this,function(){
  'use strict';
  const BASE_WEEK='2026-08-03',PLAN_KEY='heli-pad-plan-v1';
  const SETTINGS=['buffer','synced','trafficMode','dinnerProtection','currentUser','mockTime','parentLocations','people','homeAddress','homePlaceName','timeZone','notifyLeaveBy','notifyDriverNeeded','notifyCrew','connections'];
  const RESERVED=new Set(['all','family','tbd','unassigned','undetermined']);
  const dayDate=d=>{const date=new Date(BASE_WEEK+'T12:00:00Z');date.setUTCDate(date.getUTCDate()+Number(d));return date.toISOString().slice(0,10);};
  const splitKids=e=>Array.isArray(e.kids)?e.kids:String(e.kid||'').split(',').map(x=>x.trim()).filter(Boolean);
  function create(state,config={}){
    const storage=config.storage,keys=config.keys||{},listeners=new Set(),drafts=new Set();
    function read(key,fallback){try{return JSON.parse(storage?.getItem(key)||'null')??fallback;}catch{return fallback;}}
    state.plan=state.plan||read(PLAN_KEY,{});
    Object.assign(state.plan,{future:state.plan.future||[],priorities:state.plan.priorities||{},reviewed:state.plan.reviewed||{},calendar:{exports:{},pulled:[],lastReview:null,...state.plan.calendar}});
    state.people=state.people||[];state.locations=state.locations||[];state.templates=state.templates||[];state.parentLocations=state.parentLocations||{};
    const people=kind=>state.people.filter(p=>!kind||p.kind===kind);
    const caregivers=()=>people('caregiver').map(p=>p.name),children=()=>people('child').map(p=>p.name);
    const home=()=>state.homePlaceName||'Home';
    const records=()=>[...Object.entries(state.eventsByDay||{}).flatMap(([d,list])=>list.map(e=>({...e,date:dayDate(d)}))),...state.plan.future].sort((a,b)=>a.date.localeCompare(b.date)||a.time.localeCompare(b.time));
    const mutableRecords=()=>[...Object.values(state.eventsByDay||{}).flat(),...state.plan.future,...state.templates,...[...drafts].map(get=>get()).filter(Boolean),...(state.goDraft?[state.goDraft]:[])];
    const hasPlace=name=>state.locations.some(l=>l.name===name);
    function normalizeRecord(e){
      if(!['Family','TBD'].includes(e.owner)&&!caregivers().includes(e.owner)){e.owner='TBD';e.tentative=false;e.locked=false;}
      if(e.lead!==undefined)e.lead=e.owner;
      const kids=splitKids(e);e.kids=kids.includes('All')?['All']:[...new Set(kids.filter(k=>children().includes(k)))];e.kid=e.kids.join(', ');
      e.color=color(e.owner);
      if(e.location&&!hasPlace(e.location))e.locationMissing=true;else delete e.locationMissing;
    }
    function reconcile(){
      const crew=caregivers(),kids=children();
      for(const e of mutableRecords())normalizeRecord(e);
      if(!hasPlace(home()))state.homePlaceName=state.locations[0]?.name||'Home';
      state.homeAddress=state.locations.find(l=>l.name===home())?.address||'';
      for(const name of Object.keys(state.parentLocations))if(!crew.includes(name))delete state.parentLocations[name];
      for(const name of crew)if(!hasPlace(state.parentLocations[name]))state.parentLocations[name]=home();
      if(state.currentUser!=='All'&&!crew.includes(state.currentUser))state.currentUser='All';
      for(const key of ['goCrewFilter','activeCaregiverFilter'])if(state[key]&&!['all','All','Family','TBD',...crew].includes(state[key]))state[key]=key==='goCrewFilter'?null:'all';
      for(const key of ['goKidFilter','activeKidFilter','familyKidStatsFilter'])if(state[key]&&!['all','All',...kids].includes(state[key]))state[key]=key==='familyKidStatsFilter'?'All':'all';
      if(state.selectedCandidateDriver&&!crew.includes(state.selectedCandidateDriver))state.selectedCandidateDriver=null;
      const ids=new Set(records().map(e=>String(e.id)));
      for(const id of Object.keys(state.plan.calendar.exports))if(!ids.has(id))delete state.plan.calendar.exports[id];
    }
    function color(name){return state.people.find(p=>p.name===name)?.color||({Family:'#b08313',TBD:'#bf6c2c',Unassigned:'#bf6c2c'}[name])||'#687469';}
    function save(reason='data'){
      reconcile();
      if(storage){
        for(const [key,value] of [[keys.events,state.eventsByDay],[keys.locations,state.locations],[keys.templates,state.templates],[keys.rules,state.smartRules],[keys.settings,Object.fromEntries(SETTINGS.map(k=>[k,state[k]]))],[PLAN_KEY,state.plan]])if(key)storage.setItem(key,JSON.stringify(value));
      }
      for(const notify of listeners)notify(reason);
    }
    function commit(reason,change){change();save(reason);config.render?.();}
    function allReferences(name){return mutableRecords().filter(e=>e.owner===name||splitKids(e).includes(name)).length;}
    function renamePerson(id,value){
      const p=state.people.find(p=>p.id===id),name=String(value||'').trim();
      if(!p)throw Error('This person is no longer in the family.');
      if(!name||RESERVED.has(name.toLowerCase()))throw Error('Choose a personal name, rather than a shared assignment label.');
      if(state.people.some(x=>x.id!==id&&x.name.toLowerCase()===name.toLowerCase()))throw Error('Someone in the family already uses that name.');
      const from=p.name;if(from===name)return;
      commit('people',()=>{
        for(const e of mutableRecords()){
          if(e.owner===from)e.owner=name;if(e.lead===from)e.lead=name;
          e.kids=splitKids(e).map(k=>k===from?name:k);e.kid=e.kids.join(', ');
        }
        for(const key of ['currentUser','goCrewFilter','goKidFilter','activeCaregiverFilter','activeKidFilter','familyKidStatsFilter','selectedCandidateDriver'])if(state[key]===from)state[key]=name;
        if(from in state.parentLocations){state.parentLocations[name]=state.parentLocations[from];delete state.parentLocations[from];}
        p.name=name;
      });
    }
    function removePerson(id){commit('people',()=>{state.people=state.people.filter(p=>p.id!==id);});}
    function setPersonRole(id,relationship){commit('people',()=>{const p=state.people.find(p=>p.id===id);if(p){p.relationship=relationship;p.kind=relationship==='Child'?'child':'caregiver';}});}
    function addPerson(kind){
      let n=1,name;do{name=`${kind==='child'?'Child':'Caregiver'} ${n++}`;}while(state.people.some(p=>p.name===name));
      const palette=['#c75f45','#397cad','#8f55a0','#3f806e','#a8672b','#5a6ea8','#8a6d3b'];
      const p={id:config.id?.()||`person-${Date.now()}-${Math.random().toString(16).slice(2)}`,name,kind,relationship:kind==='child'?'Child':'Other',color:palette[state.people.length%palette.length]};
      commit('people',()=>state.people.push(p));return p;
    }
    function setSetting(key,value){
      if(!SETTINGS.includes(key))throw Error('Unknown setting.');
      if(key==='buffer'){value=Number(value);if(!Number.isInteger(value)||value<0||value>45)throw Error('Choose a buffer from 0 to 45 minutes.');}
      if(key==='timeZone'&&value!=='device'){try{new Intl.DateTimeFormat('en',{timeZone:value});}catch{throw Error('Choose a valid time zone.');}}
      commit('settings',()=>{state[key]=value;});
    }
    function setHomeAddress(address){const l=state.locations.find(l=>l.name===home());if(!l)throw Error('Choose a home location first.');updateLocation(state.locations.indexOf(l),{...l,address:String(address).trim(),source:'manual'});}
    function setBases(bases){for(const [name,place] of Object.entries(bases))if(!caregivers().includes(name)||!hasPlace(place))throw Error('Choose a saved place for each caregiver.');commit('settings',()=>{state.parentLocations={...bases};});}
    // Place identity and address determine route-cache identity. Renaming preserves it; moving invalidates it.
    for(const l of state.locations)if(!Object.hasOwn(l,'routeKey')){const seed=config.defaultLocations?.find(x=>x.name===l.name&&x.address===l.address);l.routeKey=seed?seed.name:null;}
    function updateLocation(index,data){
      const old=state.locations[index],name=String(data.name||'').trim();
      if(!name||!String(data.address||'').trim())throw Error('Enter a place name and address.');
      if(state.locations.some((l,i)=>i!==index&&l.name.toLowerCase()===name.toLowerCase()))throw Error('A place already uses this name.');
      commit('locations',()=>{
        const next={...old,...data,name,routeKey:old&&old.address===data.address?old.routeKey:null};
        if(old){
          state.locations[index]=next;
          if(old.name!==name){
            for(const e of mutableRecords()){if(e.location===old.name)e.location=name;if(e.place===old.name)e.place=name;}
            for(const n of Object.keys(state.parentLocations))if(state.parentLocations[n]===old.name)state.parentLocations[n]=name;
            if(home()===old.name)state.homePlaceName=name;
          }
        }else state.locations.push(next);
      });
    }
    function removeLocation(index){
      const l=state.locations[index];if(!l)return;
      if(l.name===home()||Object.values(state.parentLocations).includes(l.name))throw Error('Change home and starting bases before removing this place.');
      if(mutableRecords().some(e=>e.location===l.name||e.place===l.name))throw Error('This place is used by an event or template. Change those references first.');
      commit('locations',()=>state.locations.splice(index,1));
    }
    function replaceRecords(list){
      commit('events',()=>{
        state.eventsByDay=Object.fromEntries(Array.from({length:7},(_,d)=>[d,[]]));state.plan.future=[];
        for(const e of list){const d=Math.round((Date.parse(e.date+'T12:00:00Z')-Date.parse(BASE_WEEK+'T12:00:00Z'))/86400000);if(d>=0&&d<7)state.eventsByDay[d].push({...e});else state.plan.future.push({...e});}
      });
    }
    function travel(origin,destination,at){
      if(!origin||!destination)return null;if(origin===destination)return 0;
      const a=state.locations.find(l=>l.name===origin)?.routeKey,b=state.locations.find(l=>l.name===destination)?.routeKey;
      const base=a&&b?config.routes?.[a]?.[b]:null;
      if(base==null)return null;
      const peak=Number(at)>=420&&Number(at)<540||Number(at)>=960&&Number(at)<1080;
      return Math.round(base*(state.trafficMode&&peak?1.15:1));
    }
    const planningOptions=()=>({crew:caregivers(),home:home(),origins:state.parentLocations,buffer:state.buffer,priorities:state.plan.priorities,dinnerProtection:state.dinnerProtection,travel,routes:config.routes||{}});
    function clock(now=new Date()){
      const zone=state.timeZone==='device'||!state.timeZone?undefined:state.timeZone;
      const parts=Object.fromEntries(new Intl.DateTimeFormat('en-US',{timeZone:zone,hourCycle:'h23',hour:'2-digit',minute:'2-digit',weekday:'short'}).formatToParts(now).map(p=>[p.type,p.value]));
      return {minutes:Number(parts.hour)*60+Number(parts.minute),day:['Mon','Tue','Wed','Thu','Fri','Sat','Sun'].indexOf(parts.weekday)};
    }
    function resetSchedule(seed){commit('events',()=>{state.eventsByDay=structuredClone(seed);state.plan.future=[];state.plan.reviewed={};state.plan.calendar={exports:{},pulled:[],lastReview:null};});}
    function clearData(){if(!storage)return;for(const key of [keys.events,keys.locations,keys.templates,keys.rules,keys.settings,PLAN_KEY])if(key)storage.removeItem(key);}
    reconcile();
    return {state,plan:state.plan,people,caregivers,children,home,color,records,save,commit,renamePerson,removePerson,setPersonRole,addPerson,setSetting,setHomeAddress,setBases,updateLocation,removeLocation,replaceRecords,travel,planningOptions,clock,resetSchedule,clearData,allReferences,normalizeRecord,
      subscribe(fn){listeners.add(fn);return()=>listeners.delete(fn);},registerDraft(get){drafts.add(get);return()=>drafts.delete(get);}};
  }
  return {create,BASE_WEEK,SETTINGS,splitKids};
});
