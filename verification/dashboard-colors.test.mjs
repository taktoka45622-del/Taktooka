import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const css=readFileSync(new URL('../src/dashboard-theme.css',import.meta.url),'utf8');
const luminance=hex=>(hex.length===4?'#'+[...hex.slice(1)].map(c=>c+c).join(''):hex).match(/[a-f\d]{2}/gi).map(s=>{const c=parseInt(s,16)/255;return c<=.04045?c/12.92:((c+.055)/1.055)**2.4}).reduce((s,v,i)=>s+v*[.2126,.7152,.0722][i],0);
const contrast=(a,b)=>{const x=luminance(a),y=luminance(b);return(Math.max(x,y)+.05)/(Math.min(x,y)+.05)};
for(const block of css.matchAll(/:root(?:\[data-theme=dark\])?\{([^}]+)\}/g)){
 const tokens=Object.fromEntries([...block[1].matchAll(/--([\w-]+):(#[a-f\d]{6}|#[a-f\d]{3})/gi)].map(m=>[m[1],m[2]]));
 for(const [text,bg] of [['ink','surface'],['ink','raised'],['muted','surface'],['muted','raised'],['accent','surface'],['positive','positive-bg'],['negative','negative-bg'],['caution','caution-bg'],['info','info-bg']])assert.ok(contrast(tokens[text],tokens[bg])>=4.5,`${text}/${bg}`);
 assert.ok(contrast(tokens['field-line'],tokens.surface)>=3,'field border');
}
assert.ok(contrast('#ffffff','#c90035')>=4.5,'brand button and hero lightest stop');
for(const dir of ['src','dist'])assert.match(readFileSync(new URL(`../${dir}/index.html`,import.meta.url),'utf8'),/dashboard-theme\.css\?v=20261107-colors1/);
assert.equal(readFileSync(new URL('../dist/dashboard-theme.css',import.meta.url),'utf8'),css);
console.log('PASS: light/dark text and semantic colors >=4.5:1, field boundaries >=3:1, production assets synchronized');
