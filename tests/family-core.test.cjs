const {test}=require('node:test');
const assert=require('node:assert/strict');
const C=require('../family-core.js');
const template={id:'t1',title:'School pickup',time:'15:00',endTime:'15:30',kids:['Maya','Soni'],location:'School',owner:'Dad',mode:'Drive'};
test('legacy templates gain times and expand All to actual children without mutating the saved input',()=>{
 const old={id:'tpl_1',title:'School',kid:'All',duration:30,location:'School'};
 const t=C.normalize(old);
 assert.deepEqual(t.kids,['Soni','Maya','Noah']);assert.equal(t.time,'07:35');assert.equal(t.endTime,'08:05');assert.equal(old.time,undefined);
});
test('template validates children and same-day time range',()=>{
 assert.throws(()=>C.validate({...template,kids:[]}));
 assert.throws(()=>C.validate({...template,endTime:'14:00'}));
 assert.throws(()=>C.validate({...template,time:'15:99'}));
 assert.throws(()=>C.validate({...template,endTime:'24:00'}));
 assert.equal(C.validate(template).duration,30);
});
test('Plan draft preserves multiple kids and time, picks the requested date, and does not carry completion or recurrence',()=>{
 const draft=C.eventDraft({...template,done:true,seriesId:'old',repeat:'weekly'},'2027-01-04');
 assert.equal(draft.date,'2027-01-04');assert.equal(draft.time,'15:00');assert.equal(draft.endTime,'15:30');
 assert.deepEqual(draft.kids,['Soni','Maya']);assert.equal(draft.done,undefined);assert.equal(draft.seriesId,undefined);assert.equal(draft.repeat,'none');
 draft.kids.push('Noah');assert.equal(template.kids.length,2);
});
test('suggestions group actual identical patterns, avoid saved templates, and leave mixed caregivers undecided',()=>{
 const events=[{...template,id:1},{...template,id:2,owner:'Mom'},{...template,id:3,time:'16:00',endTime:'16:30'}];
 const list=C.suggestions(events,[]);assert.equal(list.length,1);assert.equal(list[0].count,2);assert.equal(list[0].draft.owner,'TBD');
 assert.equal(C.suggestions(events,[template]).length,0);
});
test('suggestions do not combine different children, locations, or all-day events',()=>{
 assert.equal(C.suggestions([template,{...template,kids:['Noah']},{...template,location:'Field'},{...template,allDay:true}],[]).length,0);
});
