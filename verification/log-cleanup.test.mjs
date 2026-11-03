import assert from 'node:assert/strict';
import {createServerMonitor} from '../src/server-monitor.js';
class Element {
 constructor(tag){this.tag=tag;this.children=[];this.disabled=false;this.attributes={};this.textContent='';}
 append(...children){this.children.push(...children);}
 replaceChildren(...children){this.children=children;}
 setAttribute(k,v){this.attributes[k]=v;}
 get text(){return this.textContent+this.children.map(c=>c.text).join('');}
 all(){return [this,...this.children.flatMap(c=>c.all())];}
}
const root=new Element('section'),document={getElementById:()=>root,createElement:t=>new Element(t)};
const state={enabled:false,last_deleted:0,total_deleted:0,log_bytes:614014976,batch_limit:20000};
let fail=false,resolveClean,pending;
const calls=[];
const monitor=createServerMonitor({document,run:f=>(pending=f()),rpc:async()=>({provider:{plan:'free'},live:{database_bytes:1}}),cleanupRpc:async(action,data)=>{
 calls.push([action,data]);if(fail)throw Error('offline');
 if(action==='configure')state.enabled=data.enabled;
 if(action==='clean'){await new Promise(resolve=>resolveClean=resolve);state.last_deleted=20000;state.total_deleted+=20000;}
 return structuredClone(state);
}});
const button=text=>root.all().find(e=>e.tag==='button'&&e.textContent===text);
await monitor.load();assert(button('تنظيف الآن'));assert(button('تفعيل التنظيف الدوري'));
button('تفعيل التنظيف الدوري').onclick();await pending;assert(state.enabled);assert(button('إيقاف التنظيف الدوري'));
const clean=button('تنظيف الآن');clean.onclick();assert(clean.disabled);resolveClean();await pending;
assert.match(root.text,/20,000/);assert.match(root.text,/دفعة كاملة/);assert.equal(calls.filter(([a])=>a==='clean').length,1);
button('إيقاف التنظيف الدوري').onclick();await pending;assert(!state.enabled);
fail=true;button('تنظيف الآن').onclick();await assert.rejects(pending);assert(!button('تنظيف الآن').disabled);assert.match(root.text,/تعذر تنفيذ/);
await monitor.load();assert.match(root.text,/تعذر تحميل إعدادات/);assert(!button('تنظيف الآن'));
fail=false;await monitor.load();assert(button('تنظيف الآن'));assert.match(root.text,/لا يحذف الرحلات/);
console.log('PASS: configure, clean, pending controls, batch message, error recovery and scope text');
