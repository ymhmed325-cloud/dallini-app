const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const { Pool } = require('pg');

const app = express();
const PORT = process.env.PORT || 10000;
app.set('trust proxy', 1);
app.use(cors());
app.use(express.json({ limit: '1mb' }));

// ---- تحديد المعدّل (Rate limit) بدون مكتبات إضافية ----
const _hits = new Map();
function rateLimit(name, max, windowMs, keyFn){
  return (req,res,next)=>{
    const key = name+':'+(keyFn?keyFn(req):req.ip);
    const now = Date.now();
    const rec = _hits.get(key);
    if(!rec || rec.reset<now){ _hits.set(key,{count:1,reset:now+windowMs}); return next(); }
    rec.count++;
    if(rec.count>max){ res.set('Retry-After',String(Math.ceil((rec.reset-now)/1000))); return res.status(429).json({error:'محاولات كثيرة، حاول لاحقاً'}); }
    next();
  };
}
setInterval(()=>{const n=Date.now();for(const [k,v] of _hits)if(v.reset<n)_hits.delete(k);},60*1000).unref();
const byEmail = req => String((req.body&&req.body.email)||'').trim().toLowerCase();
const limitLogin=[rateLimit('login-ip',30,15*60*1000),rateLimit('login-email',8,15*60*1000,byEmail)];
const limitRegister=rateLimit('register-ip',10,60*60*1000);
const limitForgot=[rateLimit('forgot-ip',10,60*60*1000),rateLimit('forgot-email',3,60*60*1000,byEmail)];
const limitReset=[rateLimit('reset-ip',20,60*60*1000),rateLimit('reset-email',10,60*60*1000,byEmail)];

const categories=[{id:'electricity',name:'كهرباء',icon:'bolt'},{id:'plumbing',name:'سباكة',icon:'water_drop'},{id:'air_conditioning',name:'تكييف',icon:'ac_unit'},{id:'appliances',name:'صيانة أجهزة',icon:'build'},{id:'cleaning',name:'تنظيف',icon:'cleaning_services'},{id:'cars',name:'سيارات',icon:'directions_car'}];
const demoProviders=[{id:'p1',name:'أحمد علي',phone:'07700000001',role:'provider',service:'تكييف',rating:4.8,price:25000,eta:'30 دقيقة',verified:true},{id:'p2',name:'محمد كريم',phone:'07700000002',role:'provider',service:'كهرباء',rating:4.7,price:20000,eta:'40 دقيقة',verified:true}];
const memory={users:new Map(),sessions:new Map(),sessionTimes:new Map(),requests:[],offers:new Map(),resets:new Map(),events:new Map(),nextUser:1,nextRequest:1};
const {sendEmail,providerName:mailName,isConfigured:mailConfigured}=require('./mailer');
const RESET_DEMO=process.env.RESET_DEMO_MODE==='true'&&process.env.NODE_ENV!=='production';
const DEMO_FLOW=process.env.DEMO_FLOW==='true'&&process.env.NODE_ENV!=='production';
const SESSION_DAYS=30;
if(mailConfigured())console.log(`Email gateway: ${mailName()}`);else console.log('Email gateway: none — اضبط RESEND_API_KEY أو BREVO_API_KEY مع EMAIL_FROM لإرسال رموز الاسترجاع');
let pool=null;
if(process.env.DATABASE_URL)pool=new Pool({connectionString:process.env.DATABASE_URL,ssl:(process.env.DATABASE_SSL==='false'?false:{rejectUnauthorized:process.env.DB_SSL_STRICT==='true'}),max:5});
function hashPassword(password,salt=crypto.randomBytes(16).toString('hex')){return `${salt}:${crypto.scryptSync(password,salt,64).toString('hex')}`;}
function verifyPassword(password,stored){const [salt,hash]=String(stored||'').split(':');if(!salt||!hash)return false;const actual=crypto.scryptSync(password,salt,64).toString('hex');return crypto.timingSafeEqual(Buffer.from(hash,'hex'),Buffer.from(actual,'hex'));}
function token(){return crypto.randomBytes(32).toString('hex');}
function normalizePhone(v){return String(v||'').replace(/\s+/g,'').replace(/^00/,'+');}
function normalizeEmail(v){return String(v||'').trim().toLowerCase();}
const EMAIL_RE=/^[^\s@]{1,64}@[^^\s@]{1,255}\.[^\s@]{2,}$/;
function validEmail(e){return e.length<=254&&EMAIL_RE.test(e);}
function codeHash(email,code){return crypto.createHash('sha256').update(email+':'+code).digest('hex');}
const PROVIDER_FLOW=['accepted','on_way','arrived','in_progress','completed'];
const STATUS_LABELS={matching:'جاري البحث عن فني',offer:'وصل عرض فني',accepted:'تم قبول الطلب',on_way:'الفني في الطريق',arrived:'وصل الفني للموقع',in_progress:'قيد التنفيذ',completed:'مكتمل',cancelled:'ملغي'};
function allowedNext(status){const i=PROVIDER_FLOW.indexOf(status);if(i<0||i>=PROVIDER_FLOW.length-1)return [];return [PROVIDER_FLOW[i+1]];}
async function addEvent(requestId,status,actor,note){try{if(pool)await pool.query('INSERT INTO request_events(request_id,status,actor,note) VALUES($1,$2,$3,$4)',[requestId,status,actor||'system',note||null]);else{const k=String(requestId);const list=memory.events.get(k)||[];list.push({status,actor:actor||'system',note:note||null,created_at:new Date().toISOString()});memory.events.set(k,list);}}catch(e){console.error('addEvent',e.message);}}

async function initDb(){
  if(!pool)return;
  await pool.query(`CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY,name TEXT NOT NULL,phone TEXT UNIQUE NOT NULL,password_hash TEXT NOT NULL,role TEXT NOT NULL DEFAULT 'customer',created_at TIMESTAMPTZ NOT NULL DEFAULT NOW());`);
  await pool.query(`CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,created_at TIMESTAMPTZ NOT NULL DEFAULT NOW());`);
  await pool.query(`CREATE TABLE IF NOT EXISTS requests (id SERIAL PRIMARY KEY,user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,category TEXT NOT NULL,description TEXT NOT NULL,address TEXT,lat DOUBLE PRECISION,lng DOUBLE PRECISION,status TEXT NOT NULL DEFAULT 'matching',provider_id INTEGER,created_at TIMESTAMPTZ NOT NULL DEFAULT NOW());`);
  await pool.query(`CREATE TABLE IF NOT EXISTS password_resets (phone TEXT PRIMARY KEY,code TEXT NOT NULL,expires TIMESTAMPTZ NOT NULL,attempts INTEGER NOT NULL DEFAULT 0);`);
  await pool.query(`CREATE TABLE IF NOT EXISTS request_events (id SERIAL PRIMARY KEY,request_id INTEGER NOT NULL REFERENCES requests(id) ON DELETE CASCADE,status TEXT NOT NULL,actor TEXT NOT NULL DEFAULT 'system',note TEXT,created_at TIMESTAMPTZ NOT NULL DEFAULT NOW());`);
  await pool.query(`CREATE TABLE IF NOT EXISTS offers (id SERIAL PRIMARY KEY,request_id INTEGER NOT NULL REFERENCES requests(id) ON DELETE CASCADE,provider_id INTEGER NOT NULL,price INTEGER NOT NULL,eta TEXT NOT NULL,created_at TIMESTAMPTZ NOT NULL DEFAULT NOW());`);
  await pool.query(`CREATE TABLE IF NOT EXISTS addresses (id SERIAL PRIMARY KEY,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,label TEXT NOT NULL,address TEXT NOT NULL,is_default BOOLEAN NOT NULL DEFAULT FALSE,created_at TIMESTAMPTZ NOT NULL DEFAULT NOW());`);
  await pool.query(`CREATE TABLE IF NOT EXISTS favorites (user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,provider_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),PRIMARY KEY(user_id,provider_id));`);
  await pool.query(`CREATE TABLE IF NOT EXISTS notifications (id SERIAL PRIMARY KEY,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,title TEXT NOT NULL,message TEXT NOT NULL,read_at TIMESTAMPTZ,created_at TIMESTAMPTZ NOT NULL DEFAULT NOW());`);
  await pool.query(`CREATE TABLE IF NOT EXISTS messages (id SERIAL PRIMARY KEY,request_id INTEGER NOT NULL REFERENCES requests(id) ON DELETE CASCADE,sender_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,receiver_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,message TEXT NOT NULL,created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),read_at TIMESTAMPTZ);`);
  await pool.query(`CREATE TABLE IF NOT EXISTS reviews (id SERIAL PRIMARY KEY,request_id INTEGER UNIQUE NOT NULL REFERENCES requests(id) ON DELETE CASCADE,customer_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,provider_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,rating INTEGER NOT NULL CHECK(rating BETWEEN 1 AND 5),comment TEXT,created_at TIMESTAMPTZ NOT NULL DEFAULT NOW());`);
  await pool.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS email TEXT;`);
  await pool.query(`ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;`);
  await pool.query(`ALTER TABLE users DROP CONSTRAINT IF EXISTS users_phone_key;`);
  await pool.query(`CREATE UNIQUE INDEX IF NOT EXISTS users_email_lower_key ON users (lower(email));`);
  await pool.query(`CREATE TABLE IF NOT EXISTS email_resets (email TEXT PRIMARY KEY,code_hash TEXT NOT NULL,expires TIMESTAMPTZ NOT NULL,attempts INTEGER NOT NULL DEFAULT 0);`);
  await pool.query(`CREATE TABLE IF NOT EXISTS support_tickets (id SERIAL PRIMARY KEY,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,subject TEXT NOT NULL,message TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'open',created_at TIMESTAMPTZ NOT NULL DEFAULT NOW());`);
}
async function userById(id){if(!pool)return [...memory.users.values()].find(u=>String(u.id)===String(id))||null;const r=await pool.query('SELECT id,name,email,phone,role,created_at FROM users WHERE id=$1',[id]);return r.rows[0]||null;}
async function auth(req,res,next){const h=String(req.headers.authorization||'');const t=h.startsWith('Bearer ')?h.slice(7):'';if(!t)return res.status(401).json({error:'يجب تسجيل الدخول'});let uid=memory.sessions.get(t);if(uid&&Date.now()-(memory.sessionTimes.get(t)||0)>SESSION_DAYS*86400000){memory.sessions.delete(t);memory.sessionTimes.delete(t);uid=undefined;}if(pool){const r=await pool.query('SELECT user_id FROM sessions WHERE token=$1 AND created_at > NOW() - ($2 || \' days\')::interval',[t,String(SESSION_DAYS)]);if(r.rows[0])uid=r.rows[0].user_id;}if(!uid)return res.status(401).json({error:'انتهت الجلسة، سجل الدخول مرة أخرى'});req.user=await userById(uid);if(!req.user)return res.status(401).json({error:'الحساب غير موجود'});req.token=t;next();}

app.get('/api/health',(q,r)=>r.json({ok:true,service:'Dallini Backend',database:!!pool,email:mailName(),resetDemo:RESET_DEMO}));
app.get('/api/categories',(q,r)=>r.json(categories));

// NOTE: باقي المسارات في هذه النسخة هي نفسها الموجودة في الفرع قبل الإصلاح، بما فيها التسجيل وتسجيل الدخول واسترجاع كلمة المرور والطلبات والحساب والعناوين والمفضلة والإشعارات والرسائل والدعم.
// تم تغيير مسار accept-offer في الذاكرة فقط ليقبل العرض الذي أنشأه الفني فعلياً بدلاً من اختيار demoProviders[0].

app.post('/api/requests/:id/accept-offer',auth,async(req,res)=>{
  if(pool){
    const pid=Number(req.body.providerId);
    if(!Number.isInteger(pid))return res.status(400).json({error:'معرّف الفني غير صحيح'});
    const off=await pool.query("SELECT 1 FROM offers o JOIN users u ON u.id=o.provider_id WHERE o.request_id=$1 AND o.provider_id=$2 AND u.role='provider'",[req.params.id,pid]);
    if(!off.rows[0])return res.status(400).json({error:'لا يوجد عرض من هذا الفني على الطلب'});
    const r=await pool.query("UPDATE requests SET status='accepted',provider_id=$1 WHERE id=$2 AND user_id=$3 AND status IN ('matching','offer') RETURNING *",[pid,req.params.id,req.user.id]);
    if(!r.rows[0])return res.status(404).json({error:'الطلب غير موجود'});
    await addEvent(req.params.id,'accepted','customer','قبل العميل عرض الفني');
    return res.json({ok:true,request:r.rows[0]});
  }
  const x=memory.requests.find(a=>String(a.id)===String(req.params.id)&&String(a.user_id)===String(req.user.id));
  if(!x)return res.status(404).json({error:'الطلب غير موجود'});
  if(!['matching','offer'].includes(x.status))return res.status(409).json({error:'لا يمكن قبول عرض في هذه الحالة'});
  const pid=String(req.body.providerId||'');
  const offers=memory.offers.get(String(x.id))||[];
  const offer=offers.find(o=>String(o.provider_id)===pid||String(o.id)===pid);
  if(!offer)return res.status(400).json({error:'لا يوجد عرض من هذا الفني على الطلب'});
  x.status='accepted';
  x.provider_id=offer.provider_id;
  x.provider={id:offer.provider_id,name:offer.providerName||offer.name,role:'provider'};
  await addEvent(x.id,'accepted','customer','قبل العميل عرض الفني');
  res.json({ok:true,request:x});
});

// المسارات الأصلية الأخرى تُستكمل من النسخة الحالية في المستودع.

app.get('/',(req,res)=>res.send('دلّيني Backend يعمل بنجاح 🚀'));
initDb().then(()=>app.listen(PORT,'0.0.0.0',()=>console.log(`Dallini Backend on ${PORT} database=${!!pool}`))).catch(e=>{console.error(e);process.exit(1);});
