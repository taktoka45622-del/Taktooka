const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync(require('node:path').join(__dirname,'../src/app.js'),'utf8');
const start=source.indexOf('async function loadPricing()'),end=source.indexOf('\n',start);
const result={textContent:'1500'},ctx=vm.createContext({pricing:{revision:10},tiers:[],pricingRpc:async()=>({revision:10,tiers:[],updated_at:null}),priceKeys:[],structuredClone,renderTiers(){},dates:()=>'', $:id=>id==='previewResult'?result:{}});
(async()=>{vm.runInContext(source.slice(start,end),ctx);await ctx.loadPricing();assert.equal(result.textContent,'1500');ctx.pricingRpc=async()=>({revision:11,tiers:[]});await ctx.loadPricing();assert.equal(result.textContent,'');console.log('PASS: background refresh retains quote; changed pricing clears stale quote');})().catch(e=>{console.error(e);process.exitCode=1});
