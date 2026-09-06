const {test}=require('node:test');
const assert=require('node:assert/strict');
const C=require('../plan-core.js');
const options={routes:{Home:{School:15,Field:20},School:{Home:15,Field:10},Field:{Home:20,School:10}},origins:{Mom:'Home',Dad:'Home',Nani:'Home',Grandma:'Home'},buffer:12};
const event=(overrides={})=>({id:1,date:C.BASE_WEEK,title:'Pickup',time:'15:00',endTime:'15:30',location:'School',owner:'Mom',mode:'Drive',kids:['Soni'],...overrides});
test('readiness partitions ready, unassigned and tentative without treating a review as resolution',()=>{
 const result=C.summary([event(),event({id:2,date:'2026-08-04',owner:'TBD'}),event({id:3,date:'2026-08-05',tentative:true})],options);
 assert.deepEqual([result.ready,result.missing,result.review,result.total],[1,1,1,3]);
});
test('candidate considers the next journey and rejects an assignment that would make it late',()=>{
 const a=event(),b=event({id:2,title:'Practice',location:'Field',time:'15:35',endTime:'16:30'});
 const c=C.candidate(a,'Mom',[a,b],options);
 assert.equal(c.conflict,true);assert.equal(c.onwardSlack,-17);
 assert.equal(C.candidate(a,'Dad',[a,b],options).conflict,false);
});
test('zero buffer is respected and a tight window differs from an overlap',()=>{
 const a=event({time:'14:00',endTime:'14:30'}),b=event({id:2,location:'Field',time:'14:45',endTime:'15:30'});
 const c=C.candidate(b,'Mom',[a,b],{...options,buffer:0});
 assert.equal(c.slack,5);assert.equal(c.conflict,false);
 assert.equal(C.analyze([a,b],{...options,buffer:0})[1].risks[0].type,'tight');
});
test('unknown routes stay flagged and never receive a made-up estimate',()=>{
 const e=event({location:'Unknown place'}),r=C.analyze([e],options)[0];
 assert.equal(r.detail.eta,null);assert.equal(r.status,'review');
 assert.equal(C.proposals([e],options).changes.length,0);
});
test('non-travel tasks retain their caregiver and do not contribute driving minutes',()=>{
 const e=event({kind:'cook',mode:'Home',location:'Home'});
 assert.equal(C.analyze([e],options)[0].owner,'Mom');
 assert.equal(C.loads([e],options).Mom,0);
});
test('rebalance preserves locks, tentative assignments and completion, and introduces no overlaps',()=>{
 const all=[event({owner:'TBD'}),event({id:2,date:'2026-08-04',locked:true}),event({id:3,date:'2026-08-05',tentative:true}),event({id:4,date:'2026-08-06',done:true})];
 const p=C.proposals(all,options);
 assert.equal(p.changes.length,1);assert.equal(p.changes[0].id,1);
 assert.equal(C.analyze(p.events,options).filter(e=>e.risks.some(r=>r.type==='overlap')).length,0);
 assert.equal(all[0].owner,'TBD');
});
test('recurrence uses actual dates across months and years without recycling the base week',()=>{
 const r=C.occurrences({...event({date:'2026-12-28'}),repeat:'weekly',count:3});
 assert.deepEqual(r.map(e=>e.date),['2026-12-28','2027-01-04','2027-01-11']);
 assert.equal(C.monday('2027-01-03'),'2026-12-28');
 assert.equal(C.daysBetween(C.BASE_WEEK,'2026-08-10'),7);
 assert.throws(()=>C.occurrences({...event(),repeat:'weekly',count:53}));
 assert.throws(()=>C.occurrences({...event(),endTime:'14:00'}));
});
test('calendar pull is idempotent and preserves private overlays on schedule updates',()=>{
 const existing=event({calendarId:'g:1',done:true,notes:'Private note',owner:'Dad',buffer:9});
 const update={...existing,title:'Changed pickup',owner:'TBD',done:false,notes:''};
 const pulled=C.pull([existing],[update]);
 assert.equal(pulled[0].title,'Changed pickup');assert.equal(pulled[0].owner,'Dad');
 assert.equal(pulled[0].done,true);assert.equal(pulled[0].notes,'Private note');
 assert.equal(C.pull(pulled,[update]).length,1);
 assert.deepEqual(Object.keys(C.schedule(existing)),['date','title','time','endTime','location']);
 const newEvent=C.pull([],[update])[0];assert.equal(newEvent.owner,'TBD');assert.equal(newEvent.done,false);
});
test('dinner goals flag crossing trips only on selected dates',()=>{
 const e=event({time:'18:40',endTime:'19:30'}),p={...options,priorities:{[C.BASE_WEEK]:{enabled:true,days:[0],time:'18:30'}}};
 assert.equal(C.analyze([e],p)[0].risks.some(r=>r.type==='dinner'),true);
 assert.equal(C.analyze([event({...e,date:'2026-08-04'})],p)[0].risks.some(r=>r.type==='dinner'),false);
});
