self.addEventListener('notificationclick',event=>{event.notification.close();event.stopImmediatePropagation();const data=event.notification.data?.FCM_MSG?.data||event.notification.data||{};event.waitUntil(clients.matchAll({type:'window',includeUncontrolled:true}).then(list=>{const tab=list.find(c=>c.url.startsWith(self.registration.scope));if(tab){tab.postMessage({type:'tkt-web-click',data});return tab.focus();}return clients.openWindow(self.registration.scope);}));});
importScripts('https://www.gstatic.com/firebasejs/11.10.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.10.0/firebase-messaging-compat.js');
fetch('../firebase-config.json').then(r=>r.json()).then(config=>{firebase.initializeApp(config);firebase.messaging();});
