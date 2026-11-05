const crypto = require("crypto");
const http = require("http");
const path = require("path");
const dotenv = require("dotenv");

dotenv.config({ path: path.join(__dirname, ".env") });
dotenv.config({ path: path.join(__dirname, ".env.local"), override: true });

const [orderId, checkoutSessionId, amount] = process.argv.slice(2);
if (!orderId || !checkoutSessionId || !/^\d+$/.test(amount || "")) {
  console.error(
    "Usage: node test-webhook.js <orderId> <checkoutSessionId> <amountInCentavos>",
  );
  process.exitCode = 1;
  return;
}

const secret = process.env.PAYMONGO_WEBHOOK_SECRET;
if (!secret) {
  console.error("PAYMONGO_WEBHOOK_SECRET is not configured.");
  process.exitCode = 1;
  return;
}

const payload = {
  data: {
    id: `test_event_${Date.now()}`,
    attributes: {
      type: "checkout_session.payment.paid",
      data: {
        id: checkoutSessionId,
        attributes: {
          reference_number: orderId,
          payments: [{
            id: `test_payment_${Date.now()}`,
            attributes: {
              status: "paid",
              currency: "PHP",
              amount: Number(amount),
            },
          }],
        },
      },
    },
  },
};
const rawBody = JSON.stringify(payload);
const timestamp = Math.floor(Date.now() / 1000).toString();
const signature = crypto.createHmac("sha256", secret)
  .update(`${timestamp}.${rawBody}`)
  .digest("hex");
const mode = String(process.env.PAYMONGO_MODE || "test").toLowerCase();
const port = Number(process.env.PORT || 3000);
console.log(
  `[TEST WEBHOOK] mode=${mode}, secretConfigured=true, ` +
  `signatureLength=${signature.length}, port=${port}.`,
);
const request = http.request({
  hostname: "127.0.0.1",
  port,
  path: "/api/payments/webhook",
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(rawBody),
    "Paymongo-Signature": `t=${timestamp},${mode === "live" ? "li" : "te"}=${signature}`,
  },
}, (response) => {
  let body = "";
  response.setEncoding("utf8");
  response.on("data", (chunk) => { body += chunk; });
  response.on("end", () => {
    console.log(`HTTP ${response.statusCode}: ${body}`);
  });
});
request.on("error", (error) => {
  console.error(`Webhook request failed: ${error.message}`);
  process.exitCode = 1;
});
request.write(rawBody);
request.end();
