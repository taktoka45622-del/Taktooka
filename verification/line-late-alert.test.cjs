const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync(require('node:path').join(__dirname,'../src/app.js'),'utf8');
const block=source.slice(source.indexOf('let lateLineRows=[]'),source.indexOf('async function loadLines()'));
function el(){return {children:[],append(...v){this.children.push(...v)},replaceChildren(...v){this.children=v},classList:{toggle(){}}};}
const elements={lineAlarm:el()};let rows=[{id:'run:departure',run_id:'run',line_id:'line',stage:'departure',passenger_name:'راكب',due_at:'today'}],editable=true,fail=false,armed=0,stopped=0,fetcher;
const ctx=vm.createContext({window:{},dialogMode:null,dialogEpoch:0,Object,Error,renderCache:{changed:()=>true},lineRunNames:{},canView:()=>true,canEdit:()=>editable,$:id=>elements[id],text:(tag,value)=>Object.assign(el(),{textContent:value}),dates:x=>x,localPhone:x=>x,record:(title,facts,controls)=>({title,facts,controls}),button:(label,fn)=>({label,fn}),run:fn=>fn(),status:()=>{},trackLine:async()=>{},openDetail:()=>{elements.lateLineList=null;const body=el();body.append=(...v)=>v.forEach(x=>{if(x.id)elements[x.id]=x});return body},dashboardRpc:async(name,action)=>{assert.equal(name,'tkt_line_alerts');if(action==='resolve'){if(fail)throw Error('offline');rows=[];return {resolved:true}}return rows},createEmergencyAlarm:opts=>{fetcher=opts.fetchCases;return {arm(){armed++},refresh:()=>fetcher(),resolved(){stopped++}}}});
(async()=>{
 vm.runInContext(block,ctx);
 await elements.lineAlarm.onclick();
 assert.equal(armed,1);assert.equal(ctx.dialogMode,'late-lines');
 assert.equal(elements.lateLineList.children[0].controls[1].label,'تم التعامل');
 fail=true;await assert.rejects(ctx.resolveLateLine(rows[0]));assert.equal(stopped,0);assert.equal(rows.length,1);
 fail=false;await ctx.resolveLateLine(rows[0]);assert.equal(stopped,1);assert.equal(rows.length,0);assert.match(elements.lateLineList.children[0].textContent,/ماكو خطوط/);
 rows=[{id:'new:arrival',run_id:'new',stage:'arrival'}];editable=false;await fetcher();assert.equal(elements.lateLineList.children[0].controls.length,1);await assert.rejects(ctx.resolveLateLine(rows[0]),/PERMISSION_DENIED/);
 console.log('PASS: click opens late lines, handling control, failed save preserves alarm, saved case stops, empty state, read-only permissions');
})().catch(e=>{console.error(e);process.exitCode=1});
