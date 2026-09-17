/**
 * إرسال رسائل SMS عبر بوابة حقيقية.
 * يدعم: Twilio، Vonage (Nexmo)، أو بوابة عامة عبر HTTP.
 * إن لم تُضبط أي بوابة يعمل في وضع السجل (console) ويُبلّغ بذلك.
 */
const GATEWAY = (() => {
  if (process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN && process.env.TWILIO_FROM) return 'twilio';
  if (process.env.VONAGE_API_KEY && process.env.VONAGE_API_SECRET && process.env.VONAGE_FROM) return 'vonage';
  if (process.env.SMS_API_URL) return 'generic';
  return null;
})();

function gatewayName() { return GATEWAY || 'none'; }
function isConfigured() { return GATEWAY !== null; }

async function sendSms(phone, text) {
  if (!GATEWAY) {
    console.log(`[SMS:console] to=${phone} :: ${text}`);
    return { sent: false, gateway: 'none', reason: 'no-gateway-configured' };
  }
  try {
    if (GATEWAY === 'twilio') {
      const sid = process.env.TWILIO_ACCOUNT_SID;
      const url = `https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`;
      const body = new URLSearchParams({ To: phone, From: process.env.TWILIO_FROM, Body: text });
      const r = await fetch(url, {
        method: 'POST',
        headers: {
          Authorization: 'Basic ' + Buffer.from(`${sid}:${process.env.TWILIO_AUTH_TOKEN}`).toString('base64'),
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body,
      });
      const data = await r.json().catch(() => ({}));
      if (!r.ok) { console.error('[SMS:twilio] failed', r.status, data); return { sent: false, gateway: 'twilio', reason: data.message || `http-${r.status}` }; }
      return { sent: true, gateway: 'twilio', id: data.sid };
    }

    if (GATEWAY === 'vonage') {
      const url = 'https://rest.nexmo.com/sms/json';
      const body = new URLSearchParams({
        api_key: process.env.VONAGE_API_KEY,
        api_secret: process.env.VONAGE_API_SECRET,
        to: String(phone).replace(/^\+/, ''),
        from: process.env.VONAGE_FROM,
        text,
      });
      const r = await fetch(url, { method: 'POST', body });
      const data = await r.json().catch(() => ({}));
      const msg = data && data.messages && data.messages[0];
      if (!r.ok || !msg || msg.status !== '0') { console.error('[SMS:vonage] failed', r.status, msg); return { sent: false, gateway: 'vonage', reason: (msg && msg['error-text']) || `http-${r.status}` }; }
      return { sent: true, gateway: 'vonage', id: msg['message-id'] };
    }

    // بوابة عامة: SMS_API_URL قد يحتوي {phone} و {text}
    const method = (process.env.SMS_API_METHOD || 'POST').toUpperCase();
    let url = process.env.SMS_API_URL.replace('{phone}', encodeURIComponent(phone)).replace('{text}', encodeURIComponent(text));
    const headers = { 'Content-Type': 'application/json' };
    if (process.env.SMS_API_KEY) headers.Authorization = `Bearer ${process.env.SMS_API_KEY}`;
    const opts = { method, headers };
    if (method !== 'GET') opts.body = JSON.stringify({ to: phone, text, message: text, sender: process.env.SMS_SENDER || undefined });
    const r = await fetch(url, opts);
    const raw = await r.text();
    if (!r.ok) { console.error('[SMS:generic] failed', r.status, raw.slice(0, 200)); return { sent: false, gateway: 'generic', reason: `http-${r.status}` }; }
    return { sent: true, gateway: 'generic' };
  } catch (e) {
    console.error('[SMS] error', e);
    return { sent: false, gateway: GATEWAY, reason: e.message };
  }
}

module.exports = { sendSms, gatewayName, isConfigured };
