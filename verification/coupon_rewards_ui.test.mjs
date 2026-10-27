import assert from 'node:assert/strict';
import fs from 'node:fs';
const source=fs.readFileSync(new URL('../src/coupon-rewards.js',import.meta.url),'utf8');
const {createCouponRewards}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
class Element {
 constructor(tag='div'){this.tag=tag;this.children=[];this.value='';this.hidden=false;this.disabled=false;this.isConnected=true;}
 set value(v){this._value=String(v);} get value(){return this._value;}
 append(...children){this.children.push(...children);}
 replaceChildren(...children){this.children=children;}
 scrollIntoView(){}
 querySelectorAll(){return [];}
 reset(){for(const id of ['rewardCode','rewardAmount'])elements[id].value='';elements.rewardType.value='amount';}
 click(){return this.onclick?.();}
}
const ids=['rewardType','rewardAmountField','rewardAmount','rewardExplanation','rewardForm','rewardCode','rewardUses','rewardActive','rewardExpiry','rewardList','rewardSearch','rewardSummary','newReward','refreshRewards'];
const elements=Object.fromEntries(ids.map(id=>[id,new Element()]));
const document={getElementById:id=>elements[id],createElement:tag=>new Element(tag)};
const calls=[];let edit=true;let locked=false;let detail;
const run=async fn=>{if(locked)return;locked=true;try{return await fn();}finally{locked=false;}};
const rpc=async(action,data)=>{calls.push({action,data});if(action==='list')return {coupons:[{code:'FREE1',reward_type:'free_ride',active:true,amount:100000,max_uses:20,uses:1,completed:1,bonus_days:1,expires_at:'2030-01-01T00:00:00Z'}],free_completed:1,bonus_days:1};if(action==='history')return {rows:[{id:'trip-1',customer_name:'Customer',status:'completed',coupon_reward_type:'free_ride',customer_due:0,discount:5000,days:1,created_at:'2026-10-14',captain_expires_at:'2030-01-01'}]};return {ok:true};};
const ui=createCouponRewards({document,rpc,money:x=>String(x),dates:x=>String(x),canEdit:()=>edit,notify:()=>{},run,openDetail:()=>{detail=new Element();return detail;}});
await ui.load();assert.equal(elements.rewardList.children.length,1);assert.match(elements.rewardSummary.textContent,/1 رحلة مجانية/);
elements.rewardType.value='free_ride';elements.rewardType.onchange();assert.equal(elements.rewardAmountField.hidden,true);assert.equal(elements.rewardAmount.disabled,true);
elements.rewardCode.value='newfree';elements.rewardExpiry.value='2030-01-01T00:00';elements.rewardUses.value='1,000';await elements.rewardForm.onsubmit({preventDefault(){}});await new Promise(r=>setTimeout(r,0));
const save=calls.find(c=>c.action==='save');assert.equal(save.data.reward_type,'free_ride');assert.equal(save.data.code,'NEWFREE');assert.equal(save.data.max_uses,1000);
const controls=elements.rewardList.children[0].children.at(-1);await controls.children[1].click();assert.ok(calls.some(c=>c.action==='history'));assert.equal(detail.children[0].children.length,1);
elements.rewardType.value='amount';elements.rewardType.onchange();elements.rewardCode.value='money1';elements.rewardAmount.value='2,500';elements.rewardExpiry.value='2030-01-01T00:00';await elements.rewardForm.onsubmit({preventDefault(){}});await new Promise(r=>setTimeout(r,0));assert.equal(calls.filter(c=>c.action==='save').at(-1).data.amount,2500);
edit=false;ui.syncPermissions();assert.equal(elements.rewardAmount.disabled,true);const count=calls.length;elements.rewardForm.onsubmit({preventDefault(){}});assert.equal(calls.length,count);
console.log('Coupon UI: modes, amount/free save, grouped amounts, history loading and read-only permissions passed');
