const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
let events=[],changes=0;
class Node{constructor(tag){this.tagName=tag;this.children=[];this.dataset={};this.hidden=true;this.handlers={};this.classList={toggle(){},add(){}};}append(...nodes){for(const n of nodes){n.remove();this.children.push(n);n.parentNode=this;}}remove(){if(this.parentNode){const p=this.parentNode;p.children.splice(p.children.indexOf(this),1);this.parentNode=null;}}insertBefore(n,ref){n.remove();this.children.splice(this.children.indexOf(ref),0,n);n.parentNode=this;}replaceChild(n,old){n.remove();const i=this.children.indexOf(old);assert(i>=0);this.children[i]=n;n.parentNode=this;old.parentNode=null;}closest(){return null;}setAttribute(){}addEventListener(n,f){this.handlers[n]=f;}showModal(){this.open=true;}close(){this.open=false;events.push(()=>this.handlers.close?.());}}
const body=new Node('body'),document={body,createElement:t=>new Node(t),createComment:()=>new Node('comment')};
const ctx=vm.createContext({document,requestAppBack:f=>f(),navigationChanged:()=>changes++,navigationWillChange(){}});
const src=fs.readFileSync(require('node:path').join(__dirname,'../src/screen-navigation.js'),'utf8').replace(/^import[^\n]*\n/,'').replaceAll('export ','');vm.runInContext(src,ctx);
const parent=new Node('div'),a=new Node('div'),b=new Node('div');a.id='a';b.id='b';body.append(parent);parent.append(a);a.append(b);let closed=0;
ctx.openSectionScreen(a,'A',()=>closed++);ctx.openSectionScreen(b,'B',()=>closed++);assert.equal(ctx.getSectionScreens().length,2);
ctx.closeAllSectionScreens();assert.equal(ctx.getSectionScreens().length,0);assert.equal(a.parentNode,parent);assert.equal(b.parentNode,a);assert.equal(closed,2);
ctx.openSectionScreen(a,'A again');for(const e of events)e();assert.equal(ctx.getSectionScreens().length,1);assert.equal(closed,2);assert.equal(a.hidden,false);
ctx.closeSectionScreen(a);assert.equal(a.parentNode,parent);assert.equal(ctx.getSectionScreens().length,0);
console.log('PASS: nested sections restore synchronously, original DOM placement, stale close event does not erase reopened screen');
