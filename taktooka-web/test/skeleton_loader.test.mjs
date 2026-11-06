import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const source=await readFile(new URL('../dashboard/skeleton.js',import.meta.url),'utf8');
const {createPageLoader}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
class Element {
  constructor(){this.dataset={};this.attributes={};this.children=[];}
  setAttribute(k,v){this.attributes[k]=v;}
  removeAttribute(k){delete this.attributes[k];}
  append(...nodes){for(const node of nodes){node.parent=this;this.children.push(node);}}
  remove(){this.parent.children=this.parent.children.filter(x=>x!==this);}
}
const document={createElement:()=>new Element()};
test('first read shows skeleton and deduplicates concurrent reads',async()=>{
  const page=new Element(),load=createPageLoader(document);let release,calls=0;
  const request=()=>{calls++;return new Promise(r=>release=r);};
  const a=load(page,request),b=load(page,request);
  assert.equal(a,b);assert.equal(page.attributes['aria-busy'],'true');
  assert.equal(page.children.length,1);
  await Promise.resolve();assert.equal(calls,1);release('ready');
  assert.equal(await a,'ready');assert.equal(page.children.length,0);
  assert.equal(page.attributes['aria-busy'],undefined);
  let finish;
  const refresh=load(page,()=>new Promise(r=>finish=r));
  assert.equal(page.children.length,0);
  await Promise.resolve();finish();await refresh;
});
test('failed initial read clears placeholders and allows retry',async()=>{
  const page=new Element(),load=createPageLoader(document);
  await assert.rejects(load(page,()=>{throw Error('offline');}),/offline/);
  assert.equal(page.children.length,0);
  assert.equal(page.dataset.initialLoading,undefined);
  const retry=load(page,()=>42);
  assert.equal(page.children.length,1);assert.equal(await retry,42);
});
test('pages maintain independent loading and refresh state',async()=>{
  const a=new Element(),b=new Element(),load=createPageLoader(document);let release;
  const pending=load(a,()=>new Promise(r=>release=r));
  await load(b,()=>1);
  assert.equal(a.children.length,1);assert.equal(b.children.length,0);
  release();await pending;
});
