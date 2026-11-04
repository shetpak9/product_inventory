const path = require("path");
const dotenv = require("dotenv");

dotenv.config({ path: path.join(__dirname, ".env") });
dotenv.config({ path: path.join(__dirname, ".env.local"), override: true });

const crypto = require("crypto");
const express = require("express");
const { cert, getApps, initializeApp } = require("firebase-admin/app");

function initializeFirebase() {
  if (getApps().length > 0) return;
  const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  const projectId = process.env.FIREBASE_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
  const privateKey = process.env.FIREBASE_PRIVATE_KEY;
  const databaseURL = process.env.FIREBASE_DATABASE_URL;

  if (!databaseURL) {
    throw new Error("FIREBASE_DATABASE_URL is required.");
  }

  if (serviceAccountJson) {
    let serviceAccount;
    try {
      serviceAccount = JSON.parse(serviceAccountJson);
    } catch (error) {
      throw new Error(`FIREBASE_SERVICE_ACCOUNT_JSON is invalid: ${error.message}`);
    }
    initializeApp({
      credential: cert(serviceAccount),
      databaseURL,
    });
    return;
  }

  if (!projectId || !clientEmail || !privateKey) {
    throw new Error(
      "Set FIREBASE_SERVICE_ACCOUNT_JSON or FIREBASE_PROJECT_ID, " +
      "FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY, and FIREBASE_DATABASE_URL.",
    );
  }
  initializeApp({
    credential: cert({
      projectId,
      clientEmail,
      privateKey: privateKey.replace(/\\n/g, "\n"),
    }),
    databaseURL,
  });
}

initializeFirebase();

let databaseInstance;
function database() {
  if (!databaseInstance) {
    const { getDatabase } = require("firebase-admin/database");
    databaseInstance = getDatabase();
  }
  return databaseInstance;
}
const PAYMONGO_URL = "https://api.paymongo.com/v2/checkout_sessions";
const PAYMENT_METHODS = ["card", "gcash", "qrph"];
const CHECKOUT_OPERATION_TIMEOUT_MS = 15000;

function elapsed(startedAt) {
  return `${Date.now() - startedAt}ms`;
}

function withTimeout(operation, timeoutMs, label) {
  let timer;
  const timeout = new Promise((resolve, reject) => {
    timer = setTimeout(
      () => reject(new Error(`${label} timed out after ${timeoutMs}ms.`)),
      timeoutMs,
    );
  });
  return Promise.race([operation, timeout]).finally(() => clearTimeout(timer));
}

function paymentReturnBaseUrl() {
  const value = String(process.env.PAYMENT_RETURN_BASE_URL || "").trim();
  if (!value) {
    throw new Error("PAYMENT_RETURN_BASE_URL is not configured.");
  }
  let url;
  try {
    url = new URL(value);
  } catch (_) {
    throw new Error("PAYMENT_RETURN_BASE_URL must be a valid HTTPS URL.");
  }
  if (url.protocol !== "https:") {
    throw new Error("PAYMENT_RETURN_BASE_URL must use HTTPS.");
  }
  return value.replace(/\/+$/, "");
}

function jsonError(response, status, message) {
  response.status(status).json({ error: message });
}

function bearerToken(request) {
  const header = request.get("authorization") || "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match ? match[1] : null;
}

async function authenticate(request, response) {
  const startedAt = Date.now();
  console.log("[CHECKOUT] Firebase token verification started");
  const token = bearerToken(request);
  if (!token) {
    console.warn(`[CHECKOUT] Missing Firebase token (${elapsed(startedAt)})`);
    jsonError(response, 401, "A Firebase Authentication token is required.");
    return null;
  }
  try {
    const { getAuth } = require("firebase-admin/auth");
    const decoded = await withTimeout(
      getAuth().verifyIdToken(token),
      CHECKOUT_OPERATION_TIMEOUT_MS,
      "Firebase token verification",
    );
    console.log(`[CHECKOUT] Firebase token verified (${elapsed(startedAt)})`);
    return decoded;
  } catch (error) {
    console.warn(
      `[CHECKOUT] Firebase token verification failed (${elapsed(startedAt)}): ${error.message}`,
    );
    const status = error.message.includes("timed out") ? 504 : 401;
    jsonError(
      response,
      status,
      status === 504
        ? "Firebase Authentication took too long to respond."
        : "The Firebase Authentication token is invalid.",
    );
    return null;
  }
}

function asMap(value) {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value
    : null;
}

async function writeCustomerNotification(order, type, title, body) {
  if (!order?.customerId || !order?.id) return;
  const notificationId = `order_${order.id}_${type}`;
  await database().ref(
    `notifications/${order.customerId}/${notificationId}`,
  ).set({
    type,
    title,
    body,
    orderId: order.id,
    createdAt: Date.now(),
    read: false,
  });
}

function money(value, label) {
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0 || number > 1000000) {
    throw new Error(`Invalid ${label}.`);
  }
  return number;
}

function amountInCentavos(value) {
  const rounded = Math.round(value * 100);
  if (Math.abs(rounded / 100 - value) > 0.000001) {
    throw new Error("Order contains a monetary value with more than two decimals.");
  }
  return rounded;
}

function optionAdjustment(selected, optionGroups) {
  const selections = asMap(selected) || {};
  const groups = asMap(optionGroups) || {};
  const groupList = Object.values(groups).filter(asMap);
  const groupNames = new Set(groupList.map((group) => String(group.name || "")));
  for (const key of Object.keys(selections)) {
    if (!groupNames.has(key)) throw new Error("An order option is no longer available.");
  }

  let total = 0;
  for (const group of groupList) {
    const name = String(group.name || "");
    const type = String(group.type || "");
    const value = selections[name];
    const choices = Object.values(asMap(group.choices) || {}).filter(asMap);
    if (group.required && (value === undefined || value === null ||
      (type === "freeText" && String(value).trim() === "") ||
      (type === "tags" && (!Array.isArray(value) || value.length === 0)))) {
      throw new Error(`The required option "${name}" is missing.`);
    }
    if (type === "singleChoice" && value !== undefined && value !== null) {
      const choice = choices.find((item) => item.label === value);
      if (typeof value !== "string" || !choice) throw new Error("An order option is invalid.");
      total += money(choice.priceAdjustment, "option price");
    } else if (type === "freeText" && value !== undefined &&
      (typeof value !== "string" || value.length > 100)) {
      throw new Error("An order text option is invalid.");
    } else if (type === "tags" && value !== undefined) {
      if (!Array.isArray(value) || value.some((item) =>
        typeof item !== "string" || !choices.some((choice) => choice.label === item))) {
        throw new Error("An order tag option is invalid.");
      }
      for (const item of value) {
        const choice = choices.find((entry) => entry.label === item);
        total += money(choice.priceAdjustment, "option price");
      }
    }
  }
  return total;
}

function parseItems(rawItems) {
  const entries = Array.isArray(rawItems)
    ? rawItems.map((item, index) => [String(index), item])
    : Object.entries(asMap(rawItems) || {}).sort(([a], [b]) =>
      (Number(a) || 0) - (Number(b) || 0));
  if (entries.length === 0) throw new Error("The order has no items.");
  return entries.map(([, item]) => {
    const value = asMap(item);
    if (!value) throw new Error("The order contains an invalid item.");
    const quantity = Number(value.quantity);
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 99) {
      throw new Error("The order contains an invalid quantity.");
    }

    return { ...value, quantity };
  });
}

async function claimCheckout(orderId) {
  const lockRef = database().ref(`paymentCheckoutLocks/${orderId}`);
  const now = Date.now();
  const result = await lockRef.transaction((current) => {
    if (typeof current === "number" && now - current < 120000) return;
    return now;
  });
  return {
    claimed: result.committed,
    release: () => lockRef.remove(),
  };
}

function promotionDiscount(promotion, order, subtotal) {
  const now = Date.now();
  if (!promotion || promotion.sellerId !== order.sellerId) {
    throw new Error("Discount code is not valid for this store.");
  }
  if (promotion.productId) {
    const appliesToProduct = Object.values(asMap(order.items) || {}).some(
      (item) => asMap(item)?.productId === promotion.productId,
    );
    if (!appliesToProduct) throw new Error("This discount code does not apply to this order.");
  }
  if (now < Number(promotion.startsAt) || now > Number(promotion.endsAt)) {
    throw new Error("This discount code is not currently active.");
  }
  if (promotion.usageLimit != null &&
      Number(promotion.usageCount || 0) >= Number(promotion.usageLimit)) {
    throw new Error("This discount code has reached its usage limit.");
  }
  if (subtotal < Number(promotion.minOrderAmount || 0)) {
    throw new Error("The order does not meet the minimum amount for this code.");
  }
  const value = Number(promotion.value);
  if (!Number.isFinite(value) || value <= 0 ||
      (promotion.type === "percentage" && value > 100)) {
    throw new Error("This discount code is invalid.");
  }
  const discount = promotion.type === "percentage"
    ? subtotal * value / 100
    : value;
  return Math.min(subtotal, Math.max(0, Math.round(discount * 100) / 100));
}

async function applyDiscountToOrder(orderId, uid, code) {
  const snapshot = await database().ref(`orders/${orderId}`).get();
  const order = asMap(snapshot.val());
  if (!order || order.customerId !== uid) throw new Error("Order not found.");
  if (order.discountPromotionId) {
    return {
      discountAmount: Number(order.discountAmount || 0),
      finalTotal: Number(order.finalTotal || order.total),
    };
  }
  const normalizedCode = String(code || "").trim().toUpperCase();
  if (!/^[A-Z0-9_-]{3,30}$/.test(normalizedCode)) {
    throw new Error("Enter a valid discount code.");
  }
  const promotionSnapshot = await database()
    .ref(`promotions/${order.sellerId}/${normalizedCode}`).get();
  const promotion = {
    ...asMap(promotionSnapshot.val()),
    id: normalizedCode,
  };
  const subtotal = Number(order.subtotal);
  const discountAmount = promotionDiscount(promotion, order, subtotal);
  const customerUseRef = database().ref(
    `promotionCustomerUses/${promotion.id}/${uid}`,
  );
  const customerUse = await customerUseRef.transaction((current) => current || {
    orderId,
    usedAt: Date.now(),
  });
  if (!customerUse.committed) throw new Error("Could not reserve this discount code.");
  if (customerUse.snapshot.val()?.orderId !== orderId &&
      customerUse.snapshot.val()?.orderId != null) {
    throw new Error("You have already used this discount code.");
  }
  const usageRef = database().ref(`promotions/${order.sellerId}/${promotion.id}/usageCount`);
  const usage = await usageRef.transaction((current) => {
    const count = Number(current || 0);
    if (promotion.usageLimit != null && count >= Number(promotion.usageLimit)) return;
    return count + 1;
  });
  if (!usage.committed) {
    await customerUseRef.remove();
    throw new Error("This discount code has reached its usage limit.");
  }
  const finalTotal = Math.max(0, Math.round((Number(order.total) - discountAmount) * 100) / 100);
  try {
    await database().ref(`orders/${orderId}`).update({
      discountCode: normalizedCode,
      discountPromotionId: promotion.id,
      discountAmount,
      finalTotal,
      updatedAt: Date.now(),
    });
  } catch (error) {
    await customerUseRef.remove();
    await usageRef.transaction((current) => Math.max(0, Number(current || 0) - 1));
    throw error;
  }
  return { discountAmount, finalTotal };
}

async function validateAndPriceOrder(orderId, uid) {
  const snapshot = await database().ref(`orders/${orderId}`).get();
  const order = asMap(snapshot.val());
  if (!order) throw new Error("Order not found.");
  if (order.customerId !== uid) throw new Error("You do not own this order.");
  if (order.status === "cancelled") throw new Error("Cancelled orders cannot be paid.");
  if (!["unpaid", "failed", "pending"].includes(String(order.paymentStatus || "unpaid"))) {
    throw new Error("The order is not in a payable state.");
  }
  if (order.paymentMethod !== "paymongo") throw new Error("This order is not a PayMongo order.");

  const store = asMap((await database().ref(`stores/${order.sellerId}`).get()).val());
  if (!store || store.isOpen === false) throw new Error("The store is no longer available.");
  const fulfillment = asMap(order.fulfillment);
  const nestedFulfillment = asMap(store.fulfillment);
  const fulfillmentSettings = nestedFulfillment || store;
  const pickupEnabled = nestedFulfillment
    ? fulfillmentSettings.pickupEnabled === true
    : fulfillmentSettings.pickupEnabled !== false;
  const deliveryEnabled = nestedFulfillment
    ? fulfillmentSettings.deliveryEnabled === true
    : fulfillmentSettings.deliveryEnabled === true;
  if (!fulfillment || !["pickup", "delivery"].includes(fulfillment.type)) {
    throw new Error("The order fulfillment settings are invalid.");
  }
  if (fulfillment.type === "pickup" && !pickupEnabled) {
    throw new Error("Pickup is no longer available.");
  }
  if (fulfillment.type === "delivery" && !deliveryEnabled) {
    throw new Error("Delivery is no longer available.");
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(fulfillment.date || ""))) {
    throw new Error("The fulfillment date is invalid.");
  }
  const closedDates = asMap(fulfillmentSettings.closedDates) || {};
  if (closedDates[fulfillment.date] === true) {
    throw new Error("The selected fulfillment date is no longer available.");
  }
  const deliveryFee = fulfillment.type === "delivery"
    ? money(fulfillmentSettings.deliveryFee, "delivery fee") : 0;
  const items = parseItems(order.items);
  const lineItems = [];
  let subtotal = 0;
  for (const item of items) {
    const product = asMap((await database().ref(`products/${item.productId}`).get()).val());
    if (!product || product.isAvailable === false || product.sellerId !== order.sellerId) {
      throw new Error("A product in this order is no longer available.");
    }
    const basePrice = money(product.price, "product price");
    const adjustment = optionAdjustment(item.selectedOptions, product.optionGroups);
    if (Number(item.priceAdjustment || 0) !== adjustment) {
      throw new Error("A product option price has changed.");
    }
    const unitPrice = basePrice + adjustment;
    subtotal += unitPrice * item.quantity;
    lineItems.push({
      name: String(product.name || "Product").slice(0, 100),
      amount: amountInCentavos(unitPrice),
      currency: "PHP",
      quantity: item.quantity,
    });
  }
  const total = subtotal + deliveryFee;
  if (amountInCentavos(total) <= 0) throw new Error("The order total must be positive.");
  if (fulfillment.type === "delivery" && !asMap(fulfillment.address)) {
    throw new Error("A delivery address is required.");
  }
  let discountAmount = 0;
  if (order.discountPromotionId) {
    const promotion = asMap((await database()
      .ref(`promotions/${order.sellerId}/${order.discountPromotionId}`).get()).val());
    discountAmount = promotionDiscount(promotion, order, subtotal);
    if (Number(order.discountAmount || 0) !== discountAmount) {
      throw new Error("The applied discount is no longer valid.");
    }
  }
  const finalTotal = Math.max(0, total - discountAmount);
  if (amountInCentavos(finalTotal) <= 0) throw new Error("The order total must be positive.");
  if (discountAmount > 0) {
    let remainingDiscount = amountInCentavos(discountAmount);
    for (const item of lineItems) {
      const reduction = Math.min(remainingDiscount, item.amount - 1);
      item.amount -= reduction;
      remainingDiscount -= reduction;
      if (remainingDiscount === 0) break;
    }
  }
  return { order, lineItems, subtotal, deliveryFee, total: finalTotal };
}

async function createCheckout(request, response) {
  if (request.method !== "POST") return jsonError(response, 405, "POST is required.");
  const startedAt = Date.now();
  console.log("[CHECKOUT] Request received");
  const decoded = await authenticate(request, response);
  if (!decoded) return;
  const body = asMap(request.body);
  const orderId = typeof body?.orderId === "string" ? body.orderId.trim() : "";
  if (!orderId || !/^[A-Za-z0-9_-]{1,128}$/.test(orderId)) {
    return jsonError(response, 400, "A valid orderId is required.");
  }
  try {
    console.log(`[CHECKOUT] Order validation started (${elapsed(startedAt)})`);
    const priced = await withTimeout(
      validateAndPriceOrder(orderId, decoded.uid),
      CHECKOUT_OPERATION_TIMEOUT_MS,
      "Order validation and Realtime Database reads",
    );
    console.log(`[CHECKOUT] Order and products validated (${elapsed(startedAt)})`);
    if (priced.order.paymentStatus === "pending" && priced.order.paymongoCheckoutUrl) {
      console.log(`[CHECKOUT] Reusing existing checkout session (${elapsed(startedAt)})`);
      return response.json({
        orderId,
        checkoutSessionId: priced.order.paymongoCheckoutSessionId,
        checkoutUrl: priced.order.paymongoCheckoutUrl,
      });
    }
    const checkoutClaim = await claimCheckout(orderId);
    if (!checkoutClaim.claimed) {
      return jsonError(
        response,
        409,
        "A checkout session is already being created for this order. Try again shortly.",
      );
    }
    try {
      const refreshed = await withTimeout(
        database().ref(`orders/${orderId}`).get(),
        CHECKOUT_OPERATION_TIMEOUT_MS,
        "Realtime Database order refresh",
      );
      const currentOrder = asMap(refreshed.val());
      if (currentOrder?.paymentStatus === "pending" &&
          typeof currentOrder.paymongoCheckoutUrl === "string") {
        return response.json({
          orderId,
          checkoutSessionId: currentOrder.paymongoCheckoutSessionId,
          checkoutUrl: currentOrder.paymongoCheckoutUrl,
        });
      }
    const secret = process.env.PAYMONGO_SECRET_KEY;
    if (!secret) throw new Error("PAYMONGO_SECRET_KEY is not configured.");
    const returnBaseUrl = paymentReturnBaseUrl();
    const payload = {
      data: {
        attributes: {
          line_items: [
            ...priced.lineItems,
            ...(priced.deliveryFee > 0 ? [{
              name: "Delivery fee",
              amount: amountInCentavos(priced.deliveryFee),
              currency: "PHP",
              quantity: 1,
            }] : []),
          ],
          payment_method_types: PAYMENT_METHODS,
          success_url: `${returnBaseUrl}/return.html?orderId=${encodeURIComponent(orderId)}&result=success`,
          cancel_url: `${returnBaseUrl}/return.html?orderId=${encodeURIComponent(orderId)}&result=cancel`,
          reference_number: orderId,
          metadata: { orderId, customerId: decoded.uid },
        },
      },
    };
    console.log(`[CHECKOUT] PayMongo request started (${elapsed(startedAt)})`);
    const paymongoResponse = await withTimeout(
      fetch(PAYMONGO_URL, {
        method: "POST",
        headers: {
          Authorization: `Basic ${Buffer.from(`${secret}:`).toString("base64")}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(CHECKOUT_OPERATION_TIMEOUT_MS),
      }),
      CHECKOUT_OPERATION_TIMEOUT_MS,
      "PayMongo checkout request",
    );
    console.log(`[CHECKOUT] PayMongo response received (${elapsed(startedAt)})`);
    const result = await paymongoResponse.json();
    if (!paymongoResponse.ok) {
      console.warn("PayMongo checkout creation failed:", paymongoResponse.status);
      throw new Error("PayMongo could not create a checkout session.");
    }
    const data = asMap(result.data);
    const attributes = asMap(data?.attributes);
    const checkoutUrl = attributes?.checkout_url;
    if (!data?.id || typeof checkoutUrl !== "string" || !checkoutUrl.startsWith("https://")) {
      throw new Error("PayMongo returned an invalid checkout session.");
    }
    await withTimeout(
      database().ref(`orders/${orderId}`).update({
        paymentStatus: "pending",
        paymongoCheckoutSessionId: data.id,
        paymongoCheckoutUrl: checkoutUrl,
        paymentAmount: amountInCentavos(priced.total),
        paymentCurrency: "PHP",
        updatedAt: Date.now(),
      }),
      CHECKOUT_OPERATION_TIMEOUT_MS,
      "Realtime Database order update",
    );
    console.log(`[CHECKOUT] Order updated (${elapsed(startedAt)})`);
    console.log(`[CHECKOUT] Checkout response sent (${elapsed(startedAt)})`);
    return response.json({ orderId, checkoutSessionId: data.id, checkoutUrl });
    } finally {
      await checkoutClaim.release();
    }
  } catch (error) {
    console.warn(`[CHECKOUT] Failed after ${elapsed(startedAt)}: ${error.message}`);
    const status = error.message.includes("timed out") ||
        error.name === "TimeoutError" || error.name === "AbortError"
      ? 504
      : 400;
    return jsonError(
      response,
      status,
      status === 504
        ? "The payment service took too long to respond."
        : error.message,
    );
  }
}

function verifyWebhook(request) {
  const header = request.get("x-paymongo-signature") || "";
  if (!process.env.PAYMONGO_WEBHOOK_SECRET) return false;
  const parts = Object.fromEntries(header.split(",").map((part) => part.split("=")));
  if (!parts.t || (!parts.te && !parts.li) || !request.rawBody) return false;
  const signature = parts.te || parts.li;
  const expected = crypto.createHmac("sha256", process.env.PAYMONGO_WEBHOOK_SECRET || "")
    .update(`${parts.t}.${request.rawBody.toString()}`).digest("hex");
  return signature.length === expected.length &&
    crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected));
}

async function paymongoWebhook(request, response) {
  if (request.method !== "POST") return jsonError(response, 405, "POST is required.");
  if (!verifyWebhook(request)) return jsonError(response, 401, "Invalid webhook signature.");
  let payload;
  try {
    payload = asMap(JSON.parse(request.rawBody.toString("utf8")));
  } catch (_) {
    return jsonError(response, 400, "Invalid webhook payload.");
  }
  const webhookData = asMap(payload?.data);
  const webhookAttributes = asMap(webhookData?.attributes);
  const eventId = String(webhookData?.id || payload?.id || crypto.createHash("sha256")
    .update(request.rawBody).digest("hex"));
  const eventType = String(webhookAttributes?.type || webhookData?.type || "");
  const event = asMap(webhookAttributes?.data);
  const attributes = asMap(event?.attributes);
  if (!eventId || !event || !attributes) return jsonError(response, 400, "Invalid webhook payload.");
  const eventRef = database().ref(`paymentWebhookEvents/${eventId}`);
  const claimed = await eventRef.transaction((current) => {
    const now = Date.now();
    if (current?.completed === true) return;
    if (current?.processingAt && now - current.processingAt < 300000) return;
    return { type: eventType, processingAt: now };
  });
  if (!claimed.committed) {
    const current = (await eventRef.get()).val();
    if (current?.completed === true) {
      return response.status(200).send("already processed");
    }
    return response.status(503).send("webhook is being processed");
  }
  const completeEvent = () => eventRef.update({
    completed: true,
    processedAt: Date.now(),
  });
  const orderId = String(attributes.reference_number || attributes.metadata?.orderId || "");
  if (!orderId) {
    await completeEvent();
    return response.status(200).send("ignored");
  }
  const orderSnapshot = await database().ref(`orders/${orderId}`).get();
  const order = { ...asMap(orderSnapshot.val()), id: orderId };
  if (!order || order.paymongoCheckoutSessionId !== event.id ||
    order.paymentMethod !== "paymongo") {
    await completeEvent();
    return response.status(200).send("ignored");
  }
  const payment = Array.isArray(attributes.payments)
    ? attributes.payments.find((entry) => asMap(entry)?.attributes?.status === "paid")
    : null;
  const paymentAttributes = asMap(payment?.attributes);
  const paid = eventType === "checkout_session.payment.paid" &&
    paymentAttributes?.currency === "PHP" &&
    Number(paymentAttributes.amount) === Number(order.paymentAmount);
  const failed = ["checkout_session.payment.failed", "checkout_session.expired",
    "checkout_session.payment.cancelled"].includes(eventType);
  if (order.paymentStatus === "paid") {
    await completeEvent();
    return response.status(200).send("already paid");
  }
  if (paid) {
    await database().ref(`orders/${orderId}`).update({
      paymentStatus: "paid",
      paymongoPaymentId: payment?.id || null,
      updatedAt: Date.now(),
    });
    await writeCustomerNotification(
      order,
      "payment_paid",
      "Payment confirmed",
      `Payment for your order from ${order.storeName || "the store"} was confirmed.`,
    );
  } else if (failed) {
    await database().ref(`orders/${orderId}`).update({
      paymentStatus: "failed",
      updatedAt: Date.now(),
    });
    await writeCustomerNotification(
      order,
      "payment_failed",
      "Payment failed",
      `Payment for your order from ${order.storeName || "the store"} failed or expired.`,
    );
  }
  await completeEvent();
  return response.status(200).send("ok");
}

const app = express();
app.disable("x-powered-by");
app.get("/api/health", (request, response) => {
  response.status(200).json({ status: "ok", message: "Payments backend is running" });
});
app.post("/api/payments/checkout", express.json(), createCheckout);
app.post("/api/payments/apply-discount", express.json(), async (request, response) => {
  const decoded = await authenticate(request, response);
  if (!decoded) return;
  const body = asMap(request.body);
  const orderId = typeof body?.orderId === "string" ? body.orderId.trim() : "";
  const code = typeof body?.code === "string" ? body.code : "";
  try {
    const result = await applyDiscountToOrder(orderId, decoded.uid, code);
    return response.json({ orderId, ...result });
  } catch (error) {
    return jsonError(response, 400, error.message);
  }
});

app.post("/api/promotions/notify", express.json(), async (request, response) => {
  const decoded = await authenticate(request, response);
  if (!decoded) return;
  try {
    const body = asMap(request.body);
    const promotionId = typeof body?.promotionId === "string"
      ? body.promotionId.trim().toUpperCase() : "";
    const code = typeof body?.code === "string"
      ? body.code.trim().toUpperCase() : "";
    const promotion = asMap((await database()
      .ref(`promotions/${decoded.uid}/${promotionId}`).get()).val());
    if (!promotion || promotion.code !== code) {
      return jsonError(response, 404, "Promotion not found.");
    }
    const orders = asMap((await database().ref("orders")
      .orderByChild("sellerId").equalTo(decoded.uid).get()).val()) || {};
    const updates = {};
    for (const order of Object.values(orders)) {
      if (!order?.customerId) continue;
      updates[`notifications/${order.customerId}/promotion_${promotionId}`] = {
        type: "promotion",
        sellerId: decoded.uid,
        title: "New promotion",
        body: `Use code ${promotionId} at ${order.storeName || "the store"}.`,
        createdAt: Date.now(),
        read: false,
      };
    }
    if (Object.keys(updates).length > 0) await database().ref().update(updates);
    return response.status(200).json({ notified: Object.keys(updates).length });
  } catch (error) {
    console.error("[PROMOTION] Notification fanout failed:", error);
    return jsonError(response, 500, "Could not notify customers.");
  }
});
app.post(
  "/api/payments/webhook",
  express.raw({ type: "application/json", limit: "1mb" }),
  (request, response) => {
    request.rawBody = request.body;
    return paymongoWebhook(request, response);
  },
);

const port = Number(process.env.PORT || 3000);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("PORT must be a valid TCP port.");
}
app.listen(port, "0.0.0.0", () => {
  console.log(`Payments backend listening on 0.0.0.0:${port}`);
});
