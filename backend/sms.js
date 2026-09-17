/**
 * بوابة SMS لتطبيق دلّيني.
 * يدعم Twilio Verify (OTP)، ثم Twilio Messaging، Vonage، أو HTTP عام.
 */
const VERIFY_SERVICE_SID = process.env.TWILIO_VERIFY_SERVICE_SID;
const TWILIO_READY = !!(process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN);

const GATEWAY = (() => {
  if (VERIFY_SERVICE_SID && TWILIO_READY) return 'twilio-verify';
  if (process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN && process.env.TWILIO_FROM) return 'twilio';
  if (process.env.VONAGE_API_KEY && process.env.VONAGE_API_SECRET && process.env.VONAGE_FROM) return 'vonage';
  if (process.env.SMS_API_URL) return 'generic';
  return null;
})();

function gatewayName() { return GATEWAY || 'none'; }
function isConfigured() { return GATEWAY !== null; }

function twilioAuthHeader() {
  return 'Basic ' + Buffer.from(`${process.env.TWILIO_ACCOUNT_SID}:${process.env.TWILIO_AUTH_TOKEN}`).toString('base64');
}

// Twilio requires phone numbers in E.164 format. Accept Iraqi local numbers too.
function normalizeTwilioPhone(v) {
  let p = String(v || '').trim().replace(/[\s()-]/g, '');
  if (p.startsWith('00')) p = '+' + p.slice(2);
  if (p.startsWith('+')) return p;
  if (/^07\d{9}$/.test(p)) return '+964' + p.slice(1);
  if (/^7\d{9}$/.test(p)) return '+964' + p;
  return p;
}

async function sendTwilioVerify(phone, text) {
  // دلّيني يولّد الرمز محلياً حالياً؛ نمرره إلى Verify عبر CustomCode.
  // يجب تفعيل Enable Custom Verification Code في إعدادات خدمة Verify.
  const match = String(text || '').match(/\b(\d{6})\b/);
  if (!match) return { sent: false, gateway: 'twilio-verify', reason: 'verification-code-not-found' };

  const url = `https://verify.twilio.com/v2/Services/${VERIFY_SERVICE_SID}/Verifications`;
  const body = new URLSearchParams({
    To: normalizeTwilioPhone(phone),
    Channel: 'sms',
    CustomCode: match[1],
  });
  const r = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: twilioAuthHeader(),
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body,
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) {
    console.error('[SMS:twilio-verify] failed', r.status, data);
    return {
      sent: false,
      gateway: 'twilio-verify',
      reason: data.message || data.detail || `http-${r.status}`,
      code: data.code,
    };
  }
  return { sent: true, gateway: 'twilio-verify', id: data.sid, status: data.status };
}

async function sendSms(phone, text) {
  if (!GATEWAY) {
    console.log(`[SMS:console] to=${phone} :: ${text}`);
    return { sent: false, gateway: 'none', reason: 'no-gateway-configured' };
  }
  try {
    if (GATEWAY === 'twilio-verify') return await sendTwilioVerify(phone, text);

    if (GATEWAY === 'twilio') {
      const sid = process.env.TWILIO_ACCOUNT_SID;
      const url = `https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`;
      const body = new URLSearchParams({ To: normalizeTwilioPhone(phone), From: process.env.TWILIO_FROM, Body: text });
      const r = await fetch(url, {
        method: 'POST',
        headers: { Authorization: twilioAuthHeader(), 'Content-Type': 'application/x-www-form-urlencoded' },
        body,
      });
      const data = await r.json().catch(() => ({}));
      if (!r.ok) {
        console.error('[SMS:twilio] failed', r.status, data);
        return { sent: false, gateway: 'twilio', reason: data.message || `http-${r.status}` };
      }
      return { sent: true, gateway: 'twilio', id: data.sid };
    }

    if (GATEWAY === 'vonage') {
      const body = new URLSearchParams({
        api_key: process.env.VONAGE_API_KEY,
        api_secret: process.env.VONAGE_API_SECRET,
        to: String(phone).replace(/^\+/, ''),
        from: process.env.VONAGE_FROM,
        text,
      });
      const r = await fetch('https://rest.nexmo.com/sms/json', { method: 'POST', body });
      const data = await r.json().catch(() => ({}));
      const msg = data && data.messages && data.messages[0];
      if (!r.ok || !msg || msg.status !== '0') {
        console.error('[SMS:vonage] failed', r.status, msg);
        return { sent: false, gateway: 'vonage', reason: (msg && msg['error-text']) || `http-${r.status}` };
      }
      return { sent: true, gateway: 'vonage', id: msg['message-id'] };
    }

    const method = (process.env.SMS_API_METHOD || 'POST').toUpperCase();
    const url = process.env.SMS_API_URL.replace('{phone}', encodeURIComponent(phone)).replace('{text}', encodeURIComponent(text));
    const headers = { 'Content-Type': 'application/json' };
    if (process.env.SMS_API_KEY) headers.Authorization = `Bearer ${process.env.SMS_API_KEY}`;
    const opts = { method, headers };
    if (method !== 'GET') opts.body = JSON.stringify({ to: phone, text, message: text, sender: process.env.SMS_SENDER || undefined });
    const r = await fetch(url, opts);
    const raw = await r.text();
    if (!r.ok) {
      console.error('[SMS:generic] failed', r.status, raw.slice(0, 200));
      return { sent: false, gateway: 'generic', reason: `http-${r.status}` };
    }
    return { sent: true, gateway: 'generic' };
  } catch (e) {
    console.error('[SMS] error', e);
    return { sent: false, gateway: GATEWAY, reason: e.message };
  }
}

module.exports = { sendSms, gatewayName, isConfigured };
