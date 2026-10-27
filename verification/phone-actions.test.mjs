import assert from 'node:assert/strict';
import {normalizeWhatsAppPhone,whatsappUrl,findPhoneNumbers} from '../src/phone-actions.js';
for(const p of ['07712345678','+9647712345678','009647712345678','٠٧٧١٢٣٤٥٦٧٨','+964 771 234 5678'])assert.equal(whatsappUrl(p),'https://wa.me/9647712345678');
for(const p of ['911','1234567890','077123','077123456789','uuid'])assert.equal(normalizeWhatsAppPhone(p),null);
assert.equal(findPhoneNumbers('زبون: 07712345678 · كابتن: 07812345678').length,2);
assert.equal(findPhoneNumbers('كود 1234567890 · مبلغ 75000').length,0);
assert.equal(findPhoneNumbers('00771234567899').length,0);
console.log('PASS: WhatsApp phone normalization, multiple phones, Arabic digits, invalid phone and coupon rejection');
