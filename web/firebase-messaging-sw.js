// Service worker for check-in push notifications on the web dashboard
// (functions/src/notifications.ts sends them; lib/core/notifications/
// check_in_notifications.dart registers for them). FCM's web SDK looks
// for exactly this filename at the site root — without it, getToken()
// fails and the browser never receives a push.
//
// With the app closed or in a background tab, the SDK displays each
// notification itself and, on click, opens the webpush.fcmOptions.link
// the function attaches (the live check-in feed). While the dashboard is
// the focused tab, nothing is shown here — the in-app snackbar covers it.
//
// 10.11.1 is the JS SDK version firebase_core_web 2.17.x loads for the
// app itself; kept the same so the two don't disagree about anything.
importScripts("https://www.gstatic.com/firebasejs/10.11.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.11.1/firebase-messaging-compat.js");

// The web app's public config — the same values as
// DefaultFirebaseOptions.web in lib/firebase_options.dart (not secrets;
// they ship in every page load anyway).
firebase.initializeApp({
  apiKey: "AIzaSyAeTsmpml5F76ID_dTYPD_B6cAuU1h6qnM",
  appId: "1:602513846772:web:08eafeedaa09cfa4c149a1",
  messagingSenderId: "602513846772",
  projectId: "sabha-hq",
  authDomain: "sabha-hq.firebaseapp.com",
  storageBucket: "sabha-hq.firebasestorage.app",
});

firebase.messaging();
