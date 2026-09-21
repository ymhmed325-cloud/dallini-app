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
    if(rec.count>max){
      res.set('Retry-After', String(Math.ceil((rec.reset-now)/1000)));
      return res.status(429).json({error:'محاولات كثيرة، حاول لاحقاً'});
    }
    next();
  };
}
setInterval(()=>{const n=Date.now();for(const [k,v] of _hits)if(v.reset<n)_hits.delete(k);},60*1000).unref();
const byEmail = req => String((req.body&&req.body.email)||'').trim().toLowerCase();
const limitLogin    = [rateLimit('login-ip',30,15*60*1000), rateLimit('login-email',8,15*60*1000,byEmail)];
const limitRegister = rateLimit('register-ip',10,60*60*1000);
const limitForgot   = [rateLimit('forgot-ip',10,60*60*1000), rateLimit('forgot-email',3,60*60*1000,byEmail)];
const limitReset    = [rateLimit('reset-ip',20,60*60*1000), rateLimit('reset-email',10,60*60*1000,byEmail)];

const categories = [
  { id:'electricity', name:'كهرباء', icon:'bolt' },
  { id:'plumbing', name:'سباكة', icon:'water_drop' },
  { id:'air_conditioning', name:'تكييف', icon:'ac_unit' },
  { id:'appliances', name:'صيانة أجهزة', icon:'build' },
  { id:'cleaning', name:'تنظيف', icon:'cleaning_services' },
  { id:'cars', name:'سيارات', icon:'directions_car' },
];
const demoProviders = [
  { id:'p1', name:'أحمد علي', phone:'07700000001', role:'provider', service:'تكييف', rating:4.8, price:25000, eta:'30 دقيقة', verified:true },
  { id:'p2', name:'محمد كريم', phone:'07700000002', role:'provider', service:'كهرباء', rating:4.7, price:20000, eta:'40 دقيقة', verified:true },
];
const memory = { users:new Map(), sessions:new Map(), sessionTimes:new Map(), requests:[], offers:new Map(), resets:new Map(), events:new Map(), nextUser:1, nextRequest:1 };
const { sendEmail, providerName: mailName, isConfigured: mailConfigured } = require('./mailer');
// وضع التجربة: يُعاد رمز التحقق في الاستجابة.
// وضع التجربة (devCode) لا يعمل إلا بضبط RESET_DEMO_MODE=true خارج الإنتاج.
// وضع التجربة يُفعَّل فقط بضبط RESET_DEMO_MODE=true صراحةً، ولا يعمل أبداً مع NODE_ENV=production.
const RESET_DEMO = process.env.RESET_DEMO_MODE === 'true' && process.env.NODE_ENV !== 'production';
// مسار /next الخاص بالعميل (محاكاة) معطّل إلا بضبط DEMO_FLOW=true
const DEMO_FLOW = process.env.DEMO_FLOW === 'true' && process.env.NODE_ENV !== 'production';
const SESSION_DAYS = 30;
if (mailConfigured()) console.log(`Email gateway: ${mailName()}`);
else console.log('Email gateway: none — اضبط RESEND_API_KEY أو BREVO_API_KEY مع EMAIL_FROM لإرسال رموز الاسترجاع');
let pool = null;
if (process.env.DATABASE_URL) pool = new Pool({ connectionString:process.env.DATABASE_URL, ssl:(process.env.DATABASE_SSL==='false'?false:{rejectUnauthorized:process.env.DB_SSL_STRICT==='true'}), max:5 });

function hashPassword(password,salt=crypto.randomBytes(16).toString('hex')){return `${salt}:${crypto.scryptSync(password,salt,64).toString('hex')}`;}
function verifyPassword(password,stored){const [salt,hash]=String(stored||'').split(':');if(!salt||!hash)return false;const actual=crypto.scryptSync(password,salt,64).toString('hex');return crypto.timingSafeEqual(Buffer.from(hash,'hex'),Buffer.from(actual,'hex'));}
function token(){return crypto.randomBytes(32).toString('hex');}
function normalizePhone(v){return String(v||'').replace(/\s+/g,'').replace(/^00/,'+');}
function normalizeEmail(v){return String(v||'').trim().toLowerCase();}
const EMAIL_RE=/^[^\s@]{1,64}@[^\s@]{1,255}\.[^\s@]{2,}$/;
function validEmail(e){return e.length<=254&&EMAIL_RE.test(e);}
function codeHash(email,code){return crypto.createHash('sha256').update(email+':'+code).digest('hex');}
const PROVIDER_FLOW = ['accepted','on_way','arrived','in_progress','completed'];
const STATUS_LABELS = {matching:'جاري البحث عن فني',offer:'وصل عرض فني',accepted:'تم قبول الطلب',on_way:'الفني في الطريق',arrived:'وصل الفني للموقع',in_progress:'قيد التنفيذ',completed:'مكتمل',cancelled:'ملغي'};
function allowedNext(status){const i=PROVIDER_FLOW.indexOf(status);if(i<0||i>=PROVIDER_FLOW.length-1)return [];return [PROVIDER_FLOW[i+1]];}
async function addEvent(requestId,status,actor,note){
  try{
    if(pool){await pool.query('INSERT INTO request_events(request_id,status,actor,note) VALUES($1,$2,$3,$4)',[requestId,status,actor||'system',note||null]);}
    else{const k=String(requestId);const list=memory.events.get(k)||[];list.push({status,actor:actor||'system',note:note||null,created_at:new Date().toISOString()});memory.events.set(k,list);}
  }catch(e){console.error('addEvent',e.message);}
}

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

app.post('/api/auth/register',limitRegister,async(req,res)=>{try{
  const name=String(req.body.name||'').trim(),email=normalizeEmail(req.body.email),password=String(req.body.password||''),role=req.body.role==='provider'?'provider':'customer';
  const phoneRaw=normalizePhone(req.body.phone),phone=phoneRaw?phoneRaw:null;
  if(name.length<2)return res.status(400).json({error:'اكتب اسمك'});
  if(!validEmail(email))return res.status(400).json({error:'أدخل بريداً إلكترونياً صحيحاً'});
  if(phone&&phone.length<9)return res.status(400).json({error:'رقم الهاتف غير صحيح'});
  if(password.length<6)return res.status(400).json({error:'كلمة المرور يجب أن تكون 6 أحرف على الأقل'});
  let user,id;
  if(pool){
    if((await pool.query('SELECT id FROM users WHERE lower(email)=$1',[email])).rows[0])return res.status(409).json({error:'البريد الإلكتروني مستخدم مسبقاً'});
    const r=await pool.query('INSERT INTO users(name,email,phone,password_hash,role) VALUES($1,$2,$3,$4,$5) RETURNING id,name,email,phone,role,created_at',[name,email,phone,hashPassword(password),role]);
    user=r.rows[0];id=user.id;
  }else{
    if([...memory.users.values()].some(u=>u.email===email))return res.status(409).json({error:'البريد الإلكتروني مستخدم مسبقاً'});
    id=memory.nextUser++;user={id,name,email,phone,role,created_at:new Date().toISOString()};memory.users.set(id,{...user,password_hash:hashPassword(password)});
  }
  const t=token();
  if(pool)await pool.query('INSERT INTO sessions(token,user_id) VALUES($1,$2)',[t,id]);else (memory.sessions.set(t,id),memory.sessionTimes.set(t,Date.now()));
  res.status(201).json({token:t,user});
}catch(e){console.error(e);res.status(500).json({error:'تعذر إنشاء الحساب'});}});

app.post('/api/auth/login',limitLogin,async(req,res)=>{try{
  const email=normalizeEmail(req.body.email),password=String(req.body.password||'');
  let row;
  if(pool)row=(await pool.query('SELECT * FROM users WHERE lower(email)=$1',[email])).rows[0];
  else row=[...memory.users.values()].find(u=>u.email===email);
  if(!row||!verifyPassword(password,row.password_hash))return res.status(401).json({error:'البريد الإلكتروني أو كلمة المرور غير صحيحة'});
  const t=token();
  if(pool)await pool.query('INSERT INTO sessions(token,user_id) VALUES($1,$2)',[t,row.id]);else (memory.sessions.set(t,row.id),memory.sessionTimes.set(t,Date.now()));
  res.json({token:t,user:{id:row.id,name:row.name,email:row.email,phone:row.phone,role:row.role}});
}catch(e){console.error(e);res.status(500).json({error:'تعذر تسجيل الدخول'});}});

function resetCode(){return String(crypto.randomInt(100000,1000000));}
const RESET_MINUTES=10;
app.post('/api/auth/forgot-password',limitForgot,async(req,res)=>{try{
  const email=normalizeEmail(req.body.email);
  if(!validEmail(email))return res.status(400).json({error:'أدخل بريداً إلكترونياً صحيحاً'});
  // رد موحّد سواء كان البريد مسجلاً أم لا (منعاً لكشف الحسابات)
  const generic={ok:true,message:'إن كان البريد مسجلاً فسيصلك رمز التحقق خلال دقائق'};
  let exists=false;
  if(pool)exists=!!(await pool.query('SELECT 1 FROM users WHERE lower(email)=$1',[email])).rows[0];
  else exists=[...memory.users.values()].some(u=>u.email===email);
  if(!exists)return res.json(generic);

  // مهلة 60 ثانية بين رمزين لنفس البريد
  let prev;
  if(pool)prev=(await pool.query('SELECT expires FROM email_resets WHERE email=$1',[email])).rows[0];
  else{const m=memory.resets.get(email);prev=m?{expires:new Date(m.expires)}:null;}
  if(prev&&new Date(prev.expires).getTime()>Date.now()+(RESET_MINUTES*60-60)*1000)return res.json(generic);

  const code=resetCode(),expires=new Date(Date.now()+RESET_MINUTES*60*1000),h=codeHash(email,code);
  if(pool)await pool.query('INSERT INTO email_resets(email,code_hash,expires,attempts) VALUES($1,$2,$3,0) ON CONFLICT (email) DO UPDATE SET code_hash=$2,expires=$3,attempts=0',[email,h,expires]);
  else memory.resets.set(email,{code_hash:h,expires:expires.getTime(),attempts:0});

  const delivery=await sendEmail(email,'رمز استرجاع كلمة المرور - دلّيني',`رمز استرجاع كلمة المرور في تطبيق دلّيني: ${code}\nصالح لمدة ${RESET_MINUTES} دقائق.\nإذا لم تطلب هذا الرمز فتجاهل الرسالة.`);
  if(!delivery.sent){
    console.error('email delivery failed',delivery.gateway,delivery.reason);
    if(!RESET_DEMO)return res.json(generic);
  }
  const body={...generic};
  if(RESET_DEMO)body.devCode=code;
  res.json(body);
}catch(e){console.error(e);res.status(500).json({error:'تعذر إنشاء رمز التحقق'});}});

app.post('/api/auth/reset-password',limitReset,async(req,res)=>{try{
  const email=normalizeEmail(req.body.email),code=String(req.body.code||'').trim(),newPassword=String(req.body.newPassword||req.body.password||'');
  if(!validEmail(email))return res.status(400).json({error:'أدخل بريداً إلكترونياً صحيحاً'});
  if(code.length!==6)return res.status(400).json({error:'أدخل رمز التحقق المكوّن من 6 أرقام'});
  if(newPassword.length<6)return res.status(400).json({error:'كلمة المرور يجب أن تكون 6 أحرف على الأقل'});

  let row;
  if(pool)row=(await pool.query('SELECT * FROM email_resets WHERE email=$1',[email])).rows[0];
  else{const m=memory.resets.get(email);row=m?{code_hash:m.code_hash,expires:new Date(m.expires),attempts:m.attempts}:null;}
  if(!row)return res.status(400).json({error:'اطلب رمز التحقق أولاً'});
  if(new Date(row.expires).getTime()<Date.now())return res.status(400).json({error:'انتهت صلاحية الرمز، اطلب رمزاً جديداً'});
  if(Number(row.attempts)>=5)return res.status(429).json({error:'محاولات كثيرة، اطلب رمزاً جديداً'});

  const a=Buffer.from(String(row.code_hash),'hex'),b=Buffer.from(codeHash(email,code),'hex');
  const approved=a.length===b.length&&crypto.timingSafeEqual(a,b);
  if(!approved){
    if(pool)await pool.query('UPDATE email_resets SET attempts=attempts+1 WHERE email=$1',[email]);
    else{const m=memory.resets.get(email);if(m)m.attempts+=1;}
    return res.status(400).json({error:'رمز التحقق غير صحيح'});
  }

  const hash=hashPassword(newPassword);
  if(pool){
    const r=await pool.query('UPDATE users SET password_hash=$1 WHERE lower(email)=$2 RETURNING id',[hash,email]);
    if(!r.rows[0])return res.status(400).json({error:'رمز التحقق غير صحيح'});
    await pool.query('DELETE FROM sessions WHERE user_id=$1',[r.rows[0].id]);
    await pool.query('DELETE FROM email_resets WHERE email=$1',[email]);
  }else{
    const found=[...memory.users.entries()].find(([,v])=>v.email===email);
    if(!found)return res.status(400).json({error:'رمز التحقق غير صحيح'});
    memory.users.set(found[0],{...found[1],password_hash:hash});
    for(const [t,uid] of [...memory.sessions.entries()])if(String(uid)===String(found[0]))memory.sessions.delete(t);
    memory.resets.delete(email);
  }
  res.json({ok:true,message:'تم تغيير كلمة المرور، يمكنك تسجيل الدخول الآن'});
}catch(e){console.error(e);res.status(500).json({error:'تعذر تغيير كلمة المرور'});}});

app.post('/api/auth/change-password',auth,async(req,res)=>{const current=String(req.body.currentPassword||''),next=String(req.body.newPassword||'');if(next.length<6)return res.status(400).json({error:'كلمة المرور الجديدة يجب أن تكون 6 أحرف على الأقل'});try{let row;if(pool)row=(await pool.query('SELECT * FROM users WHERE id=$1',[req.user.id])).rows[0];else row=[...memory.users.values()].find(u=>String(u.id)===String(req.user.id));if(!row||!verifyPassword(current,row.password_hash))return res.status(401).json({error:'كلمة المرور الحالية غير صحيحة'});const h=hashPassword(next);if(pool){await pool.query('UPDATE users SET password_hash=$1 WHERE id=$2',[h,req.user.id]);await pool.query('DELETE FROM sessions WHERE user_id=$1 AND token<>$2',[req.user.id,req.token]);}else{memory.users.set(req.user.id,{...row,password_hash:h});for(const [t,uid] of [...memory.sessions.entries()])if(String(uid)===String(req.user.id)&&t!==req.token)memory.sessions.delete(t);}res.json({ok:true,message:'تم تغيير كلمة المرور'});}catch(e){res.status(500).json({error:'تعذر تغيير كلمة المرور'});}});
app.get('/api/auth/me',auth,(req,res)=>res.json({user:req.user}));
app.post('/api/auth/logout',auth,async(req,res)=>{if(pool)await pool.query('DELETE FROM sessions WHERE token=$1',[req.token]);else memory.sessions.delete(req.token);res.json({ok:true});});

app.post('/api/requests',auth,async(req,res)=>{try{const category=String(req.body.category||'كهرباء'),description=String(req.body.description||'').trim();if(description.length<4)return res.status(400).json({error:'اكتب وصف المشكلة'});const address=String(req.body.address||'').trim().slice(0,300)||null;const _lat=req.body.lat==null?null:Number(req.body.lat),_lng=req.body.lng==null?null:Number(req.body.lng);if((_lat!==null&&!(_lat>=-90&&_lat<=90))||(_lng!==null&&!(_lng>=-180&&_lng<=180)))return res.status(400).json({error:'الإحداثيات غير صحيحة'});const lat=_lat,lng=_lng;if(description.length>2000)return res.status(400).json({error:'الوصف طويل جداً'});let x;if(pool)x=(await pool.query('INSERT INTO requests(user_id,category,description,address,lat,lng) VALUES($1,$2,$3,$4,$5,$6) RETURNING *',[req.user.id,category,description,address,lat,lng])).rows[0];else{x={id:String(memory.nextRequest++),user_id:req.user.id,category,description,address,lat,lng,status:'matching',created_at:new Date().toISOString()};memory.requests.unshift(x);memory.offers.set(x.id,[]);}await addEvent(x.id,'matching','customer','تم إنشاء الطلب');res.status(201).json(x);}catch(e){console.error(e);res.status(500).json({error:'تعذر إنشاء الطلب'});}});
app.get('/api/requests/mine',auth,async(req,res)=>{if(pool)return res.json((await pool.query('SELECT * FROM requests WHERE user_id=$1 ORDER BY created_at DESC',[req.user.id])).rows);res.json(memory.requests.filter(x=>String(x.user_id)===String(req.user.id)));});
app.get('/api/requests/:id',auth,async(req,res)=>{if(pool){const r=await pool.query('SELECT * FROM requests WHERE id=$1 AND user_id=$2',[req.params.id,req.user.id]);if(!r.rows[0])return res.status(404).json({error:'الطلب غير موجود'});return res.json(r.rows[0]);}const x=memory.requests.find(a=>String(a.id)===String(req.params.id)&&String(a.user_id)===String(req.user.id));if(!x)return res.status(404).json({error:'الطلب غير موجود'});res.json(x);});
app.post('/api/requests/:id/offers',auth,async(req,res)=>{try{
  if(req.user.role!=='provider')return res.status(403).json({error:'هذا المسار للفنيين'});
  const price=Number(req.body.price), eta=String(req.body.eta||'').trim();
  if(!Number.isInteger(price)||price<=0||price>100000000)return res.status(400).json({error:'السعر غير صحيح'});
  if(!eta||eta.length>80)return res.status(400).json({error:'وقت الوصول غير صحيح'});
  if(pool){
    const requestRow=(await pool.query("SELECT id,status FROM requests WHERE id=$1 AND status IN ('matching','offer')",[req.params.id])).rows[0];
    if(!requestRow)return res.status(404).json({error:'الطلب غير متاح لتقديم عرض'});
    const existing=(await pool.query('SELECT id FROM offers WHERE request_id=$1 AND provider_id=$2',[req.params.id,req.user.id])).rows[0];
    if(existing)return res.status(409).json({error:'لديك عرض سابق على هذا الطلب'});
    const r=await pool.query('INSERT INTO offers(request_id,provider_id,price,eta) VALUES($1,$2,$3,$4) RETURNING id,request_id,provider_id,price,eta,created_at',[req.params.id,req.user.id,price,eta]);
    if(requestRow.status==='matching')await pool.query("UPDATE requests SET status='offer' WHERE id=$1 AND status='matching'",[req.params.id]);
    await addEvent(req.params.id,'offer','provider',`الفني ${req.user.name} أرسل عرضاً`);
    return res.status(201).json({ok:true,offer:r.rows[0]});
  }
  const x=memory.requests.find(a=>String(a.id)===String(req.params.id)&&['matching','offer'].includes(a.status));
  if(!x)return res.status(404).json({error:'الطلب غير متاح لتقديم عرض'});
  const list=memory.offers.get(String(x.id))||[];
  if(list.some(o=>String(o.provider_id||o.id)===String(req.user.id)))return res.status(409).json({error:'لديك عرض سابق على هذا الطلب'});
  const offer={id:`${Date.now()}-${req.user.id}`,request_id:x.id,provider_id:req.user.id,name:req.user.name,providerName:req.user.name,price,eta,etaMinutes:eta,created_at:new Date().toISOString()};
  list.push(offer);memory.offers.set(String(x.id),list);x.status='offer';await addEvent(x.id,'offer','provider',`الفني ${req.user.name} أرسل عرضاً`);
  res.status(201).json({ok:true,offer});
}catch(e){console.error(e);res.status(500).json({error:'تعذر إنشاء العرض'});}});

app.get('/api/requests/:id/offers',auth,async(req,res)=>{if(pool){const own=await pool.query('SELECT id FROM requests WHERE id=$1 AND user_id=$2',[req.params.id,req.user.id]);if(!own.rows[0])return res.status(404).json({error:'الطلب غير موجود'});return res.json((await pool.query("SELECT o.id,o.request_id,o.provider_id,u.name AS providerName,o.price,o.eta,o.eta AS \"etaMinutes\",o.created_at FROM offers o LEFT JOIN users u ON u.id=o.provider_id WHERE o.request_id=$1 ORDER BY o.created_at ASC",[req.params.id])).rows);}res.json((memory.offers.get(String(req.params.id))||[]).map(o=>({...o,providerName:o.providerName||o.name,etaMinutes:o.etaMinutes||o.eta})));});
app.post('/api/requests/:id/accept-offer',auth,async(req,res)=>{if(pool){const pid=Number(req.body.providerId);if(!Number.isInteger(pid))return res.status(400).json({error:'معرّف الفني غير صحيح'});const off=await pool.query('SELECT 1 FROM offers o JOIN users u ON u.id=o.provider_id WHERE o.request_id=$1 AND o.provider_id=$2 AND u.role=\'provider\'',[req.params.id,pid]);if(!off.rows[0])return res.status(400).json({error:'لا يوجد عرض من هذا الفني على الطلب'});const r=await pool.query("UPDATE requests SET status='accepted',provider_id=$1 WHERE id=$2 AND user_id=$3 AND status IN ('matching','offer') RETURNING *",[pid,req.params.id,req.user.id]);if(!r.rows[0])return res.status(404).json({error:'الطلب غير موجود'});await addEvent(req.params.id,'accepted','customer','قبل العميل عرض الفني');return res.json({ok:true,request:r.rows[0]});}const x=memory.requests.find(a=>String(a.id)===String(req.params.id)&&String(a.user_id)===String(req.user.id));if(!x)return res.status(404).json({error:'الطلب غير موجود'});if(!['matching','offer'].includes(x.status))return res.status(409).json({error:'لا يمكن قبول عرض في هذه الحالة'});const pid=String(req.body.providerId||'');const offers=memory.offers.get(String(x.id))||[];const offer=offers.find(o=>String(o.provider_id)===pid||String(o.id)===pid);if(!offer)return res.status(400).json({error:'لا يوجد عرض من هذا الفني على الطلب'});x.status='accepted';x.provider_id=offer.provider_id;x.provider={id:offer.provider_id,name:offer.providerName||offer.name,role:'provider'};await addEvent(x.id,'accepted','customer','قبل العميل عرض الفني');res.json({ok:true,request:x});});
app.post('/api/requests/:id/next',auth,async(req,res)=>{if(!DEMO_FLOW)return res.status(403).json({error:'غير متاح: يتقدّم الطلب عبر الفني فقط'});const flow=['matching','offer','accepted','on_way','arrived','in_progress','completed'];if(pool){const own=(await pool.query('SELECT * FROM requests WHERE id=$1 AND user_id=$2',[req.params.id,req.user.id])).rows[0];if(!own)return res.status(404).json({error:'الطلب غير موجود'});const i=Math.max(0,flow.indexOf(own.status)),status=flow[Math.min(flow.length-1,i+1)];const r=await pool.query('UPDATE requests SET status=$1 WHERE id=$2 RETURNING *',[status,req.params.id]);if(status==='offer')await pool.query('INSERT INTO offers(request_id,provider_id,price,eta) VALUES($1,$2,$3,$4)',[req.params.id,1,25000,'30 دقيقة']);await addEvent(req.params.id,status,'customer');return res.json({ok:true,request:r.rows[0]});}const x=memory.requests.find(a=>String(a.id)===String(req.params.id)&&String(a.user_id)===String(req.user.id));if(!x)return res.status(404).json({error:'الطلب غير موجود'});const i=Math.max(0,flow.indexOf(x.status));x.status=flow[Math.min(flow.length-1,i+1)];if(x.status==='offer')memory.offers.set(String(x.id),[demoProviders[0]]);await addEvent(x.id,x.status,'customer');res.json({ok:true,request:x,offers:memory.offers.get(String(x.id))||[]});});
app.post('/api/requests/:id/cancel',auth,async(req,res)=>{if(pool){const r=await pool.query("UPDATE requests SET status='cancelled' WHERE id=$1 AND user_id=$2 AND status<>'completed' RETURNING *",[req.params.id,req.user.id]);if(!r.rows[0])return res.status(409).json({error:'لا يمكن إلغاء الطلب'});return res.json({ok:true,request:r.rows[0]});}const x=memory.requests.find(a=>String(a.id)===String(req.params.id)&&String(a.user_id)===String(req.user.id));if(!x)return res.status(404).json({error:'الطلب غير موجود'});if(x.status==='completed')return res.status(409).json({error:'لا يمكن إلغاء طلب مكتمل'});x.status='cancelled';await addEvent(x.id,'cancelled','customer','ألغى العميل الطلب');res.json({ok:true,request:x});});

app.get('/api/providers/requests',auth,async(req,res)=>{if(req.user.role!=='provider')return res.status(403).json({error:'هذا القسم للفنيين'});if(pool)return res.json((await pool.query("SELECT id,category,description,status,created_at FROM requests WHERE status IN ('matching','offer') ORDER BY created_at DESC LIMIT 50")).rows);res.json(memory.requests.filter(x=>['matching','offer'].includes(x.status)).slice(0,50).map(x=>({id:x.id,category:x.category,description:x.description,status:x.status,created_at:x.created_at})));});
app.post('/api/providers/requests/:id/accept',auth,async(req,res)=>{if(req.user.role!=='provider')return res.status(403).json({error:'هذا القسم للفنيين'});if(pool){const r=await pool.query("UPDATE requests SET status='accepted',provider_id=$1 WHERE id=$2 AND status IN ('matching','offer') RETURNING *",[req.user.id,req.params.id]);if(!r.rows[0])return res.status(404).json({error:'الطلب غير متاح'});await addEvent(req.params.id,'accepted','provider',`الفني ${req.user.name} قبل الطلب`);return res.json({ok:true,request:r.rows[0]});}const x=memory.requests.find(a=>String(a.id)===String(req.params.id));if(!x)return res.status(404).json({error:'الطلب غير موجود'});x.status='accepted';x.provider={id:req.user.id,name:req.user.name};x.provider_id=req.user.id;await addEvent(x.id,'accepted','provider',`الفني ${req.user.name} قبل الطلب`);res.json({ok:true,request:x});});
app.get('/api/providers/jobs',auth,async(req,res)=>{if(req.user.role!=='provider')return res.status(403).json({error:'هذا القسم للفنيين'});const active=['accepted','on_way','arrived','in_progress'],history=['completed','cancelled'];const filter=String(req.query.filter||'active');const wanted=filter==='history'?history:(filter==='all'?active.concat(history):active);if(pool)return res.json((await pool.query('SELECT id,category,description,address,lat,lng,status,provider_id,created_at FROM requests WHERE provider_id=$1 AND status=ANY($2) ORDER BY created_at DESC LIMIT 100',[req.user.id,wanted])).rows);res.json(memory.requests.filter(x=>String(x.provider_id)===String(req.user.id)&&wanted.includes(x.status)).slice(0,100).map(x=>({id:x.id,category:x.category,description:x.description,address:x.address,lat:x.lat,lng:x.lng,status:x.status,provider_id:x.provider_id,created_at:x.created_at})));});
app.post('/api/providers/requests/:id/status',auth,async(req,res)=>{try{if(req.user.role!=='provider')return res.status(403).json({error:'هذا القسم للفنيين'});const status=String(req.body.status||'');if(!PROVIDER_FLOW.includes(status))return res.status(400).json({error:'حالة غير صحيحة'});if(pool){const own=(await pool.query('SELECT * FROM requests WHERE id=$1 AND provider_id=$2',[req.params.id,req.user.id])).rows[0];if(!own)return res.status(404).json({error:'الطلب غير موجود أو غير مسند إليك'});const next=allowedNext(own.status);if(!next.includes(status))return res.status(409).json({error:`لا يمكن الانتقال من "${STATUS_LABELS[own.status]||own.status}" إلى "${STATUS_LABELS[status]||status}"`,current:own.status,allowedNext:next});const r=await pool.query('UPDATE requests SET status=$1 WHERE id=$2 RETURNING *',[status,req.params.id]);await addEvent(req.params.id,status,'provider');return res.json({ok:true,request:r.rows[0],allowedNext:allowedNext(status)});}const x=memory.requests.find(a=>String(a.id)===String(req.params.id)&&String(a.provider_id)===String(req.user.id));if(!x)return res.status(404).json({error:'الطلب غير موجود أو غير مسند إليك'});const next=allowedNext(x.status);if(!next.includes(status))return res.status(409).json({error:`لا يمكن الانتقال من "${STATUS_LABELS[x.status]||x.status}" إلى "${STATUS_LABELS[status]||status}"`,current:x.status,allowedNext:next});x.status=status;await addEvent(x.id,status,'provider');res.json({ok:true,request:x,allowedNext:allowedNext(status)});}catch(e){console.error(e);res.status(500).json({error:'تعذر تحديث حالة الطلب'});}});
app.get('/api/requests/:id/timeline',auth,async(req,res)=>{if(pool){const r=await pool.query('SELECT id,user_id,category,description,address,lat,lng,status,provider_id,created_at FROM requests WHERE id=$1',[req.params.id]);const x=r.rows[0];if(!x)return res.status(404).json({error:'الطلب غير موجود'});const isOwner=String(x.user_id)===String(req.user.id),isProvider=String(x.provider_id)===String(req.user.id);if(!isOwner&&!isProvider)return res.status(403).json({error:'لا تملك صلاحية عرض هذا الطلب'});const ev=(await pool.query('SELECT status,actor,note,created_at FROM request_events WHERE request_id=$1 ORDER BY created_at ASC',[req.params.id])).rows;const {user_id,...safeRequest}=x;return res.json({request:safeRequest,status:x.status,statusLabel:STATUS_LABELS[x.status]||x.status,allowedNext:allowedNext(x.status),events:ev.map(e=>({...e,statusLabel:STATUS_LABELS[e.status]||e.status}))});}const x=memory.requests.find(a=>String(a.id)===String(req.params.id));if(!x)return res.status(404).json({error:'الطلب غير موجود'});const isOwner=String(x.user_id)===String(req.user.id),isProvider=String(x.provider_id)===String(req.user.id);if(!isOwner&&!isProvider)return res.status(403).json({error:'لا تملك صلاحية عرض هذا الطلب'});const ev=memory.events.get(String(x.id))||[];const {user_id,...safeRequest}=x;res.json({request:safeRequest,status:x.status,statusLabel:STATUS_LABELS[x.status]||x.status,allowedNext:allowedNext(x.status),events:ev.map(e=>({...e,statusLabel:STATUS_LABELS[e.status]||e.status}))});});

// الحساب والعناوين والمفضلة والإشعارات والرسائل والدعم
app.get('/api/profile',auth,async(req,res)=>{try{if(pool){const r=await pool.query('SELECT id,name,email,phone,role,created_at FROM users WHERE id=$1',[req.user.id]);return res.json({user:r.rows[0]});}res.json({user:req.user});}catch(e){res.status(500).json({error:'تعذر تحميل الملف الشخصي'});}});
app.put('/api/profile',auth,async(req,res)=>{try{const name=String(req.body.name||'').trim();if(name.length<2)return res.status(400).json({error:'الاسم غير صحيح'});const ph=req.body.phone===undefined?null:normalizePhone(req.body.phone);if(ph&&ph.length<9)return res.status(400).json({error:'رقم الهاتف غير صحيح'});if(pool){const r=await pool.query('UPDATE users SET name=$1,phone=COALESCE($3,phone) WHERE id=$2 RETURNING id,name,email,phone,role,created_at',[name,req.user.id,ph||null]);return res.json({user:r.rows[0]});}const u=[...memory.users.values()].find(x=>String(x.id)===String(req.user.id));if(!u)return res.status(404).json({error:'الحساب غير موجود'});u.name=name;if(ph)u.phone=ph;res.json({user:{id:u.id,name:u.name,email:u.email,phone:u.phone,role:u.role,created_at:u.created_at}});}catch(e){res.status(500).json({error:'تعذر تحديث الملف الشخصي'});}});
app.get('/api/addresses',auth,async(req,res)=>{if(pool)return res.json((await pool.query('SELECT * FROM addresses WHERE user_id=$1 ORDER BY is_default DESC,created_at DESC',[req.user.id])).rows);res.json((memory.addresses||new Map()).get(String(req.user.id))||[]);});
app.post('/api/addresses',auth,async(req,res)=>{const label=String(req.body.label||'المنزل').trim(),address=String(req.body.address||'').trim();if(!address)return res.status(400).json({error:'اكتب العنوان'});try{if(pool){if(req.body.isDefault)await pool.query('UPDATE addresses SET is_default=false WHERE user_id=$1',[req.user.id]);const r=await pool.query('INSERT INTO addresses(user_id,label,address,is_default) VALUES($1,$2,$3,$4) RETURNING *',[req.user.id,label,address,!!req.body.isDefault]);return res.status(201).json(r.rows[0]);}if(!memory.addresses)memory.addresses=new Map();const list=memory.addresses.get(String(req.user.id))||[];if(req.body.isDefault)list.forEach(x=>x.is_default=false);const x={id:crypto.randomUUID(),label,address,is_default:!!req.body.isDefault,created_at:new Date().toISOString()};list.unshift(x);memory.addresses.set(String(req.user.id),list);res.status(201).json(x);}catch(e){res.status(500).json({error:'تعذر حفظ العنوان'});}});
app.delete('/api/addresses/:id',auth,async(req,res)=>{try{if(pool){const r=await pool.query('DELETE FROM addresses WHERE id=$1 AND user_id=$2 RETURNING id',[req.params.id,req.user.id]);if(!r.rows[0])return res.status(404).json({error:'العنوان غير موجود'});return res.json({ok:true});}const list=(memory.addresses?.get(String(req.user.id))||[]).filter(x=>String(x.id)!==String(req.params.id));if(memory.addresses)memory.addresses.set(String(req.user.id),list);res.json({ok:true});}catch(e){res.status(500).json({error:'تعذر حذف العنوان'});}});
app.get('/api/favorites',auth,async(req,res)=>{try{if(pool)return res.json((await pool.query("SELECT u.id,u.name,u.phone,u.role FROM favorites f JOIN users u ON u.id=f.provider_id WHERE f.user_id=$1 ORDER BY f.created_at DESC",[req.user.id])).rows);res.json((memory.favorites?.get(String(req.user.id))||[]));}catch(e){res.status(500).json({error:'تعذر تحميل المفضلة'});}});
app.post('/api/favorites/:providerId',auth,async(req,res)=>{try{if(pool){await pool.query('INSERT INTO favorites(user_id,provider_id) VALUES($1,$2) ON CONFLICT DO NOTHING',[req.user.id,req.params.providerId]);return res.json({ok:true});}if(!memory.favorites)memory.favorites=new Map();const list=memory.favorites.get(String(req.user.id))||[];if(!list.some(x=>String(x.id)===String(req.params.providerId)))list.push({id:req.params.providerId,name:'فني',role:'provider'});memory.favorites.set(String(req.user.id),list);res.json({ok:true});}catch(e){res.status(500).json({error:'تعذر إضافة الفني للمفضلة'});}});
app.delete('/api/favorites/:providerId',auth,async(req,res)=>{try{if(pool){await pool.query('DELETE FROM favorites WHERE user_id=$1 AND provider_id=$2',[req.user.id,req.params.providerId]);return res.json({ok:true});}const list=(memory.favorites?.get(String(req.user.id))||[]).filter(x=>String(x.id)!==String(req.params.providerId));if(memory.favorites)memory.favorites.set(String(req.user.id),list);res.json({ok:true});}catch(e){res.status(500).json({error:'تعذر إزالة الفني من المفضلة'});}});
app.get('/api/notifications',auth,async(req,res)=>{try{if(pool)return res.json((await pool.query('SELECT * FROM notifications WHERE user_id=$1 ORDER BY created_at DESC LIMIT 100',[req.user.id])).rows);res.json((memory.notifications?.get(String(req.user.id))||[{id:'1',title:'دلّيني',message:'ستظهر هنا تحديثات الطلب والعروض الجديدة.'}]));}catch(e){res.status(500).json({error:'تعذر تحميل الإشعارات'});}});
app.patch('/api/notifications/:id/read',auth,async(req,res)=>{try{if(pool){await pool.query('UPDATE notifications SET read_at=NOW() WHERE id=$1 AND user_id=$2',[req.params.id,req.user.id]);return res.json({ok:true});}res.json({ok:true});}catch(e){res.status(500).json({error:'تعذر تحديث الإشعار'});}});
app.get('/api/messages/:requestId',auth,async(req,res)=>{try{if(pool){const q=await pool.query('SELECT * FROM requests WHERE id=$1',[req.params.requestId]);const x=q.rows[0];if(!x)return res.status(404).json({error:'الطلب غير موجود'});if(String(x.user_id)!==String(req.user.id)&&String(x.provider_id)!==String(req.user.id))return res.status(403).json({error:'لا تملك صلاحية المحادثة'});return res.json((await pool.query('SELECT id,request_id,sender_id,receiver_id,message,created_at,read_at FROM messages WHERE request_id=$1 ORDER BY created_at ASC',[req.params.requestId])).rows);}res.json([]);}catch(e){res.status(500).json({error:'تعذر تحميل المحادثة'});}});
app.post('/api/messages/:requestId',auth,async(req,res)=>{const message=String(req.body.message||'').trim();if(!message)return res.status(400).json({error:'اكتب الرسالة'});try{if(pool){const q=await pool.query('SELECT * FROM requests WHERE id=$1',[req.params.requestId]);const x=q.rows[0];if(!x)return res.status(404).json({error:'الطلب غير موجود'});const isCustomer=String(x.user_id)===String(req.user.id),isProvider=String(x.provider_id)===String(req.user.id);if(!isCustomer&&!isProvider)return res.status(403).json({error:'لا تملك صلاحية المحادثة'});const receiver=isCustomer?x.provider_id:x.user_id;if(!receiver)return res.status(409).json({error:'لم يتم ربط فني بالطلب بعد'});const r=await pool.query('INSERT INTO messages(request_id,sender_id,receiver_id,message) VALUES($1,$2,$3,$4) RETURNING *',[req.params.requestId,req.user.id,receiver,message]);await pool.query('INSERT INTO notifications(user_id,title,message) VALUES($1,$2,$3)',[receiver,'رسالة جديدة','لديك رسالة جديدة في طلبك']);return res.status(201).json(r.rows[0]);}return res.status(409).json({error:'المحادثة متاحة بعد ربط فني بالطلب'});}catch(e){res.status(500).json({error:'تعذر إرسال الرسالة'});}});
app.post('/api/reviews',auth,async(req,res)=>{const requestId=req.body.requestId,rating=Number(req.body.rating),comment=String(req.body.comment||'').trim();if(!requestId||rating<1||rating>5)return res.status(400).json({error:'التقييم غير صحيح'});try{if(pool){const q=await pool.query("SELECT * FROM requests WHERE id=$1 AND user_id=$2 AND status='completed'",[requestId,req.user.id]);const x=q.rows[0];if(!x||!x.provider_id)return res.status(409).json({error:'لا يمكن تقييم هذا الطلب الآن'});const r=await pool.query('INSERT INTO reviews(request_id,customer_id,provider_id,rating,comment) VALUES($1,$2,$3,$4,$5) ON CONFLICT(request_id) DO UPDATE SET rating=EXCLUDED.rating,comment=EXCLUDED.comment RETURNING *',[requestId,req.user.id,x.provider_id,rating,comment]);return res.status(201).json(r.rows[0]);}return res.status(201).json({ok:true});}catch(e){res.status(500).json({error:'تعذر حفظ التقييم'});}});
app.post('/api/support/tickets',auth,async(req,res)=>{const subject=String(req.body.subject||'مساعدة').trim(),message=String(req.body.message||'').trim();if(!message)return res.status(400).json({error:'اكتب تفاصيل المشكلة'});try{if(pool){const r=await pool.query('INSERT INTO support_tickets(user_id,subject,message) VALUES($1,$2,$3) RETURNING *',[req.user.id,subject,message]);return res.status(201).json(r.rows[0]);}res.status(201).json({id:crypto.randomUUID(),subject,message,status:'open'});}catch(e){res.status(500).json({error:'تعذر إرسال طلب الدعم'});}});

app.get('/',(req,res)=>res.send('دلّيني Backend يعمل بنجاح 🚀'));
initDb().then(()=>app.listen(PORT,'0.0.0.0',()=>console.log(`Dallini Backend on ${PORT} database=${!!pool}`))).catch(e=>{console.error(e);process.exit(1);});
