import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {JSDOM} from 'jsdom';
import {createCompanyPage,companyIndicators,companyCsv,baghdadDay} from '../src/company-performance.js';
const data={from:'2026-10-10',to:'2026-10-13',previous_from:'2026-10-06',previous_to:'2026-10-09',server_now:'2026-10-13T12:00:00Z',revenue:15000,expenses:2000,previous_revenue:10000,payments:3,paying_captains:2,first_paid_captains:1,lifetime_revenue:45000,fee:5000,profiles:{active:2,expired:1,never:1,expiring_soon:1},rides:{requested:10,completed:6,cancelled:2,completed_fares:50000},wallets:{customer_funds:400000,captain_funds:300000},lines:{active:2},current_operations:{pending:1,long_wait:1},daily:[{day:'2026-10-10',revenue:5000,expenses:0},{day:'2026-10-11',revenue:10000,expenses:2000}],expiring:[]};
function setup(handler,editable=true){
 const dom=new JSDOM(fs.readFileSync(new URL('../src/index.html',import.meta.url),'utf8'),{url:'https://example.test'}),document=dom.window.document,calls=[];
 const rpc=async(action,args)=>{calls.push({action,args});return handler?handler(action,args):action==='report'?{...data,...args}:{items:[],has_more:false};};
 const page=createCompanyPage({document,rpc,money:n=>`${Number(n).toLocaleString('en-US')} د.ع`,dates:v=>v,canEdit:()=>editable,canOpenProfile:()=>false,openProfile:()=>{},confirmVoid:()=>null});
 document.getElementById('companyFrom').value=data.from;document.getElementById('companyTo').value=data.to;
 return {dom,document,page,calls};
}
test('profit includes only subscription revenue minus recorded expenses',()=>{
 assert.deepEqual(companyIndicators(data),{revenue:15000,expenses:2000,net:13000,growth:50,completion:60,cancellation:20});
 assert.equal(companyIndicators({...data,previous_revenue:0}).growth,null);
 assert.equal(companyIndicators({...data,expenses:20000}).net,-5000);
 assert.equal(baghdadDay(new Date('2026-10-10T21:00:00Z')),'2026-10-11');
 const csv=companyCsv(data);assert.match(csv,/"الصافي بعد المصاريف المسجلة","13000"/);assert.match(csv,/ليست ربح الشركة/);
});
test('company metrics separate wallet funds and fares and reject injected HTML',async()=>{
 const v=setup((action,args)=>action==='report'?{...data,...args}:{items:[{name:'<img src=x onerror=alert(1)>',amount:5000,created_at:'2026-10-10',expires_at:'2026-10-17'}],has_more:false});
 await v.page.load();assert.equal(v.document.getElementById('companyRevenue').textContent,'15,000 د.ع');assert.match(v.document.getElementById('companyFinancials').textContent,/13,000/);assert.equal(v.document.getElementById('companyCustomerFunds').textContent,'400,000 د.ع');assert.equal(v.document.querySelectorAll('#companyRecords img').length,0);assert.match(v.document.getElementById('companyRecords').textContent,/<img/);
 v.page.reset();assert.equal(v.page.getReport(),null);assert.equal(v.document.getElementById('companyRecords').textContent,'');assert.equal(v.document.getElementById('companyExport').disabled,true);v.dom.window.close();
});
test('view-only finance permission prevents expense submission',async()=>{
 const v=setup(null,false);await v.page.load();assert.equal(v.document.getElementById('companyExpenseSave').disabled,true);await v.document.getElementById('companyExpenseForm').onsubmit({preventDefault(){}});assert.equal(v.calls.some(c=>c.action==='expense_add'),false);v.dom.window.close();
});
test('ambiguous expense response reuses its id on retry',async()=>{
 let attempts=0;const v=setup((action,args)=>{if(action==='expense_add'){if(++attempts===1)throw new Error('network lost');return {id:args.id};}return action==='report'?{...data,...args}:{items:[],has_more:false};});
 for(const [id,value]of [['companyExpenseDate','2026-10-11'],['companyExpenseAmount','2000'],['companyExpenseDescription','Maps bill']])v.document.getElementById(id).value=value;
 const form=v.document.getElementById('companyExpenseForm');await form.onsubmit({preventDefault(){}});await form.onsubmit({preventDefault(){}});const writes=v.calls.filter(c=>c.action==='expense_add');assert.equal(writes.length,2);assert.equal(writes[0].args.id,writes[1].args.id);assert.equal(writes[0].args.amount,2000);v.dom.window.close();
});
test('late response cannot overwrite a newly selected period',async()=>{
 let release;const gate=new Promise(resolve=>release=resolve);const v=setup(async(action,args)=>{if(action!=='report')return {items:[],has_more:false};if(args.from==='2026-10-10')await gate;return {...data,...args,revenue:args.from==='2026-10-10'?15000:20000};});
 const old=v.page.load();v.document.getElementById('companyFrom').value='2026-10-11';await v.page.load();release();await old;assert.equal(v.page.getReport().from,'2026-10-11');assert.equal(v.document.getElementById('companyRevenue').textContent,'20,000 د.ع');v.dom.window.close();
});
test('pagination appends records without changing report totals',async()=>{
 const v=setup((action,args)=>action==='report'?{...data,...args}:{items:Array.from({length:args.offset?10:50},(_,i)=>({id:args.offset+i,name:'Captain',amount:5000})),has_more:!args.offset});
 await v.page.load();await v.document.getElementById('companyMore').onclick();assert.equal(v.document.querySelectorAll('.company-record').length,60);assert.equal(v.document.getElementById('companyRevenue').textContent,'15,000 د.ع');assert.equal(v.calls.at(-1).args.offset,50);v.dom.window.close();
});
