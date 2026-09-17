# مشروع دلّيني (Dallini)

تطبيق خدمات منزلية: يطلب المستخدم فنّي (كهرباء، سباكة، تكييف، صيانة أجهزة، تنظيف، سيارات)،
ويستقبل الفنّي الطلبات القريبة ويقبلها.

## المحتويات
- `backend/` — خادم Node.js/Express (توثيق بـ JWT، عروض، حالات الطلب، دعم PostgreSQL اختياري).
- `mobile_source/` — كود تطبيق Flutter (المصدر الأساسي).
- `mobile/` — مشروع Flutter المولَّد للبناء (يُنشأ بـ `flutter create`).
- `.github/workflows/` — بناء APK تلقائي + تصدير ملف المشروع.

> مصدر التطبيق المستخدم فعلياً في بناء الـAPK هو `mobile_source/lib/app_fixed.dart` (يُنسخ إلى `mobile/lib/main.dart`).

## تشغيل الخادم محلياً
```bash
cd backend
npm install
PORT=10000 node server.js
# ثم تحقّق:
curl http://127.0.0.1:10000/api/health
```
بدون `DATABASE_URL` يعمل الخادم بذاكرة مؤقتة (in-memory) — مناسب للتجربة.
للاستمرارية أنشئ قاعدة PostgreSQL واضبط `DATABASE_URL`، وسينشئ الخادم الجداول تلقائياً.

## بناء تطبيق Flutter
```bash
flutter create --platforms=android --org com.dallini mobile
cp mobile_source/pubspec.yaml mobile/pubspec.yaml
cp mobile_source/lib/app_fixed.dart mobile/lib/main.dart
cd mobile
flutter pub get
flutter build apk --release --dart-define=API_URL=https://dallini-app.onrender.com
```
ناتج البناء: `mobile/build/app/outputs/flutter-apk/app-release.apk`

## واجهات الخادم (API)
| الطريقة | المسار | الوصف |
|---|---|---|
| GET | `/api/health` | فحص الحالة |
| GET | `/api/categories` | الفئات |
| POST | `/api/auth/register` | إنشاء حساب (`customer` أو `provider`) |
| POST | `/api/auth/login` | تسجيل الدخول |
| GET | `/api/auth/me` | بيانات الحساب |
| POST | `/api/requests` | إنشاء طلب |
| GET | `/api/requests/mine` | طلبات المستخدم |
| GET | `/api/requests/:id/offers` | عروض الطلب |
| POST | `/api/requests/:id/accept-offer` | قبول عرض |
| POST | `/api/requests/:id/next` | تقديم حالة الطلب |
| POST | `/api/requests/:id/cancel` | إلغاء الطلب |
| GET | `/api/providers/requests` | طلبات متاحة للفنّي |
| POST | `/api/providers/requests/:id/accept` | الفنّي يقبل طلباً |

## ملاحظات الجودة (تم إصلاحها)
- إضافة قوس ناقص في `SimplePage` كان يمنع الترجمة (`Expected to find ')'`).
- توحيد المسارات مع الخادم: `/api/providers/requests` (كان `provider` مفرداً).
- قبول العرض أصبح `/api/requests/:id/accept-offer` (كان `/offers/:offerId/accept`).
- استبدال `value:` المهجورة بـ `initialValue:` في `DropdownButtonFormField`.
