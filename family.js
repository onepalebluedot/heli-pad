/* Family's saved places, household settings, and reusable schedule templates. */
(() => {
  'use strict';
  const C=FamilyCore;
  C.configure({children:()=>AppStore.children()});
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const icon=n=>appIcon(n);
  const button=(label,action,cls='fh-use',attrs='')=>`<button type="button" class="${cls}" data-fh="${action}" ${attrs}>${label}</button>`;
  const mark=n=>`<span class="go-mark" style="background:${goPersonBg(n)};color:${goPersonText(n)}">${esc(n[0])}</span>`;
  const refresh=()=>{renderAll();window.renderSettings?.();};
  const templateList=()=>state.templates.map(C.normalize);
  const homeName=()=>AppStore.home();
  const baseNames=()=>new Set([homeName(),...Object.values(state.parentLocations)]);
  const address=l=>l?.address||'No address saved';
  const locationRow=(l,idx)=>`<div class="fam-loc-card"><div class="fam-loc-icon">${icon(l.icon||'map-pin')}</div><div class="fam-loc-body"><div class="fam-loc-title">${esc(l.name)}</div><div class="fam-loc-address">${esc(address(l))}</div></div>${button(icon('pencil'),'location','fam-icon-btn fh-location-edit',`data-index="${idx}" aria-label="Edit ${esc(l.name)}"`)}</div>`;
  function locations(){
    const bases=baseNames(),home=state.locations.find(l=>l.name===homeName());
    return `<section class="fh-bases" aria-label="Home and starting bases"><div class="fh-base-head"><h3>Where your day begins</h3>${button('Settings','settings','')}</div><div class="fh-base-row">${icon('house')}<div><strong>Home</strong><small>${esc(address(home))}</small></div></div>${Object.entries(state.parentLocations).map(([name,place])=>{const l=state.locations.find(l=>l.name===place);return `<div class="fh-base-row">${mark(name)}<div><strong>${esc(name)}'s starting base · ${esc(place)}</strong><small>${esc(address(l))}</small></div></div>`;}).join('')}<p class="fh-base-foot">Set during setup. Change home and work bases in Settings.</p></section>
      <div class="fam-panel-head"><h2>Your regular places</h2>${button('+ Add location','location','fam-action-link')}</div><p class="fh-intro">Save a place once. Find it quickly when you plan a handoff.</p><div class="fam-loc-list">${state.locations.map((l,i)=>bases.has(l.name)?'':locationRow(l,i)).join('')||'<p class="fh-empty">Add your first regular stop.</p>'}</div><p class="fh-note">Travel time updates with the route and traffic, rather than being saved with a place. This preview uses sample routes.</p>`;
  }
  function suggestions(){
    const records=window.HeliPlan?.records()||Object.values(state.eventsByDay).flat();
    return C.suggestions(records,state.templates);
  }
  function templates(){
    const list=templateList(),ideas=suggestions();
    return `<div class="fam-panel-head"><h2>Your shortcuts</h2>${button('+ New template','template','fam-action-link')}</div><p class="fh-intro">The handoffs you use often, ready for another day. Choose a date when you use one in Plan.</p>${list.map(t=>`<article class="fh-tpl"><div class="fh-tpl-top"><div class="fh-tpl-copy"><h3>${esc(t.title)}</h3><p>${icon('clock-3')}${formatTime(t.time)} – ${formatTime(t.endTime)}</p><p>${icon('map-pin')}${esc(t.location)}</p></div>${button(icon('pencil'),'template','fam-icon-btn',`data-id="${esc(t.id)}" aria-label="Edit ${esc(t.title)}"`)}</div><div class="fh-tpl-foot"><div class="fh-kid-tags">${t.kids.map(k=>`<span>${esc(k)}</span>`).join('')}</div>${button(`Use in Plan ${icon('arrow-up-right')}`,'use','fh-use',`data-id="${esc(t.id)}" aria-label="Use ${esc(t.title)} in Plan"`)}</div></article>`).join('')||'<p class="fh-empty">Save a frequently used schedule item to get started.</p>'}
      <section class="fh-ai" aria-label="AI template suggestions"><div class="fh-ai-head">${icon('sparkles')}<h3>A shortcut for next time</h3><span class="fh-badge">AI preview</span></div><p class="fh-intro">Repeated handoffs in your schedule can become templates. Review the details before saving.</p>${ideas.map((idea,i)=>`<article class="fh-suggestion"><div><strong>${esc(idea.draft.title)}</strong><small>${idea.count} matching handoffs · ${formatTime(idea.draft.time)}<br>${esc(idea.draft.kids.join(', '))} · ${esc(idea.draft.location)}</small></div>${button('Review','suggestion','fh-use',`data-index="${i}" aria-label="Review suggestion for ${esc(idea.draft.title)}"`)}</article>`).join('')||'<p class="fh-empty">No new repeated handoffs found. Suggestions appear as your schedule develops.</p>'}<p class="fh-note">Preview uses repeated schedule patterns. No AI service is connected.</p></section>`;
  }
  function familyEvents(){return Object.values(state.eventsByDay).flat();}
  function renderHero(){
    const el=document.getElementById('famHeroCard');if(!el)return;
    const list=familyEvents(),load=PlanCore.loads(AppStore.records().filter(e=>e.date>=PlanCore.BASE_WEEK&&e.date<=PlanCore.dateAdd(PlanCore.BASE_WEEK,6)),AppStore.planningOptions());
    const max=Math.max(1,...Object.values(load));
    el.innerHTML=`<div class="fam-hero-head"><div class="fam-hero-eyebrow">This sample week</div></div><h2>Care across the family</h2><p>${list.length} events · ${list.filter(e=>e.owner==='TBD').length} awaiting a caregiver</p><div class="pn-load-chart">${AppStore.caregivers().map(name=>`<div class="pn-load-row"><span class="pn-load-name">${mark(name)}${esc(name)}</span><div class="pn-track"><i style="width:${(load[name]||0)/max*100}%;--person:${goPersonInk(name)}"></i></div><strong>${load[name]||0}<small> min</small></strong></div>`).join('')||'<p>Add caregivers in Settings to assign your schedule.</p>'}</div><p class="fh-note">Estimated driving time. Unknown routes need checking.</p>`;
  }
  function kidsStats(){
    const events=familyEvents();
    return `<div class="fam-panel-head"><h2>Each child's week</h2></div><p class="fh-intro">Activities in the sample week, shared with Go and Plan.</p>${AppStore.children().map(name=>{const list=events.filter(e=>e.kids?.includes(name)||e.kids?.includes('All'));return `<article class="fh-tpl"><h3>${esc(name)}</h3><p>${list.length} events · ${list.filter(e=>e.owner==='TBD').length} awaiting a caregiver</p>${list.slice(0,4).map(e=>`<p>${esc(e.title)} · ${esc(e.location)}</p>`).join('')}</article>`;}).join('')||'<p class="fh-empty">Add children in Settings to include them in events and templates.</p>'}`;
  }
  function crew(){
    return `<div class="fam-panel-head"><h2>Your caregivers</h2><button class="fh-use" onclick="go('settings')">Manage in Settings</button></div>${AppStore.people('caregiver').map(p=>`<article class="fh-tpl"><div class="fh-base-row">${mark(p.name)}<div><strong>${esc(p.name)}</strong><small>${esc(p.relationship)} · starts at ${esc(state.parentLocations[p.name])}</small></div></div></article>`).join('')||'<p class="fh-empty">No caregivers yet.</p>'}<section class="fh-ai"><h3>Shared planning preferences</h3><p>${state.buffer} minutes of travel buffer · Traffic adjustment ${state.trafficMode?'on':'off'} · Dinner protection ${state.dinnerProtection?'on':'off'}</p><button class="fh-use" onclick="go('settings')">Change in Settings</button></section>`;
  }
  // Sample addresses are intentionally fictional. Google Places replaces this list when configured.
  const samplePlaces=[...defaultLocations.map(l=>({...l,address:l.name==='Warren Plant'?'6400 Manufacturing Drive, Warren, MI 48092':`${l.address}, Troy, MI 48084`,source:'sample'})),
    {name:'Maple Swim School',address:'820 Maple Road, Troy, MI 48084',icon:'waves',source:'sample'},
    {name:'Oak Park Library',address:'120 Oak Park Drive, Troy, MI 48084',icon:'book-open',source:'sample'},
    {name:'Pine Street Dance Studio',address:'450 Pine Street, Troy, MI 48084',icon:'music-2',source:'sample'}];
  let sheet=null,focusReturn=null,googleReady=null;
  function close(){
    document.getElementById('familySheetBackdrop')?.remove();
    for(const selector of ['.topbar','.content','.bottom-nav'])document.querySelector(selector).inert=false;
    sheet=null;
    if(focusReturn?.isConnected)focusReturn.focus({preventScroll:true});else document.querySelector('[data-fh=settings]')?.focus({preventScroll:true});
  }
  function show(kind,data={}){
    if(!sheet)focusReturn=document.activeElement;
    sheet={kind,data};paint();
  }
  function error(message){const el=document.getElementById('fhError');el.hidden=false;el.textContent=message;}
  function field(label,name,value,type='text',attrs=''){return `<label>${label}<input class="go-field" name="${name}" type="${type}" value="${esc(value)}" ${attrs}></label>`;}
  function settingsContent(){
    const names=[...baseNames()];
    return {title:'Home & starting bases',eyebrow:'Family settings',body:`<p class="fh-intro">Your setup defaults. Go uses a caregiver's starting base when there is no earlier stop to travel from.</p><div>${names.map(name=>{const i=state.locations.findIndex(l=>l.name===name),l=state.locations[i];return `<div class="fh-settings-row"><div><strong>${esc(name)}</strong><small>${esc(address(l))}</small></div>${button('Edit address','base-address','fh-use',`data-index="${i}" aria-label="Edit ${esc(name)} address"`)}</div>`;}).join('')}</div><form id="fhForm" class="fh-form" style="margin-top:20px">${Object.entries(state.parentLocations).map(([name,place])=>`<label>${esc(name)}'s starting base<select class="go-field" name="base-${esc(name)}">${state.locations.map(l=>`<option value="${esc(l.name)}" ${l.name===place?'selected':''}>${esc(l.name)}</option>`).join('')}</select></label>`).join('')}</form><p class="fh-note">Sample household addresses are shown for this prototype.</p>`,foot:button('Save settings','settings-save','go-btn primary')};
  }
  function locationContent(){
    const {index=-1,settings=false}=sheet.data,l=state.locations[index],isBase=l&&baseNames().has(l.name);
    return {title:l?`Edit ${isBase?l.name:'location'}`:'Save a regular place',eyebrow:settings?'Family settings':'Your regular places',body:`${settings?button('‹ Settings','settings','fh-use'):''}<form id="fhForm" class="fh-form">${field('Place name','name',l?.name||'','text',`required maxlength="100" placeholder="e.g. Swim school" ${isBase?'readonly':''}`)}<div id="fhAddressSearch"><label for="fhAddress">Search address</label><input id="fhAddress" class="go-field" name="address" value="${esc(l?.address||'')}" placeholder="Start typing a place or address" autocomplete="off" role="combobox" aria-autocomplete="list" aria-expanded="false" aria-controls="fhAddressResults" required maxlength="250"><div id="fhAddressResults" class="fh-search-results" role="listbox" aria-label="Address suggestions"></div><p class="fh-note" id="fhAddressStatus" role="status">Sample address suggestions. You can also enter an address manually.</p></div></form><p class="fh-note">Drive time is calculated for each trip. No fixed travel time is needed here.</p>`,foot:button('Save location','location-save','go-btn primary')+(l&&!isBase?button('Remove location','remove-location','fh-secondary'):'')};
  }
  function templateContent(){
    const t=sheet.data.draft||(sheet.data.draft=sheet.data.id?C.normalize(state.templates.find(t=>t.id===sheet.data.id)):C.normalize({title:'',location:'',mode:'Drive',owner:'TBD',kids:[],time:'16:00',endTime:'17:00'}));
    return {title:sheet.data.id?'Edit template':sheet.data.suggestion?'Save this shortcut':'A handoff worth keeping',eyebrow:'Schedule template',body:`${sheet.data.suggestion?'<p class="fh-intro">We found this repeated in your schedule. Adjust the details, then save it as a reusable template.</p>':''}<form id="fhForm" class="fh-form">${field('Template name','title',t.title,'text','required maxlength="100" placeholder="e.g. School pickup"')}<div class="go-two">${field('Starts','time',t.time,'time','required')}${field('Ends','endTime',t.endTime,'time','required')}</div><label>Location<select class="go-field" name="location" required><option value="">Choose a saved place</option>${state.locations.map(l=>`<option value="${esc(l.name)}" ${t.location===l.name?'selected':''}>${esc(l.name)}</option>`).join('')}</select></label><fieldset><legend>Kids involved · choose one or more</legend><div class="fh-choices">${C.KIDS.map(k=>`<label class="fh-choice"><input type="checkbox" name="kids" value="${esc(k)}" ${t.kids.includes(k)?'checked':''}>${esc(k)}</label>`).join('')}</div></fieldset><details class="pn-disclosure"><summary>Caregiver & activity</summary><fieldset style="margin-top:12px"><legend>Usual caregiver</legend><div class="fh-choices">${['TBD',...AppStore.caregivers(),'Family'].map(n=>`<label class="fh-choice"><input type="radio" name="owner" value="${esc(n)}" ${t.owner===n?'checked':''}>${n==='TBD'?'Decide later':esc(n)}</label>`).join('')}</div></fieldset><label style="display:block;margin-top:14px">Activity type<select class="go-field" name="mode"><option value="Drive" ${t.mode!=='Home'?'selected':''}>Drive / pickup</option><option value="Home" ${t.mode==='Home'?'selected':''}>At home / no travel</option></select></label></details></form><p class="fh-note">Saving a template does not add an event. Choose its date in Plan.</p>`,foot:button('Save template','template-save','go-btn primary')+(sheet.data.id?button('Remove template','remove-template','fh-secondary'):'')};
  }
  function paint(){
    const content=sheet.kind==='remove'?{title:`Remove this ${sheet.data.target}?`,eyebrow:'Family',body:`<p class="fh-intro">${esc(sheet.data.name)} will be removed from your saved ${sheet.data.target==='template'?'templates':'places'}. Scheduled events stay in the plan.</p>`,foot:button('Remove','remove-confirm','go-btn primary')+button('Keep it','close','fh-secondary')}:sheet.kind==='settings'?settingsContent():sheet.kind==='location'?locationContent():templateContent();
    let back=document.getElementById('familySheetBackdrop');
    if(!back){back=document.createElement('div');back.id='familySheetBackdrop';back.className='go-sheet-backdrop';document.querySelector('.app').append(back);}
    back.innerHTML=`<section class="go-sheet" role="dialog" aria-modal="true" aria-labelledby="fhTitle"><div class="go-sheet-grip" aria-hidden="true"></div><header class="go-sheet-head"><div><p class="go-sheet-eyebrow">${content.eyebrow}</p><h2 id="fhTitle" tabindex="-1">${esc(content.title)}</h2></div>${button(icon('x'),'close','go-sheet-close','aria-label="Close family details"')}</header><div class="go-sheet-body">${content.body}</div><footer class="go-sheet-foot">${content.foot}<p id="fhError" class="fh-error" role="alert" hidden></p></footer></section>`;
    for(const selector of ['.topbar','.content','.bottom-nav'])document.querySelector(selector).inert=true;
    back.onclick=e=>{if(e.target===back)close();};
    back.onkeydown=e=>{
      if(e.key==='Escape'){e.preventDefault();close();return;}
      if(e.key!=='Tab')return;
      const focusables=[...back.querySelectorAll('button:not(:disabled),input,select,textarea,summary,gmp-place-autocomplete')].filter(x=>x.getClientRects().length),first=focusables[0],last=focusables.at(-1);
      if(e.shiftKey&&(document.activeElement===first||document.activeElement.id==='fhTitle')){e.preventDefault();last?.focus();}
      else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus();}
    };
    back.querySelector('form')?.addEventListener('submit',e=>{e.preventDefault();handle(`${sheet.kind}-save`,{});});
    window.refreshAppIcons();document.getElementById('fhTitle').focus({preventScroll:true});
    if(sheet.kind==='location')bindAddress();
  }
  async function googlePlaces(){
    if(window.google?.maps?.importLibrary)return google.maps.importLibrary('places');
    const key=document.querySelector('meta[name="google-maps-api-key"]')?.content;
    if(!key)return null;
    if(!googleReady)googleReady=new Promise((resolve,reject)=>{
      const script=document.createElement('script');
      const url=new URL('https://maps.googleapis.com/maps/api/js');url.search=new URLSearchParams({key,libraries:'places',v:'weekly',loading:'async',callback:'heliFamilyMapsReady'}).toString();
      window.heliFamilyMapsReady=()=>resolve(google.maps.importLibrary('places'));
      script.src=url.href;script.onerror=()=>reject(Error('Address search is unavailable.'));document.head.append(script);
    });
    return googleReady;
  }
  function bindAddress(){
    const input=document.getElementById('fhAddress'),results=document.getElementById('fhAddressResults'),status=document.getElementById('fhAddressStatus'),currentSheet=sheet;
    let matches=[],active=-1;
    function clear(){results.innerHTML='';input.setAttribute('aria-expanded','false');input.removeAttribute('aria-activedescendant');active=-1;}
    function select(i){const place=matches[i];if(!place)return;input.value=place.address;sheet.data.place=place;const name=document.querySelector('#fhForm [name=name]');if(!name.value.trim())name.value=place.name;clear();status.textContent='Sample address selected.';input.focus();}
    function search(){
      sheet.data.place=null;const q=input.value.trim().toLowerCase();clear();
      if(q.length<2){status.textContent='Type at least two characters to see sample addresses.';return;}
      matches=samplePlaces.filter(l=>`${l.name} ${l.address}`.toLowerCase().includes(q)).slice(0,5);
      results.innerHTML=matches.map((l,i)=>`<button type="button" role="option" id="fh-result-${i}" aria-selected="false" data-result="${i}"><strong>${esc(l.name)}</strong><small>${esc(l.address)}</small></button>`).join('');
      input.setAttribute('aria-expanded',String(matches.length>0));status.textContent=matches.length?`${matches.length} sample addresses. Choose one or keep typing.`:'No sample matches. You can save the address you enter.';
    }
    input.addEventListener('input',search);
    results.addEventListener('click',e=>{const option=e.target.closest('[data-result]');if(option)select(Number(option.dataset.result));});
    input.addEventListener('keydown',e=>{
      if(e.key==='Escape'&&results.children.length){e.preventDefault();e.stopPropagation();clear();return;}
      if(!matches.length||!results.children.length)return;
      if(['ArrowDown','ArrowUp'].includes(e.key)){e.preventDefault();active=(active+(e.key==='ArrowDown'?1:-1)+matches.length)%matches.length;[...results.children].forEach((el,i)=>el.setAttribute('aria-selected',String(i===active)));input.setAttribute('aria-activedescendant',`fh-result-${active}`);}
      if(e.key==='Enter'&&active>=0){e.preventDefault();select(active);}
    });
    googlePlaces().then(library=>{
      if(!library||sheet!==currentSheet||!input.isConnected)return;
      const widget=new library.PlaceAutocompleteElement({includedRegionCodes:['us']});widget.setAttribute('aria-label','Search Google Maps addresses');
      document.getElementById('fhAddressSearch').prepend(widget);input.removeAttribute('role');input.removeAttribute('aria-controls');input.removeAttribute('aria-autocomplete');input.removeEventListener('input',search);clear();
      status.textContent='Search Google Maps above, or enter an address below.';
      widget.addEventListener('gmp-select',async({placePrediction})=>{
        try{const place=placePrediction.toPlace();await place.fetchFields({fields:['id','displayName','formattedAddress','location']});if(sheet!==currentSheet)return;
          input.value=place.formattedAddress;sheet.data.place={placeId:place.id,address:place.formattedAddress,coordinates:place.location?.toJSON(),source:'google'};
          const name=document.querySelector('#fhForm [name=name]');if(!name.value.trim())name.value=place.displayName;status.textContent='Google Maps address selected.';
        }catch{status.textContent='Could not load this address. Try again or enter it manually.';}
      });
      input.addEventListener('input',()=>{sheet.data.place=null;});
      widget.addEventListener('gmp-error',()=>{status.textContent='Google address search is unavailable. You can still enter an address.';});
    }).catch(()=>{if(sheet===currentSheet)status.textContent='Google address search is unavailable. Sample suggestions are available.';});
  }
  function saveLocation(){
    const form=document.getElementById('fhForm');if(!form.reportValidity())return;
    const f=new FormData(form),name=f.get('name').trim(),addr=f.get('address').trim(),idx=sheet.data.index??-1,old=state.locations[idx];
    if(!name||!addr)return error('Enter a name and address.');
    if(state.locations.some((l,i)=>i!==idx&&l.name.toLowerCase()===name.toLowerCase()))return error('A place already uses this name. Choose another name.');
    const isBase=old&&baseNames().has(old.name);
    if(isBase&&!sheet.data.settings)return error('Change home and starting bases in Settings.');
    const place=sheet.data.place,unchanged=old?.address===addr;
    const record={...old,icon:old?.icon||place?.icon||'map-pin',name: isBase?old.name:name,address:addr,source:place?.source||(unchanged?old?.source:'manual'),placeId:place?.placeId||(unchanged?old?.placeId:undefined),coordinates:place?.coordinates||(unchanged?old?.coordinates:undefined)};
    const settings=sheet.data.settings;
    try{AppStore.updateLocation(idx,record);}catch(e){return error(e.message);}
    if(settings)show('settings');else close();toast('Location saved');
  }
  function saveTemplate(){
    const form=document.getElementById('fhForm');if(!form.reportValidity())return;
    const f=new FormData(form);
    try{
      const data=C.validate({...sheet.data.draft,title:f.get('title').trim(),time:f.get('time'),endTime:f.get('endTime'),location:f.get('location'),kids:f.getAll('kids'),owner:f.get('owner')||'TBD',mode:f.get('mode')||'Drive'});
      const idx=state.templates.findIndex(t=>t.id===sheet.data.id);
      const record={id:idx>=0?sheet.data.id:`tpl_${crypto.randomUUID()}`,title:data.title,time:data.time,endTime:data.endTime,kids:data.kids,kid:data.kid,location:data.location,owner:data.owner,duration:data.duration,mode:data.mode,category:data.category||'Family'};
      if(idx>=0)state.templates[idx]=record;else state.templates.push(record);
      saveState();state.familyActivePanel='events';refresh();close();toast('Template saved. Ready in Plan.');
    }catch(e){error(e.message);}
  }
  function handle(action,element){
    const data=element.dataset||{},index=data.index===undefined?-1:Number(data.index);
    if(action==='close')return close();
    if(action==='settings')return show('settings');
    if(action==='settings-save'){
      const f=new FormData(document.getElementById('fhForm'));
      for(const name of Object.keys(state.parentLocations)){const place=f.get(`base-${name}`);if(!state.locations.some(l=>l.name===place))return error('Choose a saved place for each starting base.');}
      AppStore.setBases(Object.fromEntries(AppStore.caregivers().map(name=>[name,f.get(`base-${name}`)])));
      refresh();close();toast('Home and starting bases saved');return;
    }
    if(action==='location'||action==='base-address'){
      if(index>=0&&baseNames().has(state.locations[index]?.name)&&action!=='base-address')return show('settings');
      return show('location',{index,settings:action==='base-address'});
    }
    if(action==='remove-location'){
      const index=sheet.data.index,place=state.locations[index];
      if(!place||baseNames().has(place.name))return;
      const events=window.HeliPlan?.records()||Object.values(state.eventsByDay).flat();
      if(events.some(e=>e.location===place.name)||state.templates.some(t=>t.location===place.name))return error('This place is used in your schedule or templates. Change those references before removing it.');
      return show('remove',{target:'location',index,name:place.name});
    }
    if(action==='remove-template')return show('remove',{target:'template',id:sheet.data.id,name:sheet.data.draft.title});
    if(action==='remove-confirm'){
      if(sheet.data.target==='template')state.templates=state.templates.filter(t=>t.id!==sheet.data.id);
      else {try{AppStore.removeLocation(sheet.data.index);}catch(e){return error(e.message);}}
      saveState();refresh();close();toast('Removed from Family');return;
    }
    if(action==='location-save')return saveLocation();
    if(action==='template')return show('template',{id:data.id});
    if(action==='template-save')return saveTemplate();
    if(action==='suggestion'){const idea=suggestions()[index];if(idea)show('template',{draft:idea.draft,suggestion:true});return;}
    if(action==='use'){window.HeliPlan?.useTemplate(data.id);return;}
  }
  document.addEventListener('click',e=>{const button=e.target.closest('[data-fh]');if(button)handle(button.dataset.fh,button);});
  AppStore.registerDraft(()=>sheet?.data?.draft);
  AppStore.subscribe(reason=>{if(reason==='people'&&sheet)close();});
  window.FamilyHub={locations,templates,templateList,renderHero,kidsStats,crew,close,openSettings:()=>show('settings')};
  // Legacy callers (Map and future entry points) share the same editor.
  window.famOpenAddLocation=()=>show('location');
  window.famOpenAddTemplate=()=>show('template');
  state.templates=templateList();
  renderFamilyScreen();
})();
