import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createAccountAdmin} from '../src/account-admin.js';
class Element{
 constructor(tag){this.tagName=tag;this.children=[];this.value='';this.checked=false;this.disabled=false;}
 append(...nodes){this.children.push(...nodes);}replaceChildren(...nodes){this.children=nodes;}setAttribute(){}
}
function fixture(info={}){
 const ids=new Map();const document={getElementById:id=>{if(!ids.has(id))ids.set(id,new Element('div'));return ids.get(id);},createElement:tag=>new Element(tag),createTextNode:s=>s};
 const body=new Element('div'),calls=[];const text=(tag,s)=>Object.assign(new Element(tag),{textContent:s});
 const admin=createAccountAdmin({document,rpc:async()=>({kind:'user',id:'target',name:'Test',account_type:'customer',status:'ready',blockers:[],fingerprint:'f',...info}),invoke:async data=>{calls.push(data);return {ok:true};},openDetail:(title,route)=>{calls.push(route);return body;},button:(label,fn)=>Object.assign(text('button',label),{onclick:fn}),text,record:()=>new Element('article'),money:String,localPhone:String,run:fn=>fn(),notify:()=>{},onDeleted:async()=>{},canManage:()=>true});return {admin,body,calls};
}
test('delete requires exact word and checked confirmation',async()=>{const f=fixture();await f.admin.open('user','target');const form=f.body.children.find(e=>e.tagName==='form');const [label,checkLabel,submit]=form.children;const input=label.children[0],check=checkLabel.children[0];assert.equal(submit.disabled,true);input.value='حذف';input.oninput();assert.equal(submit.disabled,true);check.checked=true;check.onchange();assert.equal(submit.disabled,false);input.value='احذف';input.oninput();assert.equal(submit.disabled,true);});
test('blocked account has reason and no delete form',async()=>{const f=fixture({blockers:['LAST_OWNER']});await f.admin.open('user','target');assert.ok(!f.body.children.some(e=>e.tagName==='form'));assert.ok(f.body.children.some(e=>e.className==='notice'));});
test('completed account cannot submit again',async()=>{const f=fixture({status:'completed'});await f.admin.open('user','target');assert.ok(!f.body.children.some(e=>e.tagName==='form'));assert.equal(f.calls.length,1);});
test('valid confirmation sends canonical target and fingerprint',async()=>{const f=fixture({id:'canonical'});await f.admin.open('exchange','legacy');const form=f.body.children.find(e=>e.tagName==='form');const [label,checkLabel,submit]=form.children;label.children[0].value='حذف';checkLabel.children[0].checked=true;checkLabel.children[0].onchange();form.onsubmit({preventDefault(){}});await new Promise(resolve=>setImmediate(resolve));assert.deepEqual(f.calls[1],{kind:'user',id:'canonical',fingerprint:'f',confirm:'DELETE_ACCOUNT'});assert.equal(f.calls[0].name,'accountDelete');});
