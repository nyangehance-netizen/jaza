// Template for a real payment aggregator (Selcom, AzamPay, ClickPesa, Pesapal, DPO...).
//
// Copy this file to e.g. selcom.js, fill in each method using the provider's official
// API documentation and your merchant credentials, then register it in payments/index.js
// and set PAYMENT_PROVIDER=selcom in .env.
//
// The rest of the app only depends on these three methods.

export const templateProvider = {
  name: 'template',

  /**
   * Start a payment. For mobile money this usually sends a USSD push (PIN prompt) to
   * `phone`; for cards it usually returns a hosted checkout URL.
   * @param {{ payment: {reference:string, amount:number}, order: object, method: string, phone: string }} args
   * @returns {Promise<{ providerRef: string, instructions: string, checkoutUrl?: string|null }>}
   */
  async initiate({ payment, order, method, phone }) {
    // 1. Read credentials from process.env (never hard-code them).
    // 2. Call the provider's "create order / push USSD" endpoint with:
    //    amount = payment.amount (TZS), your reference = payment.reference,
    //    msisdn = phone (2557XXXXXXXX), callback URL = `${PUBLIC_URL}/api/payments/callback/<name>`.
    // 3. Return the provider's transaction id and a message to show the client.
    throw new Error('Payment provider not configured. Set PAYMENT_PROVIDER=test or implement this adapter.');
  },

  /**
   * Turn the provider's webhook request into { reference, status }.
   * MUST verify the provider's signature/checksum and throw if it does not match.
   * @returns {{ reference: string, status: 'paid'|'failed', raw: object }}
   */
  parseCallback(body, headers) {
    throw new Error('Not implemented');
  },

  /** Refund a paid payment (order declined or cancelled). */
  async refund(payment) {
    throw new Error('Not implemented');
  },
};
