const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

// ─────────────────────────────────────────────────────────────────────────────
// activateLicense — called by mobile app when user enters a key
//
// Input:  { key, deviceId, deviceModel, deviceOS }
// Output: { success, message, expiryDate? }
//
// Scenarios handled:
//   - C1: Device has a blocked key → reject (can't use new key while blocked)
//   - A1: Valid pending key → bind device, set active, calculate expiry
//   - A6/A7: Same device re-enters same key → restore (no write needed)
//   - C2: Expired key on device → device freed, can activate new key
//   - C3: Deleted key on device → device freed, can activate new key
//   - Wrong device → reject
//   - Key blocked/deleted/expired → reject
//   - Auto-expire: if key is past expiry date, mark expired + clear device
// ─────────────────────────────────────────────────────────────────────────────
exports.activateLicense = onCall({ region: "europe-west1" }, async (request) => {
  const { key, deviceId, deviceModel, deviceOS } = request.data;

  if (!key || !deviceId) {
    throw new HttpsError("invalid-argument", "Missing key or deviceId.");
  }

  // ── C1: Check if this device has a BLOCKED key ──────────────────────────
  const blockedSnap = await db.collection("licenses")
    .where("deviceId", "==", deviceId)
    .where("status", "==", "blocked")
    .limit(1)
    .get();

  if (!blockedSnap.empty) {
    return { success: false, message: "Device is blocked. Contact support." };
  }

  // ── Find the license by key ─────────────────────────────────────────────
  const licSnap = await db.collection("licenses")
    .where("key", "==", key)
    .limit(1)
    .get();

  if (licSnap.empty) {
    return { success: false, message: "Invalid license key." };
  }

  const licDoc = licSnap.docs[0];
  const lic = licDoc.data();

  // ── Reject blocked/deleted/expired ──────────────────────────────────────
  if (lic.status === "blocked") {
    return { success: false, message: "This key has been blocked." };
  }
  if (lic.status === "deleted") {
    return { success: false, message: "This key has been deleted." };
  }
  if (lic.status === "expired") {
    return { success: false, message: "This key has expired." };
  }

  // ── Auto-expire check ──────────────────────────────────────────────────
  if (lic.expiryDate) {
    const expiry = lic.expiryDate.toDate();
    if (new Date() > expiry) {
      await licDoc.ref.update({
        status: "expired",
        deviceId: "",
        deviceModel: "",
        deviceOS: "",
      });
      await db.collection("activity").add({
        key: key,
        action: "Expired",
        device: lic.deviceModel || "Unknown",
        timestamp: FieldValue.serverTimestamp(),
      });
      return { success: false, message: "This key has expired." };
    }
  }

  // ── Wrong device check ─────────────────────────────────────────────────
  if (lic.deviceId && lic.deviceId !== "" && lic.deviceId !== deviceId) {
    return { success: false, message: "Key is linked to another device." };
  }

  // ── A6/A7: Same device already active → restore (no write) ─────────────
  if (lic.deviceId === deviceId && lic.status === "active") {
    return {
      success: true,
      message: "Restored.",
      expiryDate: lic.expiryDate ? lic.expiryDate.toDate().toISOString() : null,
    };
  }

  // ── A1: First activation (pending key) → bind device ────────────────────
  const updates = {
    deviceId: deviceId,
    deviceModel: deviceModel || "Unknown",
    deviceOS: deviceOS || "Unknown",
    status: "active",
    lastReactivationAt: FieldValue.serverTimestamp(),
  };

  // Set expiry on first ever activation
  if (!lic.activatedAt) {
    updates.activatedAt = FieldValue.serverTimestamp();
    if (lic.durationDays) {
      const expiry = new Date();
      expiry.setDate(expiry.getDate() + lic.durationDays);
      updates.expiryDate = Timestamp.fromDate(expiry);
    } else if (lic.durationMonths) {
      const expiry = new Date();
      expiry.setDate(expiry.getDate() + lic.durationMonths * 30);
      updates.expiryDate = Timestamp.fromDate(expiry);
    }
  }

  await licDoc.ref.update(updates);

  // ── Update users collection ─────────────────────────────────────────────
  await db.collection("users").doc(deviceId).set({
    deviceId: deviceId,
    deviceModel: deviceModel || "Unknown",
    deviceOS: deviceOS || "Unknown",
    currentLicense: key,
    lastActive: FieldValue.serverTimestamp(),
  }, { merge: true });

  // ── Log activity ────────────────────────────────────────────────────────
  await db.collection("activity").add({
    key: key,
    action: "Activated",
    device: deviceModel || "Unknown",
    timestamp: FieldValue.serverTimestamp(),
  });

  return {
    success: true,
    message: "Activated successfully.",
    expiryDate: updates.expiryDate
      ? updates.expiryDate.toDate().toISOString()
      : (lic.expiryDate ? lic.expiryDate.toDate().toISOString() : null),
  };
});


// ─────────────────────────────────────────────────────────────────────────────
// checkLicense — called by mobile app on every launch
//
// Input:  { key, deviceId }
// Output: { valid, message }
//
// Handles:
//   - Kill switch check
//   - Auto-expire (marks key expired + clears device server-side)
//   - Device mismatch (key was reset to another device)
//   - Status checks (blocked, deleted, expired)
// ─────────────────────────────────────────────────────────────────────────────
exports.checkLicense = onCall({ region: "europe-west1" }, async (request) => {
  const { key, deviceId } = request.data;

  if (!key || !deviceId) {
    throw new HttpsError("invalid-argument", "Missing key or deviceId.");
  }

  // ── Kill switch ─────────────────────────────────────────────────────────
  const settingsSnap = await db.collection("settings").doc("global").get();
  if (settingsSnap.exists && settingsSnap.data().killSwitch === true) {
    return { valid: false, message: "App is disabled." };
  }

  // ── Find the license ────────────────────────────────────────────────────
  const licSnap = await db.collection("licenses")
    .where("key", "==", key)
    .limit(1)
    .get();

  if (licSnap.empty) {
    return { valid: false, message: "Key not found." };
  }

  const licDoc = licSnap.docs[0];
  const lic = licDoc.data();

  // ── Status checks ──────────────────────────────────────────────────────
  if (lic.status === "blocked" || lic.status === "deleted" || lic.status === "expired") {
    return { valid: false, message: `Key is ${lic.status}.` };
  }

  // ── Auto-expire ────────────────────────────────────────────────────────
  if (lic.expiryDate) {
    const expiry = lic.expiryDate.toDate();
    if (new Date() > expiry) {
      await licDoc.ref.update({
        status: "expired",
        deviceId: "",
        deviceModel: "",
        deviceOS: "",
      });
      await db.collection("activity").add({
        key: key,
        action: "Expired",
        device: lic.deviceModel || "Unknown",
        timestamp: FieldValue.serverTimestamp(),
      });
      return { valid: false, message: "Key has expired." };
    }
  }

  // ── Device mismatch (key was reset to another device) ──────────────────
  if (lic.deviceId && lic.deviceId !== "" && lic.deviceId !== deviceId) {
    return { valid: false, message: "Key is linked to another device." };
  }

  return { valid: true, message: "OK" };
});
