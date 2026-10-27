import assert from 'node:assert/strict';
import {buildCouponCardsPdf,buildCouponCardsPdfAsync} from '../src/coupon-card-pdf.js';

const codes=Array.from({length:1000},(_,i)=>String(1000000000+i));
const options={codes,jpeg:new Uint8Array([255,216,255,217]),width:1672,height:941};
const bytes=buildCouponCardsPdf(options);
const text=new TextDecoder().decode(bytes);
assert.match(text,/\/Count 1000 /);
const values=[...text.matchAll(/\((\d+)\) Tj/g)].map(match=>match[1]);
assert.equal(values.length,2000);
for(let i=0;i<1000;i++)assert.deepEqual(values.slice(i*2,i*2+2),[codes[i],String(i+1)]);
assert.deepEqual(await buildCouponCardsPdfAsync(options),bytes);
assert.deepEqual(buildCouponCardsPdf(options),bytes);
const serialCommands=[...text.matchAll(/1 0 0 1 ([\d.]+) ([\d.]+) Tm \((\d{1,4})\) Tj/g)];
assert.equal(serialCommands.length,1000);
assert.ok(Number(serialCommands.at(-1)[1])>0);
console.log('1000 prize cards: sequence 1–1000, distinct codes, deterministic re-download and async PDF passed');
