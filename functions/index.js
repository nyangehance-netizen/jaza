/**
 * Letea Cloud Functions. Everything that involves money, prices or trust runs
 * here, so it cannot be changed from someone's phone.
 *
 *  createOrders       customer checkout: re-reads prices, makes one order per provider
 *  confirmDelivery    rider/provider enters the customer's PIN to finish an order
 *  startMobilePayment sends an M-Pesa / Airtel Money payment prompt (see payments.js)
 *  paymentWebhook     your payment provider calls this when a payment succeeds
 *  notify*            push notifications on new orders, new jobs and status changes
 */
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");
const crypto = require("crypto");
const payments = require("./payments");

admin.initializeApp();
setGlobalOptions({ region: "europe-west1", maxInstances: 10 });

const db = admin.firestore();
const FV = admin.firestore.FieldValue;
const DELIVERY_FEE = 2000; // TSh per order with physical goods
const PAY_METHODS = ["mpesa", "airtel", "cash"];

// ---------------------------------------------------------------- checkout
exports.createOrders = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  const { items, address, lat, lng, payMethod, prescriptionPath } = req.data || {};

  if (!Array.isArray(items) || items.length === 0 || items.length > 50) {
    throw new HttpsError("invalid-argument", "Your cart is empty.");
  }
  if (typeof address !== "string" || address.trim().length < 8) {
    throw new HttpsError("invalid-argument", "Add a street or landmark so the rider can find you.");
  }
  if (!PAY_METHODS.includes(payMethod)) throw new HttpsError("invalid-argument", "Choose how to pay.");

  const userSnap = await db.doc(`users/${uid}`).get();
  const customer = userSnap.get("customer");
  if (!customer) throw new HttpsError("failed-precondition", "Set up your customer account first.");

  const snaps = await db.getAll(...items.map((i) => db.doc(`listings/${String(i.listingId)}`)));
  const groups = new Map(); // providerId -> [{listing, qty}]
  snaps.forEach((s, idx) => {
    const qty = Number(items[idx].qty);
    if (!s.exists || s.get("active") === false) {
      throw new HttpsError("failed-precondition", "Something in your cart is no longer available. Remove it and try again.");
    }
    if (!Number.isInteger(qty) || qty < 1 || qty > 50) throw new HttpsError("invalid-argument", "Check the quantities in your cart.");
    const l = { id: s.id, ...s.data() };
    if (!groups.has(l.providerId)) groups.set(l.providerId, []);
    groups.get(l.providerId).push({ l, qty });
  });

  const needsRx = [...groups.values()].flat().some((x) => x.l.rx);
  let rxUrl = null;
  if (needsRx) {
    if (typeof prescriptionPath !== "string" || !prescriptionPath.startsWith(`prescriptions/${uid}/`)) {
      throw new HttpsError("failed-precondition", "Add a photo of your prescription.");
    }
    // A private link the pharmacy can open for 7 days.
    [rxUrl] = await admin.storage().bucket().file(prescriptionPath)
      .getSignedUrl({ action: "read", expires: Date.now() + 7 * 24 * 3600 * 1000 });
  }

  const providerSnaps = await db.getAll(...[...groups.keys()].map((p) => db.doc(`users/${p}`)));
  const providers = Object.fromEntries(providerSnaps.map((s) => [s.id, s]));

  const batch = db.batch();
  const orderIds = [];
  for (const [providerId, lines] of groups) {
    const p = providers[providerId];
    const kind = lines.some((x) => x.l.type !== "service") ? "delivery" : "service";
    const subtotal = lines.reduce((a, x) => a + x.l.price * x.qty, 0);
    const ref = db.collection("orders").doc();
    orderIds.push(ref.id);
    batch.set(ref, {
      code: "LT-" + crypto.randomBytes(3).toString("hex").toUpperCase(),
      customerId: uid,
      customerName: customer.name,
      customerPhone: userSnap.get("phone") || "",
      providerId,
      providerName: p?.get("provider.name") || lines[0].l.providerName,
      providerPhone: p?.get("phone") || "",
      pickupArea: p?.get("provider.area") || lines[0].l.area,
      dropoffAddress: address.trim(),
      dropoff: typeof lat === "number" && typeof lng === "number" ? new admin.firestore.GeoPoint(lat, lng) : null,
      kind,
      items: lines.map((x) => ({ listingId: x.l.id, name: x.l.name, price: x.l.price, qty: x.qty })),
      subtotal,
      fee: kind === "delivery" ? DELIVERY_FEE : 0,
      payMethod,
      payStatus: "unpaid",
      status: "placed",
      riderId: null,
      rxUrl: lines.some((x) => x.l.rx) ? rxUrl : null,
      times: { placed: FV.serverTimestamp() },
    });
    batch.set(ref.collection("private").doc("secret"), {
      pin: String(crypto.randomInt(1000, 10000)),
      attempts: 0,
    });
  }
  await batch.commit();
  return { orderIds };
});

// ---------------------------------------------------------------- delivery PIN
exports.confirmDelivery = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  const { orderId, pin } = req.data || {};
  const orderRef = db.doc(`orders/${String(orderId)}`);
  const secretRef = orderRef.collection("private").doc("secret");

  const result = await db.runTransaction(async (tx) => {
    const [o, s] = await Promise.all([tx.get(orderRef), tx.get(secretRef)]);
    if (!o.exists) throw new HttpsError("not-found", "Order not found.");
    const d = o.data();
    const allowed = d.kind === "service" ? d.providerId === uid : d.riderId === uid;
    if (!allowed) throw new HttpsError("permission-denied", "This order is not assigned to you.");
    if (d.status !== "onway") throw new HttpsError("failed-precondition", "This order is not on the way yet.");
    const attempts = s.get("attempts") || 0;
    if (attempts >= 5) throw new HttpsError("resource-exhausted", "Too many wrong PINs. Call Letea support to finish this order.");
    if (String(pin) !== s.get("pin")) {
      tx.update(secretRef, { attempts: attempts + 1 });
      return "wrong";
    }
    tx.update(orderRef, {
      status: "delivered",
      "times.delivered": FV.serverTimestamp(),
      ...(d.payMethod === "cash" ? { payStatus: "paid" } : {}),
    });
    return "ok";
  });
  if (result === "wrong") {
    throw new HttpsError("invalid-argument", "That PIN is wrong. Ask the customer to check their order screen.");
  }
  return { ok: true };
});

// ---------------------------------------------------------------- payments
// After you create the payment secrets (README step 7), change the next line to:
//   exports.startMobilePayment = onCall({ secrets: ["PAYMENT_API_KEY"] }, async (req) => {
// and paymentWebhook below to: onRequest({ secrets: ["PAYMENT_WEBHOOK_SECRET"] }, async (req, res) => {
exports.startMobilePayment = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  const { orderId, phone } = req.data || {};
  const o = await db.doc(`orders/${String(orderId)}`).get();
  if (!o.exists || o.get("customerId") !== uid) throw new HttpsError("not-found", "Order not found.");
  if (o.get("payStatus") === "paid") return { ok: true };
  if (!["mpesa", "airtel"].includes(o.get("payMethod"))) throw new HttpsError("failed-precondition", "This order is paid in cash.");

  const amount = o.get("subtotal") + o.get("fee");
  const ref = await payments.requestPayment({
    method: o.get("payMethod"),
    phone: String(phone || ""),
    amount,
    reference: o.id,
  });
  await db.collection("payments").doc(o.id).set({
    orderId: o.id, amount, method: o.get("payMethod"), providerRef: ref || null,
    status: "pending", createdAt: FV.serverTimestamp(),
  });
  return { ok: true };
});

exports.paymentWebhook = onRequest(async (req, res) => {
  const event = payments.parseWebhook(req); // returns null if the request is not genuine
  if (!event) {
    res.status(401).send("unauthorised");
    return;
  }
  const orderRef = db.doc(`orders/${event.reference}`);
  await db.runTransaction(async (tx) => {
    const o = await tx.get(orderRef);
    if (!o.exists) return;
    if (event.success && event.amount >= o.get("subtotal") + o.get("fee")) {
      tx.update(orderRef, { payStatus: "paid", "times.paid": FV.serverTimestamp() });
    } else if (!event.success) {
      tx.update(orderRef, { payStatus: "failed" });
    }
    tx.set(db.collection("payments").doc(event.reference), { status: event.success ? "paid" : "failed", raw: event.raw || null }, { merge: true });
  });
  res.status(200).send("ok");
});

// ---------------------------------------------------------------- notifications
async function pushToUser(uid, title, body, data = {}) {
  if (!uid) return;
  const user = await db.doc(`users/${uid}`).get();
  const tokens = user.get("fcmTokens") || [];
  if (!tokens.length) return;
  const res = await admin.messaging().sendEachForMulticast({ tokens, notification: { title, body }, data });
  const dead = tokens.filter((_, i) => !res.responses[i].success &&
    ["messaging/registration-token-not-registered", "messaging/invalid-registration-token"].includes(res.responses[i].error?.code));
  if (dead.length) await user.ref.update({ fcmTokens: FV.arrayRemove(...dead) });
}

exports.notifyNewOrder = onDocumentCreated("orders/{id}", async (event) => {
  const o = event.data.data();
  await pushToUser(o.providerId, "New order", `${o.customerName} · ${o.items.length} item(s) · ${o.code}`, { orderId: event.params.id });
});

exports.notifyStatusChange = onDocumentUpdated("orders/{id}", async (event) => {
  const before = event.data.before.data();
  const o = event.data.after.data();
  if (before.status === o.status) return;
  const id = event.params.id;
  const msg = {
    accepted: [o.customerId, `${o.providerName} confirmed your order`],
    cancelled: [o.customerId, `${o.providerName} declined your order`],
    assigned: [o.customerId, `${o.riderName || "A rider"} is collecting your order`],
    onway: [o.customerId, o.kind === "service" ? `${o.providerName} is on the way` : "Your order is on the way"],
    delivered: [o.customerId, o.kind === "service" ? "Job completed. Asante!" : "Delivered. Asante!"],
  }[o.status];
  if (msg) await pushToUser(msg[0], o.code, msg[1], { orderId: id });
  if (o.status === "assigned") await pushToUser(o.providerId, o.code, `${o.riderName || "A rider"} is coming to pick up`, { orderId: id });
  if (o.status === "ready") {
    await admin.messaging().send({
      topic: "rider-jobs",
      notification: { title: "New delivery job", body: `${o.pickupArea} → ${o.dropoffAddress.split(",")[0]} · TSh ${o.fee}` },
      data: { orderId: id },
    });
  }
});
