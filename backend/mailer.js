/**
 * إرسال البريد لتطبيق دلّيني عبر واجهة HTTP (بدون SMTP).
 * المزوّدات المدعومة: Resend (RESEND_API_KEY) أو Brevo (BREVO_API_KEY).
 * المرسِل: EMAIL_FROM  مثل:  دلّيني <no-reply@yourdomain.com>
 * لا تُسجَّل مفاتيح ولا محتوى الرسائل في السجل.
 */
const FROM = process.env.EMAIL_FROM || '';

const PROVIDER = (() => {
  if (process.env.RESEND_API_KEY && FROM) return 'resend';
  if (process.env.BREVO_API_KEY && FROM) return 'brevo';
  return null;
})();

function providerName() { return PROVIDER || 'none'; }
function isConfigured() { return PROVIDER !== null; }

// "الاسم <a@b.com>" → { name, email }
function parseFrom(v) {
  const m = String(v).match(/^\s*(.*?)\s*<([^>]+)>\s*$/);
  return m ? { name: m[1].replace(/^"|"$/g, ''), email: m[2] } : { name: '', email: String(v).trim() };
}

async function sendEmail(to, subject, text) {
  if (!PROVIDER) return { sent: false, gateway: 'none', reason: 'email-not-configured' };
  try {
    let r;
    if (PROVIDER === 'resend') {
      r = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { Authorization: `Bearer ${process.env.RESEND_API_KEY}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ from: FROM, to: [to], subject, text }),
        signal: AbortSignal.timeout(10000),
      });
    } else {
      const f = parseFrom(FROM);
      r = await fetch('https://api.brevo.com/v3/smtp/email', {
        method: 'POST',
        headers: { 'api-key': process.env.BREVO_API_KEY, 'Content-Type': 'application/json', accept: 'application/json' },
        body: JSON.stringify({ sender: f.name ? { name: f.name, email: f.email } : { email: f.email }, to: [{ email: to }], subject, textContent: text }),
        signal: AbortSignal.timeout(10000),
      });
    }
    if (!r.ok) {
      console.error(`[EMAIL:${PROVIDER}] failed`, r.status);
      return { sent: false, gateway: PROVIDER, reason: `http-${r.status}` };
    }
    return { sent: true, gateway: PROVIDER };
  } catch (e) {
    console.error(`[EMAIL:${PROVIDER}] error`, e && e.name);
    return { sent: false, gateway: PROVIDER, reason: 'network' };
  }
}

module.exports = { sendEmail, providerName, isConfigured };
