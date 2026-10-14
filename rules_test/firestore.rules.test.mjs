import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, serverTimestamp, collection, query, where, getDocs, Timestamp } from 'firebase/firestore';
import { readFileSync } from 'node:fs';

const env = await initializeTestEnvironment({
  projectId: 'demo-attendance',
  firestore: { rules: readFileSync(process.argv[2] ?? "../firestore.rules", 'utf8'), host: '127.0.0.1', port: 8080 },
});

await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'users/admin1'), { name: 'Admin', role: 'admin', active: true });
  await setDoc(doc(db, 'users/emp1'), { name: 'Asha', role: 'employee', active: true, deviceId: null, faceEmbedding: null });
  await setDoc(doc(db, 'users/emp2'), { name: 'Ravi', role: 'employee', active: true, deviceId: 'd2', faceEmbedding: [0.1] });
  await setDoc(doc(db, 'users/off1'), { name: 'Gone', role: 'employee', active: false, deviceId: null, faceEmbedding: null });
  await setDoc(doc(db, 'attendance/emp2_2026-10-13'), { uid: 'emp2', date: '2026-10-13', checkIn: { time: Timestamp.now() }, flagged: true, reviewed: false });
});

const emp = env.authenticatedContext('emp1').firestore();
const emp2 = env.authenticatedContext('emp2').firestore();
const off = env.authenticatedContext('off1').firestore();
const admin = env.authenticatedContext('admin1').firestore();

const punch = (extra = {}) => ({ time: serverTimestamp(), lat: 1, lng: 2, accuracy: 5, siteId: 's', siteName: 'HQ', distanceMeters: 3, photoUrl: 'u', photoPath: 'p', faceScore: 0.8, flagReasons: [], deviceId: 'd1', ...extra });
const rec = (uid, date, p = punch(), flagged = false) => ({ uid, employeeName: 'x', date, shiftId: null, checkIn: p, flagged, reviewed: false });

let pass = 0, fail = 0;
async function t(name, fn) { try { await fn(); pass++; console.log('ok  ', name); } catch (e) { fail++; console.log('FAIL', name, e.message); } }

await t('employee reads own missing record (listener)', () => assertSucceeds(getDoc(doc(emp, 'attendance/emp1_2026-10-14'))));
await t('employee cannot read other missing record', () => assertFails(getDoc(doc(emp, 'attendance/emp2_2026-10-14'))));
await t('employee cannot read other existing record', () => assertFails(getDoc(doc(emp, 'attendance/emp2_2026-10-13'))));
await t('employee own-range query', () => assertSucceeds(getDocs(query(collection(emp, 'attendance'), where('uid', '==', 'emp1')))));
await t('employee unfiltered query denied', () => assertFails(getDocs(collection(emp, 'attendance'))));
await t('admin query all', () => assertSucceeds(getDocs(collection(admin, 'attendance'))));

await t('employee binds device once', () => assertSucceeds(updateDoc(doc(emp, 'users/emp1'), { deviceId: 'd1', deviceModel: 'Pixel', deviceBoundAt: serverTimestamp() })));
await t('employee cannot rebind device', () => assertFails(updateDoc(doc(emp, 'users/emp1'), { deviceId: 'dX' })));
await t('employee enrolls face once', () => assertSucceeds(updateDoc(doc(emp, 'users/emp1'), { faceEmbedding: [0.1, 0.2], faceUrl: 'u', facePath: 'p', faceEnrolledAt: serverTimestamp() })));
await t('employee cannot overwrite face', () => assertFails(updateDoc(doc(emp, 'users/emp1'), { faceEmbedding: [9] })));
await t('employee cannot make self admin', () => assertFails(updateDoc(doc(emp, 'users/emp1'), { role: 'admin' })));
await t('employee cannot read other user', () => assertFails(getDoc(doc(emp, 'users/emp2'))));

await t('check-in with server time', () => assertSucceeds(setDoc(doc(emp, 'attendance/emp1_2026-10-14'), rec('emp1', '2026-10-14'))));
await t('check-in with client time denied', () => assertFails(setDoc(doc(emp, 'attendance/emp1_2026-10-15'), rec('emp1', '2026-10-15', punch({ time: Timestamp.now() })))));
await t('check-in for another user denied', () => assertFails(setDoc(doc(emp, 'attendance/emp2_2026-10-15'), rec('emp2', '2026-10-15'))));
await t('check-in id/date mismatch denied', () => assertFails(setDoc(doc(emp, 'attendance/emp1_2026-10-16'), rec('emp1', '2026-10-17'))));
await t('check-in hiding flags denied', () => assertFails(setDoc(doc(emp, 'attendance/emp1_2026-10-18'), rec('emp1', '2026-10-18', punch({ flagReasons: ['face_mismatch'] }), false))));
await t('check-in duplicate (overwrite) denied', () => assertFails(setDoc(doc(emp, 'attendance/emp1_2026-10-14'), rec('emp1', '2026-10-14'))));
await t('inactive user check-in denied', () => assertFails(setDoc(doc(off, 'attendance/off1_2026-10-14'), rec('off1', '2026-10-14'))));

await t('check-out ok', () => assertSucceeds(updateDoc(doc(emp, 'attendance/emp1_2026-10-14'), { checkOut: punch(), flagged: false, reviewed: false })));
await t('second check-out denied', () => assertFails(updateDoc(doc(emp, 'attendance/emp1_2026-10-14'), { checkOut: punch(), flagged: false, reviewed: false })));
await t('edit check-in denied', () => assertFails(updateDoc(doc(emp, 'attendance/emp1_2026-10-14'), { 'checkIn.lat': 9 })));
await t('employee cannot clear flag on check-out', () => assertFails(updateDoc(doc(emp2, 'attendance/emp2_2026-10-13'), { checkOut: punch(), flagged: false, reviewed: false })));
await t('employee check-out keeps flag', () => assertSucceeds(updateDoc(doc(emp2, 'attendance/emp2_2026-10-13'), { checkOut: punch(), flagged: true, reviewed: false })));
await t('employee cannot self-review', () => assertFails(updateDoc(doc(emp2, 'attendance/emp2_2026-10-13'), { reviewed: true, reviewDecision: 'approved' })));
await t('admin review', () => assertSucceeds(updateDoc(doc(admin, 'attendance/emp2_2026-10-13'), { reviewed: true, reviewDecision: 'approved', reviewedBy: 'admin1', reviewedAt: serverTimestamp(), reviewNote: null })));
await t('admin cannot rewrite punch times', () => assertFails(updateDoc(doc(admin, 'attendance/emp2_2026-10-13'), { 'checkIn.time': Timestamp.now() })));

await t('employee reads sites', () => assertSucceeds(getDocs(collection(emp, 'sites'))));
await t('employee cannot write sites', () => assertFails(setDoc(doc(emp, 'sites/x'), { name: 'x' })));
await t('admin writes sites', () => assertSucceeds(setDoc(doc(admin, 'sites/x'), { name: 'x', lat: 1, lng: 2, radiusMeters: 100 })));
await t('admin creates user profile', () => assertSucceeds(setDoc(doc(admin, 'users/new1'), { name: 'New', role: 'employee', active: true, deviceId: null, faceEmbedding: null })));
await t('admin resets device', () => assertSucceeds(updateDoc(doc(admin, 'users/emp1'), { deviceId: null, deviceModel: null, deviceBoundAt: null })));
await t('employee rebinds after reset', () => assertSucceeds(updateDoc(doc(emp, 'users/emp1'), { deviceId: 'd9', deviceModel: 'New', deviceBoundAt: serverTimestamp() })));

await env.cleanup();
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
