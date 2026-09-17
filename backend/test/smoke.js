/**
 * اختبار دخاني لخادم دلّيني: يشغّل الخادم على منفذ مؤقت ثم يمرّ على المسارات الأساسية.
 * التشغيل: npm test    (لا يحتاج قاعدة بيانات، يعمل بذاكرة مؤقتة)
 */
const { spawn } = require('node:child_process');
const assert = require('node:assert');

const PORT = process.env.TEST_PORT || 10099;
const BASE = `http://127.0.0.1:${PORT}`;
const phone = '0770' + String(Date.now()).slice(-7);
const password = 'secret123';
const newPassword = 'newsecret456';

const req = async (path, opts = {}) => {
  const r = await fetch(BASE + path, opts);
  let body = null;
  try { body = await r.json(); } catch (_) { /* بعض الردود ليست JSON */ }
  return { status: r.status, body };
};
const post = (path, obj, token) => req(path, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
  body: JSON.stringify(obj),
});

(async () => {
  const child = spawn(process.execPath, ['server.js'], {
    cwd: __dirname + '/..',
    env: { ...process.env, PORT: String(PORT), DATABASE_URL: '', RESET_DEMO_MODE: 'true' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const logs = [];
  child.stdout.on('data', d => logs.push(String(d)));
  child.stderr.on('data', d => logs.push(String(d)));

  let passed = 0;
  const check = (name, cond, extra = '') => {
    if (cond) { passed++; console.log(`  ✅ ${name}`); }
    else { console.log(`  ❌ ${name} ${extra}`); throw new Error(`failed: ${name}`); }
  };

  try {
    let up = false;
    for (let i = 0; i < 60; i++) {
      try { const h = await req('/api/health'); if (h.status === 200) { up = true; break; } } catch (_) {}
      await new Promise(r => setTimeout(r, 250));
    }
    assert.ok(up, 'الخادم لم يستجب على /api/health');
    console.log('الخادم يعمل على', BASE);

    const health = await req('/api/health');
    check('فحص الحالة', health.status === 200 && health.body.ok === true);

    const cats = await req('/api/categories');
    check('الفئات', cats.status === 200 && Array.isArray(cats.body) && cats.body.length >= 6);

    const reg = await post('/api/auth/register', { name: 'مستخدم اختبار', phone, password, role: 'customer' });
    check('إنشاء حساب', reg.status === 201 && !!reg.body.token, JSON.stringify(reg.body));
    const token = reg.body.token;

    const dup = await post('/api/auth/register', { name: 'مكرر', phone, password, role: 'customer' });
    check('رفض رقم مكرر', dup.status === 409);

    const login = await post('/api/auth/login', { phone, password });
    check('تسجيل الدخول', login.status === 200 && !!login.body.token);

    const me = await req('/api/auth/me', { headers: { Authorization: `Bearer ${token}` } });
    check('بيانات الحساب', me.status === 200 && me.body.user.phone === phone);

    const forgot = await post('/api/auth/forgot-password', { phone });
    check('طلب رمز التحقق', forgot.status === 200 && String(forgot.body.devCode || '').length === 6, JSON.stringify(forgot.body));
    const code = String(forgot.body.devCode);

    const forgotUnknown = await post('/api/auth/forgot-password', { phone: '07709999999' });
    check('رفض رقم غير مسجل', forgotUnknown.status === 404);

    const badReset = await post('/api/auth/reset-password', { phone, code: '000000', newPassword });
    check('رفض رمز خاطئ', badReset.status === 400);

    const reset = await post('/api/auth/reset-password', { phone, code, newPassword });
    check('تغيير كلمة المرور', reset.status === 200 && reset.body.ok === true, JSON.stringify(reset.body));

    const oldLogin = await post('/api/auth/login', { phone, password });
    check('رفض كلمة المرور القديمة', oldLogin.status === 401);

    const newLogin = await post('/api/auth/login', { phone, password: newPassword });
    check('الدخول بكلمة المرور الجديدة', newLogin.status === 200 && !!newLogin.body.token);
    const token2 = newLogin.body.token;

    const staleSession = await req('/api/auth/me', { headers: { Authorization: `Bearer ${token}` } });
    check('إبطال الجلسات القديمة بعد التغيير', staleSession.status === 401);

    const created = await post('/api/requests', { category: 'تكييف', description: 'المكيف لا يبرد', address: 'بغداد' }, token2);
    check('إنشاء طلب', created.status === 201 && !!created.body.id, JSON.stringify(created.body));

    const mine = await req('/api/requests/mine', { headers: { Authorization: `Bearer ${token2}` } });
    check('طلباتي', mine.status === 200 && Array.isArray(mine.body) && mine.body.length >= 1);

    const providerGate = await req('/api/providers/requests', { headers: { Authorization: `Bearer ${token2}` } });
    check('حجب قسم الفنيين عن المستخدم', providerGate.status === 403);

    const unauth = await req('/api/requests/mine');
    check('منع الوصول بلا توثيق', unauth.status === 401);

    console.log(`\nالنتيجة: ${passed} اختباراً ناجحاً ✅`);
  } catch (e) {
    console.error('\nفشل الاختبار:', e.message);
    console.error('--- سجل الخادم ---\n' + logs.join(''));
    try { child.kill('SIGKILL'); } catch (_) {}
    process.exit(1);
  } finally {
    try { child.kill('SIGKILL'); } catch (_) {}
  }
})();
