const {test}=require('node:test');
const assert=require('node:assert/strict');
const {create}=require('../app-store.js');
const Plan=require('../plan-core.js');
const Family=require('../family-core.js');
function fixture(){
  const map=new Map(),storage={getItem:k=>map.get(k)||null,setItem:(k,v)=>map.set(k,v),removeItem:k=>map.delete(k)};
  const event=(id,date='2026-08-03')=>({id,date,title:'Practice',owner:'Alex',lead:'Alex',kids:['Sam'],kid:'Sam',time:'16:00',endTime:'17:00',location:'School',mode:'Drive',locked:true,tentative:true});
  const locations=[{name:'Home',address:'1 Main'},{name:'Work',address:'2 Main'},{name:'School',address:'3 Main'}];
  const state={people:[{id:'a',name:'Alex',kind:'caregiver',relationship:'Father',color:'#123456'},{id:'b',name:'Jo',kind:'caregiver',relationship:'Other'},{id:'c',name:'Sam',kind:'child',relationship:'Child'}],locations:structuredClone(locations),homePlaceName:'Home',parentLocations:{Alex:'Work',Jo:'Home'},currentUser:'Alex',goCrewFilter:'Alex',goKidFilter:'Sam',buffer:12,trafficMode:false,dinnerProtection:false,eventsByDay:{0:[event(1)]},templates:[event('tpl')],goDraft:event('draft'),plan:{future:[event(2,'2026-08-10')],calendar:{exports:{1:'sig',2:'sig',ghost:'sig'}},priorities:{},reviewed:{}}};
  const app=create(state,{storage,keys:{events:'events',locations:'locations',settings:'settings',templates:'templates',rules:'rules'},defaultLocations:locations,routes:{Home:{School:20,Work:10},Work:{School:10,Home:10},School:{Home:20,Work:10}}});
  return {app,state,event,map,storage};
}
test('removing a caregiver clears current, future, template and open-draft assignments and preferences, and persists them',()=>{
  const {app,state,map}=fixture();const draft={...state.templates[0]};app.registerDraft(()=>draft);app.removePerson('a');
  assert.deepEqual(app.caregivers(),['Jo']);
  for(const e of [...app.records(),...state.templates,state.goDraft,draft]){assert.equal(e.owner,'TBD');assert.equal(e.lead,'TBD');assert.equal(e.locked,false);assert.equal(e.tentative,false);}
  assert.equal(state.currentUser,'All');assert.equal(state.goCrewFilter,null);assert.equal(state.parentLocations.Alex,undefined);
  assert.equal(JSON.parse(map.get('heli-pad-plan-v1')).future[0].owner,'TBD');
  assert.equal(JSON.parse(map.get('templates'))[0].owner,'TBD');
});
test('rename preserves person identity and cascades names containing punctuation through every relationship',()=>{
  const {app,state}=fixture();app.renamePerson('a',"Alex O'Neill");
  assert.equal(state.people[0].id,'a');assert.equal(state.currentUser,"Alex O'Neill");assert.equal(state.parentLocations["Alex O'Neill"],'Work');
  for(const e of [...app.records(),...state.templates,state.goDraft])assert.equal(e.owner,"Alex O'Neill");
  app.renamePerson('c','Casey');for(const e of [...app.records(),...state.templates,state.goDraft])assert.deepEqual(e.kids,['Casey']);
  assert.throws(()=>app.renamePerson('a','jo'));assert.throws(()=>app.renamePerson('a','All'));
});
test('removing the only selected child leaves no children rather than silently assigning everyone',()=>{
  const {app,state}=fixture();app.removePerson('c');
  for(const e of [...app.records(),...state.templates,state.goDraft]){assert.deepEqual(e.kids,[]);assert.equal(e.kid,'');}
  assert.equal(state.goKidFilter,'all');Family.configure({children:app.children});
  assert.deepEqual(Family.normalize(state.templates[0]).kids,[]);
  assert.throws(()=>Family.validate(state.templates[0]),/child|kid/i);
});
test('role changes use the same cleanup rules and new caregivers have a saved starting base',()=>{
  const {app,state}=fixture();app.setPersonRole('a','Child');assert.equal(app.records()[0].owner,'TBD');assert(!app.caregivers().includes('Alex'));assert(app.children().includes('Alex'));
  app.setPersonRole('c','Other');assert.deepEqual(app.records()[0].kids,[]);assert.equal(state.parentLocations.Sam,'Home');
  const p=app.addPerson('caregiver');assert(app.caregivers().includes(p.name));assert.equal(state.parentLocations[p.name],'Home');
});
test('place rename cascades across dates and templates, preserves route identity across reload, and moving invalidates estimates',()=>{
  const {app,state,storage}=fixture();app.updateLocation(2,{name:'New School',address:'3 Main'});
  for(const e of [...app.records(),...state.templates,state.goDraft])assert.equal(e.location,'New School');
  assert.equal(app.travel('Work','New School',960),10);
  const reloaded=create({...structuredClone(state),plan:undefined},{storage,routes:{Work:{School:10}}});
  assert.equal(reloaded.travel('Work','New School',960),10);
  app.updateLocation(2,{name:'New School',address:'99 Elsewhere'});assert.equal(app.travel('Work','New School',960),null);
  assert.throws(()=>app.removeLocation(2),/used/);assert.throws(()=>app.removeLocation(0),/home/i);
});
test('home and bases are one source and feed the shared planning calculation',()=>{
  const {app,state}=fixture();app.setHomeAddress('9 New Street');assert.equal(state.homeAddress,'9 New Street');assert.equal(state.locations[0].address,'9 New Street');assert.equal(app.travel('Home','School',480),null);
  app.setBases({Alex:'School',Jo:'Work'});assert.equal(Plan.candidate(app.records()[0],'Alex',app.records(),app.planningOptions()).eta,0);
  assert.throws(()=>app.setBases({Deleted:'Work'}));
});
test('buffer zero, traffic adjustment and dinner protection use the same settings on every date',()=>{
  const {app,state,event}=fixture();app.setSetting('buffer',0);
  const calc=()=>Plan.analyze(app.records(),app.planningOptions())[0];assert.equal(calc().detail.leave,950);
  app.setSetting('trafficMode',true);assert.equal(calc().detail.eta,12);assert.equal(calc().detail.leave,948);
  app.setSetting('buffer',45);assert.equal(calc().detail.leave,903);assert.throws(()=>app.setSetting('buffer',46));
  state.plan.future=[{...event(8,'2026-08-10'),time:'18:00',endTime:'19:00',mode:'Home'}];app.setSetting('dinnerProtection',true);
  assert(Plan.analyze(state.plan.future,app.planningOptions())[0].risks.some(r=>r.type==='dinner'));
  app.setSetting('dinnerProtection',false);assert(!Plan.analyze(state.plan.future,app.planningOptions())[0].risks.some(r=>r.type==='dinner'));
});
test('empty roster produces missing assignments without recommending removed caregivers',()=>{
  const {app}=fixture();app.removePerson('a');app.removePerson('b');assert.deepEqual(app.caregivers(),[]);
  const result=Plan.summary(app.records(),app.planningOptions());assert.equal(result.missing,2);assert.deepEqual(Plan.loads(app.records(),app.planningOptions()),{});assert.deepEqual(Plan.proposals(app.records(),app.planningOptions()).changes,[]);
});
test('schedule reset clears future events and review/export metadata; account reset preserves unrelated origin data',()=>{
  const {app,state,map}=fixture();assert.equal(state.plan.calendar.exports.ghost,undefined);
  app.resetSchedule({0:[]});assert.deepEqual(app.records(),[]);assert.deepEqual(state.plan.reviewed,{});assert.deepEqual(state.plan.calendar.exports,{});
  map.set('unrelated','keep');app.clearData();assert.deepEqual([...map.entries()],[['unrelated','keep']]);
});
test('time zone affects the live clock and rejects invalid input',()=>{
  const {app}=fixture();app.setSetting('timeZone','America/Detroit');assert.equal(app.clock(new Date('2026-08-03T12:00:00Z')).minutes,480);
  app.setSetting('timeZone','America/Los_Angeles');assert.equal(app.clock(new Date('2026-08-03T12:00:00Z')).minutes,300);assert.throws(()=>app.setSetting('timeZone','Invalid/Zone'));
});
