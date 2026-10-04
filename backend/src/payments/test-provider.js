// Test-mode provider. Behaves like a mobile money / card aggregator but moves no money.
// A payment is approved automatically after TEST_AUTO_APPROVE_MS, or manually via
// POST /api/payments/test/:reference/approve (or /decline).
import { config, PAYMENT_METHODS } from '../config.js';

export const testProvider = {
  name: 'test',
  async initiate({ payment, method, phone }) {
    const kind = PAYMENT_METHODS[method].kind;
    const instructions = kind === 'mobile'
      ? `Test mode: a ${PAYMENT_METHODS[method].label} PIN prompt would now appear on ${phone}.`
      : 'Test mode: the card checkout page would open here.';
    return {
      providerRef: 'TEST-' + payment.reference,
      instructions,
      checkoutUrl: null,
      autoApproveMs: config.testAutoApproveMs,
    };
  },
  // Real providers verify a signature here. Test callbacks are trusted.
  parseCallback(body) {
    return { reference: body.reference, status: body.status === 'paid' ? 'paid' : 'failed', raw: body };
  },
  async refund() {
    return { ok: true };
  },
};
