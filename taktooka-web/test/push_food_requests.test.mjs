import assert from 'node:assert/strict';
import {buildPushMessage} from '../supabase/functions/taktooka-push/message.ts';
const now=Date.parse('2026-10-31T12:00:00Z');
const base={id:'notice',user_id:'owner',title:'طلب جديد',body:'افتح تفاصيل الطلب',expires_at:'2026-10-31T12:00:30Z'};
for(const request_type of ['restaurant','courier']) {
  const n={...base,kind:'food',target:{screen:'food',request_type,order_id:'order',offer_id:'f:order:c:1'}};
  for(const platform of ['android','ios']) {
    const m=buildPushMessage(n,{token:'test',platform},now);
    assert.equal(m.android.priority,'high');
    assert.equal(m.android.ttl,'30s');
    assert.equal(m.apns.payload.aps.sound,'captain_request.caf');
    assert.equal(m.apns.headers['apns-push-type'],'alert');
    assert.equal(m.data.request_type,request_type);
    assert.equal(m.data.screen,'food');
    assert.equal(m.apns.headers['apns-collapse-id'],m.android.collapse_key);
  }
}
const end=buildPushMessage({...base,kind:'offer_end',target:{screen:'food',offer_id:'f:order:c:1'}},{token:'test',platform:'ios'},now);
assert.equal(end.apns.headers['apns-push-type'],'background');
assert.equal(end.apns.payload.aps.sound,undefined);
assert.equal(end.apns.payload.aps['content-available'],1);
const update=buildPushMessage({...base,kind:'food',target:{screen:'food'}},{token:'test',platform:'ios'},now);
assert.equal(update.apns.payload.aps.sound,'default');
assert.equal(update.data.request_type,undefined);
const ride=buildPushMessage({...base,kind:'offer',target:{offer_id:'ride'}},{token:'test',platform:'ios'},now);
assert.equal(ride.apns.payload.aps.sound,'captain_request.caf');
console.log('PASS: restaurant/private/public request payloads, 30s TTL, background priority, shared ringtone, cancellation and normal updates');
