/**
 * Mobile money adapter. THIS IS THE ONE PART YOU MUST FINISH before taking
 * real payments, because it depends on which payment company you sign up with.
 *
 * In Tanzania you can either:
 *   - connect to each network directly (Vodacom M-Pesa, Airtel Money, ...), or
 *   - use one aggregator that covers all networks with one contract and one API.
 *     For a startup an aggregator is usually faster. Compare their fees,
 *     settlement times and onboarding requirements before choosing.
 *
 * Whichever you pick, they give you: API keys, a "push payment" (USSD prompt)
 * endpoint, and a webhook/callback that tells you when the customer paid.
 * Fill in the two functions below with their documented API.
 *
 * Keep keys out of code. Store them as secrets:
 *   firebase functions:secrets:set PAYMENT_API_KEY
 *   firebase functions:secrets:set PAYMENT_WEBHOOK_SECRET
 */
const { HttpsError } = require("firebase-functions/v2/https");
const crypto = require("crypto");

/**
 * Ask the payment company to send a payment prompt to the customer's phone.
 * @returns {Promise<string>} the payment company's transaction reference
 */
async function requestPayment({ method, phone, amount, reference }) {
  if (!process.env.PAYMENT_API_KEY) {
    throw new HttpsError(
      "failed-precondition",
      "Mobile money is not switched on yet. Choose cash on delivery for now."
    );
  }
  // Example shape (replace with your provider's real endpoint and fields):
  //
  // const res = await fetch("https://api.your-payment-provider.example/v1/push", {
  //   method: "POST",
  //   headers: { "Authorization": `Bearer ${process.env.PAYMENT_API_KEY}`, "Content-Type": "application/json" },
  //   body: JSON.stringify({ msisdn: phone.replace("+", ""), amount, currency: "TZS",
  //                          network: method, external_id: reference,
  //                          callback_url: "https://<region>-<project>.cloudfunctions.net/paymentWebhook" }),
  // });
  // if (!res.ok) throw new HttpsError("unavailable", "The payment service did not respond. Try again.");
  // return (await res.json()).transaction_id;
  throw new HttpsError("unimplemented", "Connect a payment provider in functions/payments.js.");
}

/**
 * Check a webhook really came from your payment company, and read it.
 * @returns {{reference: string, success: boolean, amount: number, raw?: object} | null}
 */
function parseWebhook(req) {
  const secret = process.env.PAYMENT_WEBHOOK_SECRET;
  if (!secret) return null;
  // Most providers sign the body with a shared secret (HMAC). Check yours.
  const sig = req.get("x-signature") || "";
  const expected = crypto.createHmac("sha256", secret).update(req.rawBody || "").digest("hex");
  if (sig.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) return null;
  const b = req.body || {};
  // Map your provider's field names here:
  return {
    reference: String(b.external_id || b.reference || ""),
    success: b.status === "SUCCESS" || b.status === "COMPLETED",
    amount: Number(b.amount || 0),
    raw: b,
  };
}

module.exports = { requestPayment, parseWebhook };
