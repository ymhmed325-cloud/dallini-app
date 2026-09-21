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
    check('عدم كشف الأرقام غير المسجلة', forgotUnknown.status === 200 && !forgotUnknown.body.devCode);

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


    // ---------- مسار الفني: قبول + تتبّع المراحل ----------
    const pPhone = '0771' + String(Date.now()).slice(-7);
    const preg = await post('/api/auth/register', { name: 'فني اختبار', phone: pPhone, password, role: 'provider' });
    check('إنشاء حساب فني', preg.status === 201 && !!preg.body.token, JSON.stringify(preg.body));
    const ptoken = preg.body.token;

    const open = await post('/api/requests', { category: 'سباكة', description: 'تسريب ماء في المطبخ', address: 'بغداد - الكرادة' }, token2);
    check('طلب جديد متاح للفنيين', open.status === 201);
    const reqId = open.body.id;

    const list = await req('((none))'.replace('((none))','/api/providers/requests'), { headers: { Authorization: `Bearer ${ptoken}` } });
    const found = Array.isArray(list.body) && list.body.some(x => String(x.id) === String(reqId));
    check('الطلب يظهر في القائمة المتاحة', found);

    const acc = await post(`/api/providers/requests/${reqId}/accept`, {}, ptoken);
    check('الفني يقبل الطلب', acc.status === 200 && acc.body.request.status === 'accepted', JSON.stringify(acc.body).slice(0, 160));

    const jobs = await req('/api/providers/jobs?filter=active', { headers: { Authorization: `Bearer ${ptoken}` } });
    check('الطلب يظهر في طلباتي (الفني)', Array.isArray(jobs.body) && jobs.body.some(x => String(x.id) === String(reqId)));

    // انتقال غير مسموح: من accepted إلى completed مباشرة
    const jump = await post(`/api/providers/requests/${reqId}/status`, { status: 'completed' }, ptoken);
    check('رفض الانتقال غير المسموح', jump.status === 409 && Array.isArray(jump.body.allowedNext), `status=${jump.status} body=${JSON.stringify(jump.body).slice(0,160)}`);

    // الانتقالات بالترتيب
    for (const st of ['on_way', 'arrived', 'in_progress', 'completed']) {
      const r = await post(`/api/providers/requests/${reqId}/status`, { status: st }, ptoken);
      check(`انتقال إلى ${st}`, r.status === 200 && r.body.request.status === st, `status=${r.status} ${JSON.stringify(r.body).slice(0,140)}`);
    }

    // لا انتقال بعد الاكتمال
    const after = await post(`/api/providers/requests/${reqId}/status`, { status: 'on_way' }, ptoken);
    check('رفض أي انتقال بعد الاكتمال', after.status === 409);

    // تتبّع الطلب: العميل والفني مسموح، والغريب ممنوع
    const track = await req(`/api/requests/${reqId}/timeline`, { headers: { Authorization: `Bearer ${token2}` } });
    check('تتبّع الطلب للعميل', track.status === 200 && track.body.status === 'completed' && Array.isArray(track.body.events) && track.body.events.length >= 4, JSON.stringify(track.body).slice(0, 180));
    const trackProvider = await req(`/api/requests/${reqId}/timeline`, { headers: { Authorization: `Bearer ${ptoken}` } });
    check('تتبّع الطلب للفني', trackProvider.status === 200);
    const stranger = await post('/api/auth/register', { name: 'غريب', phone: '0772' + String(Date.now()).slice(-7), password, role: 'customer' });
    const trackStranger = await req(`/api/requests/${reqId}/timeline`, { headers: { Authorization: `Bearer ${stranger.body.token}` } });
    check('منع تتبّع طلب ليس لك', trackStranger.status === 403);

    // بوابة SMS: الحالة الظاهرة في /api/health
    const health2 = await req('/api/health');
    check('حالة بوابة SMS معروضة', typeof health2.body.sms === 'string', JSON.stringify(health2.body));
    console.log(`     (بوابة SMS الحالية: ${health2.body.sms} | resetDemo: ${health2.body.resetDemo})`);

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
