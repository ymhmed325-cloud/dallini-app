# مشروع دلّيني (Dallini)

تطبيق خدمات منزلية: يطلب المستخدم فنّي (كهرباء، سباكة، تكييف، صيانة أجهزة، تنظيف، سيارات)،
ويستقبل الفنّي الطلبات القريبة ويقبلها.

## المحتويات
- `backend/` — خادم Node.js/Express (توثيق بجلسات، عروض، حالات الطلب، استرجاع كلمة المرور، دعم PostgreSQL).
- `mobile_source/` — كود تطبيق Flutter (المصدر الأساسي).
- `mobile/` — مشروع Flutter المولَّد للبناء (يُنشأ بـ `flutter create`).
- `.github/workflows/build-apk.yml` — بناء APK تلقائي + نشر Release دائم.
- `.github/workflows/export-project.yml` — تصدير ملف المشروع كامل.
- `scripts/` — سكربتات البناء والتشغيل.
- `docker-compose.yml` — تشغيل الخادم مع PostgreSQL بأمر واحد.

> مصدر التطبيق المستخدم فعلياً في بناء الـAPK هو `mobile_source/lib/app_fixed.dart` (يُنسخ إلى `mobile/lib/main.dart`).

## تشغيل الخادم محلياً
```bash
cd backend
npm install
PORT=10000 node server.js
curl http://127.0.0.1:10000/api/health
```
بدون `DATABASE_URL` يعمل الخادم بذاكرة مؤقتة (in-memory) — مناسب للتجربة.

## تشغيل الخادم مع قاعدة بيانات (أمر واحد)
```bash
docker compose up --build
# الخادم على http://127.0.0.1:10000 وقاعدة PostgreSQL على المنفذ 5432
```

## الاختبار الدخاني
```bash
cd backend
npm test
```
يشغّل الخادم على منفذ مؤقت ويمرّ على: الحالة، الفئات، التسجيل، منع التكرار، الدخول،
استرجاع كلمة المرور (طلب رمز/رفض رمز خاطئ/تغيير/إبطال الجلسات القديمة)، إنشاء الطلب،
جلب الطلبات، وحجب قسم الفنيين عن المستخدم العادي.

## بناء تطبيق Flutter
```bash
flutter create --platforms=android --org com.dallini mobile
cp mobile_source/pubspec.yaml mobile/pubspec.yaml
cp mobile_source/lib/app_fixed.dart mobile/lib/main.dart
cd mobile
flutter pub get
flutter build apk --release --dart-define=API_URL=https://dallini-app.onrender.com
```
أو استخدم `bash scripts/build_apk.sh`. ناتج البناء: `mobile/build/app/outputs/flutter-apk/app-release.apk`

## الإصدارات (GitHub Releases)
سير العمل `Build Dallini APK` يبني الـAPK على كل رفع إلى `main`.
وعند تشغيله يدوياً (Actions ← Build Dallini APK ← Run workflow) ينشر أيضاً
**Release دائم** باسم `v1.1.0-build<N>` يحمل ملف `app-release.apk` كأصل (asset) لا ينتهي بعد 90 يوماً.

## واجهات الخادم (API)
| الطريقة | المسار | الوصف |
|---|---|---|
| GET | `/api/health` | فحص الحالة |
| GET | `/api/categories` | الفئات |
| POST | `/api/auth/register` | إنشاء حساب (`customer` أو `provider`) |
| POST | `/api/auth/login` | تسجيل الدخول |
| GET | `/api/auth/me` | بيانات الحساب |
| POST | `/api/auth/logout` | تسجيل الخروج |
| POST | `/api/auth/forgot-password` | طلب رمز تحقق لاسترجاع كلمة المرور |
| POST | `/api/auth/reset-password` | تغيير كلمة المرور بالرمز |
| POST | `/api/requests` | إنشاء طلب |
| GET | `/api/requests/mine` | طلبات المستخدم |
| GET | `/api/requests/:id` | تفاصيل طلب |
| GET | `/api/requests/:id/offers` | عروض الطلب |
| POST | `/api/requests/:id/accept-offer` | قبول عرض |
| POST | `/api/requests/:id/next` | تقديم حالة الطلب |
| POST | `/api/requests/:id/cancel` | إلغاء الطلب |
| GET | `/api/providers/requests` | طلبات متاحة للفنّي |
| POST | `/api/providers/requests/:id/accept` | الفنّي يقبل طلباً |
| GET | `/api/notifications` | الإشعارات |

### استرجاع كلمة المرور
1. `POST /api/auth/forgot-password` بجسم `{"phone":"07xxxxxxxxx"}` → رمز من 6 أرقام صالح 10 دقائق.
2. `POST /api/auth/reset-password` بجسم `{"phone":"...","code":"123456","newPassword":"..."}`.
3. بعد التغيير تُبطَل كل الجلسات القديمة لتلك الحساب.

في وضع التجربة (`RESET_DEMO_MODE` غير مضبوط أو `true`) يُعاد الرمز في الحقل `devCode`
لأنه لا توجد بوابة رسائل مربوطة بعد. عند ربط بوابة SMS اضبط `RESET_DEMO_MODE=false`
ولن يُعاد الرمز في الاستجابة. الرمز يُرفض بعد 5 محاولات خاطئة، ويجب طلب رمز جديد.

## ملاحظات الجودة (تم إصلاحها)
- قوس ناقص في `SimplePage` كان يمنع الترجمة (`Expected to find ')'`).
- توحيد المسارات مع الخادم: `/api/providers/requests`.
- قبول العرض أصبح `/api/requests/:id/accept-offer` مع إرسال `providerId`.
- استبدال `value:` المهجورة بـ `initialValue:` في `DropdownButtonFormField`.
- معالجة الشبكة: مهلة 60 ثانية + 3 محاولات + رسائل تشخيص واضحة بدل ابتلاع الخطأ.

## متغيّرات البيئة
| المتغير | الافتراضي | الوصف |
|---|---|---|
| `PORT` | `10000` | منفذ الخادم |
| `DATABASE_URL` | — | رابط PostgreSQL؛ بدونه يعمل الخادم بذاكرة مؤقتة |
| `RESET_DEMO_MODE` | `true` | إعادة رمز التحقق في الاستجابة (للتجربة) |
