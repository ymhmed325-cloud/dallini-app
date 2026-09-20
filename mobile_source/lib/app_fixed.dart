import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String apiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://dallini-app.onrender.com');
const List<String> services = <String>['كهرباء', 'سباكة', 'تكييف', 'صيانة أجهزة', 'تنظيف', 'سيارات'];
const List<IconData> serviceIcons = <IconData>[Icons.bolt, Icons.water_drop, Icons.ac_unit, Icons.build, Icons.cleaning_services, Icons.directions_car];
const List<Color> serviceColors = <Color>[Colors.amber, Colors.blue, Colors.cyan, Colors.deepPurple, Colors.green, Colors.red];

void main() { runApp(const DalliniApp()); }

class DalliniApp extends StatelessWidget {
  const DalliniApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'دلّيني',
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff087e8b))),
      home: const Directionality(textDirection: TextDirection.rtl, child: RootPage()),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});
  @override State<RootPage> createState() => _RootPageState();
}
class _RootPageState extends State<RootPage> {
  Map<String, dynamic>? user;
  bool loading = true;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('user');
    Map<String, dynamic>? value;
    if (raw != null) {
      try { value = Map<String, dynamic>.from(jsonDecode(raw) as Map); } catch (_) {}
    }
    if (mounted) setState(() { user = value; loading = false; });
  }
  Future<void> loginDone(String token, Map<String, dynamic> account) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('token', token);
    await p.setString('user', jsonEncode(account));
    if (mounted) setState(() { user = account; });
  }
  Future<void> logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
    await p.remove('user');
    if (mounted) setState(() { user = null; });
  }
  @override Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (user == null) return LoginPage(onDone: loginDone);
    return MainShell(user: user!, onLogout: logout);
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onDone});
  final Future<void> Function(String, Map<String, dynamic>) onDone;
  @override State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final phone = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  bool register = false;
  bool busy = false;
  String role = 'customer';
  @override void dispose() { phone.dispose(); password.dispose(); name.dispose(); super.dispose(); }
  void message(String s) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }
  Future<void> submit() async {
    if (phone.text.trim().length < 9 || password.text.length < 6) { message('أدخل رقم هاتف صحيح وكلمة مرور من 6 أحرف على الأقل'); return; }
    if (register && name.text.trim().length < 2) { message('أدخل الاسم الكامل'); return; }
    setState(() { busy = true; });
    final endpoint = register ? 'register' : 'login';
    final uri = Uri.parse('$apiUrl/api/auth/$endpoint');
    final payload = jsonEncode({'name': name.text.trim(), 'phone': phone.text.trim(), 'password': password.text, 'role': role});
    http.Response? response;
    Object? lastError;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        response = await http.post(uri, headers: const {'Content-Type': 'application/json'}, body: payload).timeout(const Duration(seconds: 60));
        break;
      } catch (e) {
        lastError = e;
        if (attempt < 3) {
          if (mounted) message('جارٍ الاتصال بالخادم... إعادة المحاولة $attempt من 3');
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
    }
    if (response == null) {
      final kind = lastError is TimeoutException ? 'انتهت مهلة الاتصال' : (lastError is SocketException ? 'لا يوجد اتصال بالإنترنت' : 'خطأ في الشبكة');
      if (mounted) message('$kind — تعذر الوصول إلى $apiUrl');
    } else {
      try {
        final decoded = jsonDecode(response.body);
        final data = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
        if (response.statusCode >= 200 && response.statusCode < 300 && data['user'] is Map) {
          await widget.onDone('${data['token']}', Map<String, dynamic>.from(data['user'] as Map));
        } else {
          if (mounted) message('${data['error'] ?? 'تعذر إتمام العملية (رمز ${response.statusCode})'}');
        }
      } catch (_) {
        if (mounted) message('استجابة غير متوقعة من الخادم (رمز ${response.statusCode})');
      }
    }
    if (mounted) setState(() { busy = false; });
  }
  @override Widget build(BuildContext context) {
    return Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(22), child: Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(children: <Widget>[
      Container(height: 100, alignment: Alignment.center, decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(colors: <Color>[Color(0xff063c59), Color(0xff1aa0b8)])), child: const Text('دلّيني', style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w900))),
      const SizedBox(height: 18), Text(register ? 'إنشاء حساب' : 'تسجيل الدخول', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)), const SizedBox(height: 18),
      if (register) TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم الكامل', border: OutlineInputBorder())),
      if (register) const SizedBox(height: 12),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف', border: OutlineInputBorder())), const SizedBox(height: 12),
      TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور', border: OutlineInputBorder())),
      if (register) const SizedBox(height: 12),
      if (register) DropdownButtonFormField<String>(initialValue: role, decoration: const InputDecoration(labelText: 'نوع الحساب', border: OutlineInputBorder()), items: const <DropdownMenuItem<String>>[DropdownMenuItem<String>(value: 'customer', child: Text('مستخدم / طالب خدمة')), DropdownMenuItem<String>(value: 'provider', child: Text('فني / مقدم خدمة'))], onChanged: (v) { if (v != null) setState(() { role = v; }); }),
      const SizedBox(height: 18), SizedBox(width: double.infinity, height: 52, child: FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'جاري...' : (register ? 'إنشاء الحساب' : 'دخول')))),
        TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ForgotPasswordPage())), child: const Text('نسيت كلمة المرور؟')),
      TextButton(onPressed: busy ? null : () { setState(() { register = !register; }); }, child: Text(register ? 'لدي حساب بالفعل' : 'إنشاء حساب جديد')),
      const Text('الحساب متصل بالخادم الحقيقي.', style: TextStyle(color: Colors.grey)),
    ])))))));
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.user, required this.onLogout});
  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;
  @override State<MainShell> createState() => _MainShellState();
}
class _MainShellState extends State<MainShell> {
  int index = 0;
  Future<void> openNew([String? service]) async { await Navigator.push(context, MaterialPageRoute(builder: (_) => NewRequestPage(service: service))); if (mounted) setState(() {}); }
  @override Widget build(BuildContext context) {
    final isProvider = widget.user['role'] == 'provider';
    if (isProvider) {
      final pages = <Widget>[const ProviderJobsPage(), ProfilePage(user: widget.user, onLogout: widget.onLogout)];
      return Scaffold(body: IndexedStack(index: index, children: pages), bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (i) { setState(() { index = i; }); }, destinations: const <NavigationDestination>[NavigationDestination(icon: Icon(Icons.work_outline), label: 'الطلبات'), NavigationDestination(icon: Icon(Icons.person_outline), label: 'حسابي')]));
    }
    final pages = <Widget>[HomePage(onNew: openNew), const OrdersPage(), const SizedBox.shrink(), const MessagesPage(), ProfilePage(user: widget.user, onLogout: widget.onLogout)];
    return Scaffold(body: IndexedStack(index: index, children: pages), bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (i) { if (i == 2) { openNew(); } else { setState(() { index = i; }); } }, destinations: const <NavigationDestination>[NavigationDestination(icon: Icon(Icons.home_outlined), label: 'الرئيسية'), NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'طلباتي'), NavigationDestination(icon: Icon(Icons.add_circle_outline), label: 'طلب جديد'), NavigationDestination(icon: Icon(Icons.chat_outlined), label: 'المحادثات'), NavigationDestination(icon: Icon(Icons.person_outline), label: 'حسابي')]));
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onNew});
  final Future<void> Function([String?]) onNew;
  @override Widget build(BuildContext context) {
    return SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: <Widget>[
      Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), gradient: const LinearGradient(colors: <Color>[Color(0xff063c59), Color(0xff1aa0b8)])), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text('دلّيني', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)), SizedBox(height: 6), Text('عندك مشكلة؟ خلّينا نحلّها.', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)), SizedBox(height: 5), Text('اختار الخدمة ونوصل لك فني مناسب.', style: TextStyle(color: Colors.white70))])),
      const SizedBox(height: 22), const Text('شنو تحتاج اليوم؟', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)), const SizedBox(height: 12),
      GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: services.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.2), itemBuilder: (context, i) { final color = serviceColors[i]; return Card(child: InkWell(onTap: () { onNew(services[i]); }, child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: <Color>[color.withAlpha(55), Colors.white])), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[CircleAvatar(radius: 29, backgroundColor: color.withAlpha(45), foregroundColor: color, child: Icon(serviceIcons[i], size: 31)), const SizedBox(height: 8), Text(services[i], style: const TextStyle(fontWeight: FontWeight.w900))])))); }),
      const SizedBox(height: 18), Card(child: ListTile(onTap: () { onNew(); }, leading: const CircleAvatar(child: Icon(Icons.add)), title: const Text('إنشاء طلب جديد', style: TextStyle(fontWeight: FontWeight.w900)), subtitle: const Text('اكتب المشكلة وأرسلها للفنيين'), trailing: const Icon(Icons.chevron_left)))
    ]));
  }
}

class NewRequestPage extends StatefulWidget {
  const NewRequestPage({super.key, this.service});
  final String? service;
  @override State<NewRequestPage> createState() => _NewRequestPageState();
}
class _NewRequestPageState extends State<NewRequestPage> {
  final desc = TextEditingController();
  final address = TextEditingController();
  String? service;
  bool sending = false;
  @override void initState() { super.initState(); service = widget.service; }
  @override void dispose() { desc.dispose(); address.dispose(); super.dispose(); }
  void message(String s) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }
  Future<void> send() async {
    if (service == null) { message('اختر نوع الخدمة'); return; }
    if (desc.text.trim().length < 3) { message('اكتب وصف المشكلة'); return; }
    final p = await SharedPreferences.getInstance();
    final token = p.getString('token') ?? '';
    if (token.isEmpty) { message('سجّل الدخول مرة أخرى'); return; }
    setState(() { sending = true; });
    try {
      final r = await http.post(Uri.parse('$apiUrl/api/requests'), headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'}, body: jsonEncode({'category': service, 'description': desc.text.trim(), 'address': address.text.trim()})).timeout(const Duration(seconds: 60));
      final raw = jsonDecode(r.body);
      final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      if (r.statusCode >= 200 && r.statusCode < 300) { if (mounted) { message('تم إرسال الطلب بنجاح'); Navigator.pop(context); } } else { message('${data['error'] ?? 'تعذر إرسال الطلب'}'); }
    } catch (_) { message('تعذر الاتصال بالخادم'); }
    if (mounted) setState(() { sending = false; });
  }
  @override Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('طلب جديد')), body: ListView(padding: const EdgeInsets.all(18), children: <Widget>[
      DropdownButtonFormField<String>(initialValue: service, decoration: const InputDecoration(labelText: 'نوع الخدمة', border: OutlineInputBorder()), items: services.map((s) => DropdownMenuItem<String>(value: s, child: Text(s))).toList(), onChanged: (v) { setState(() { service = v; }); }),
      const SizedBox(height: 14), TextField(controller: desc, minLines: 4, maxLines: 7, decoration: const InputDecoration(labelText: 'وصف المشكلة', hintText: 'مثال: المكيف لا يبرد', border: OutlineInputBorder())),
      const SizedBox(height: 14), TextField(controller: address, maxLines: 2, decoration: const InputDecoration(labelText: 'العنوان', border: OutlineInputBorder())),
      const SizedBox(height: 20), SizedBox(height: 52, child: FilledButton.icon(onPressed: sending ? null : send, icon: const Icon(Icons.send), label: Text(sending ? 'جاري الإرسال...' : 'إرسال الطلب')))
    ]));
  }
}

class OrdersPage extends StatefulWidget { const OrdersPage({super.key}); @override State<OrdersPage> createState() => _OrdersPageState(); }
class _OrdersPageState extends State<OrdersPage> {
  List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
  bool loading = true;
  String? error;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    if (mounted) setState(() { loading = true; error = null; });
    final p = await SharedPreferences.getInstance(); final token = p.getString('token') ?? '';
    try {
      final r = await http.get(Uri.parse('$apiUrl/api/requests/mine'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 60));
      if (r.statusCode == 200) { final raw = jsonDecode(r.body); items = raw is List ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[]; } else { error = 'تعذر تحميل الطلبات'; }
    } catch (_) { error = 'تعذر الاتصال بالخادم'; }
    if (mounted) setState(() { loading = false; });
  }
  String statusText(dynamic status) { const map = <String, String>{'matching': 'جاري البحث عن فني', 'offer': 'وصل عرض فني', 'accepted': 'تم قبول الفني', 'on_way': 'الفني بالطريق', 'arrived': 'وصل الفني', 'in_progress': 'قيد التنفيذ', 'completed': 'مكتمل', 'cancelled': 'ملغي'}; return map['${status ?? ''}'] ?? '${status ?? ''}'; }
  @override Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[Text(error!), const SizedBox(height: 12), FilledButton(onPressed: load, child: const Text('إعادة المحاولة'))]));
    if (items.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[const Icon(Icons.receipt_long, size: 70, color: Colors.grey), const SizedBox(height: 12), const Text('ما عندك طلبات بعد', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)), const SizedBox(height: 12), FilledButton.icon(onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const NewRequestPage())).then((_) { load(); }); }, icon: const Icon(Icons.add), label: const Text('إنشاء طلب'))]));
    return RefreshIndicator(onRefresh: load, child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: items.length, itemBuilder: (context, i) { final x = items[i]; final k = services.indexOf('${x['category']}'); final n = k < 0 ? 0 : k; return Card(child: ListTile(leading: CircleAvatar(backgroundColor: serviceColors[n].withAlpha(45), foregroundColor: serviceColors[n], child: Icon(serviceIcons[n])), title: Text('${x['category']}', style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text('${x['description']}\n${statusText(x['status'])}'), isThreeLine: true, trailing: IconButton(icon: const Icon(Icons.timeline), tooltip: 'تتبّع الطلب', onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => RequestTimelinePage(requestId: '${x['id']}', category: '${x['category']}', description: '${x['description']}'))); }), onTap: () { Navigator.push(context, MaterialPageRoute(builder: (_) => RequestDetailPage(request: x))).then((_) { load(); }); })); }));
  }
}

class RequestDetailPage extends StatefulWidget { const RequestDetailPage({super.key, required this.request}); final Map<String, dynamic> request; @override State<RequestDetailPage> createState() => _RequestDetailPageState(); }
class _RequestDetailPageState extends State<RequestDetailPage> {
  late Map<String, dynamic> request;
  bool busy = false;
  @override void initState() { super.initState(); request = Map<String, dynamic>.from(widget.request); }
  Future<void> nextStatus() async {
    final id = request['id']; if (id == null) return;
    final p = await SharedPreferences.getInstance(); final token = p.getString('token') ?? '';
    setState(() { busy = true; });
    try {
      final r = await http.post(Uri.parse('$apiUrl/api/requests/$id/next'), headers: {'Authorization': 'Bearer $token'});
      if (r.statusCode >= 200 && r.statusCode < 300) { final raw = jsonDecode(r.body); if (raw is Map && raw['request'] is Map) setState(() { request = Map<String, dynamic>.from(raw['request'] as Map); }); }
    } catch (_) {}
    if (mounted) setState(() { busy = false; });
  }
  Future<void> acceptOffer(dynamic offerId) async {
    final p = await SharedPreferences.getInstance(); final token = p.getString('token') ?? '';
    setState(() { busy = true; });
    try {
      final r = await http.post(Uri.parse('$apiUrl/api/requests/${request['id']}/accept-offer'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({'providerId': offerId}));
      if (r.statusCode >= 200 && r.statusCode < 300) { final raw = jsonDecode(r.body); if (raw is Map && raw['request'] is Map) setState(() { request = Map<String, dynamic>.from(raw['request'] as Map); }); }
    } catch (_) {}
    if (mounted) setState(() { busy = false; });
  }
  @override Widget build(BuildContext context) {
    final rawOffers = request['offers'];
    final offers = rawOffers is List ? rawOffers : <dynamic>[];
    return Scaffold(appBar: AppBar(title: const Text('تفاصيل الطلب')), body: ListView(padding: const EdgeInsets.all(18), children: <Widget>[
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text('${request['category']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)), const SizedBox(height: 10), Text('${request['description']}'), const SizedBox(height: 10), Text('الحالة: ${request['status']}'), const SizedBox(height: 8), Text('العنوان: ${request['address'] ?? '-'}')]))) ,
      if (offers.isNotEmpty) const Padding(padding: EdgeInsets.only(top: 14, bottom: 8), child: Text('العروض', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
      ...offers.map((raw) { final o = Map<String, dynamic>.from(raw as Map); return Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.engineering)), title: Text('${o['providerName'] ?? 'فني'}'), subtitle: Text('السعر: ${o['price'] ?? '-'}\nالوصول: ${o['etaMinutes'] ?? '-'} دقيقة'), isThreeLine: true, trailing: FilledButton(onPressed: busy ? null : () { acceptOffer(o['id']); }, child: const Text('قبول')))); }),
      const SizedBox(height: 14), SizedBox(height: 50, child: OutlinedButton.icon(onPressed: busy ? null : nextStatus, icon: const Icon(Icons.refresh), label: const Text('تحديث حالة الطلب')))
    ]));
  }
}

class MessagesPage extends StatelessWidget { const MessagesPage({super.key}); @override Widget build(BuildContext context) { return const SafeArea(child: Center(child: Text('المحادثات ستظهر بعد قبول أحد العروض.'))); } }

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.user, required this.onLogout});
  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;
  @override Widget build(BuildContext context) {
    final entries=<Map<String,dynamic>>[
      {'t':'تعديل الملف الشخصي','i':Icons.edit_outlined},
      {'t':'العناوين','i':Icons.location_on_outlined},
      {'t':'الفنيون المفضلون','i':Icons.favorite_outline},
      {'t':'الإشعارات','i':Icons.notifications_none},
      {'t':'الإعدادات','i':Icons.settings_outlined},
      {'t':'الأمان والخصوصية','i':Icons.security_outlined},
      {'t':'المساعدة والدعم','i':Icons.help_outline},
    ];
    return SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:<Widget>[
      Card(child:ListTile(leading:const CircleAvatar(radius:28,child:Icon(Icons.person)),title:Text(_text(user['name'],'مستخدم'),style:const TextStyle(fontWeight:FontWeight.w900)),subtitle:Text(_text(user['phone'])))),
      const SizedBox(height:10),
      ...entries.map((e) => Card(
        child: ListTile(
          leading: Icon(e['i'] as IconData),
          title: Text(e['t'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
          trailing: const Icon(Icons.chevron_left),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AccountFeaturePage(
                  kind: e['t'] as String,
                  user: user,
                ),
              ),
            );
          },
        ),
      )),
      const SizedBox(height:16),
      FilledButton.tonalIcon(onPressed:onLogout,icon:const Icon(Icons.logout),label:const Text('تسجيل الخروج')),
    ]));
  }
}

class AccountFeaturePage extends StatefulWidget {
  const AccountFeaturePage({super.key,required this.kind,required this.user});
  final String kind; final Map<String,dynamic> user;
  @override State<AccountFeaturePage> createState()=>_AccountFeaturePageState();
}
class _AccountFeaturePageState extends State<AccountFeaturePage>{
  List<Map<String,dynamic>> items=<Map<String,dynamic>>[];
  bool loading=true;
  final name=TextEditingController(); final current=TextEditingController(); final next=TextEditingController();
  @override void initState(){super.initState();name.text=_text(widget.user['name']);load();}
  @override void dispose(){name.dispose();current.dispose();next.dispose();super.dispose();}
  Future<String> token()async{final p=await SharedPreferences.getInstance();return p.getString('token')??'';}
  Future<void> load()async{
    if(widget.kind=='العناوين')await loadList('/api/addresses');
    else if(widget.kind=='الفنيون المفضلون')await loadList('/api/favorites');
    else if(widget.kind=='الإشعارات')await loadList('/api/notifications');
    else if(mounted)setState(()=>loading=false);
  }
  Future<void> loadList(String path)async{
    try{final r=await http.get(Uri.parse(apiUrl+path),headers:{'Authorization':'Bearer '+await token()});if(r.statusCode==200){final raw=jsonDecode(r.body);if(raw is List)items=raw.map((e)=>Map<String,dynamic>.from(e as Map)).toList();}}
    catch(_){}
    if(mounted)setState(()=>loading=false);
  }
  Future<void> saveProfile()async{
    try{final r=await http.put(Uri.parse(apiUrl+'/api/profile'),headers:{'Authorization':'Bearer '+await token(),'Content-Type':'application/json'},body:jsonEncode({'name':name.text.trim()}));if(r.statusCode>=200&&r.statusCode<300){final raw=jsonDecode(r.body);if(raw is Map&&raw['user'] is Map){final p=await SharedPreferences.getInstance();await p.setString('user',jsonEncode(raw['user']));}if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم تحديث الملف الشخصي')));}}
    catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تعذر الاتصال بالخادم')));}
  }
  Future<void> addAddress()async{
    final label=TextEditingController(text:'المنزل');final address=TextEditingController();
    await showDialog<void>(context:context,builder:(c)=>AlertDialog(title:const Text('إضافة عنوان'),content:Column(mainAxisSize:MainAxisSize.min,children:<Widget>[
      TextField(controller:label,decoration:const InputDecoration(labelText:'اسم العنوان')),TextField(controller:address,maxLines:3,decoration:const InputDecoration(labelText:'العنوان')),
    ]),actions:<Widget>[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('إلغاء')),FilledButton(onPressed:()async{await http.post(Uri.parse(apiUrl+'/api/addresses'),headers:{'Authorization':'Bearer '+await token(),'Content-Type':'application/json'},body:jsonEncode({'label':label.text,'address':address.text,'isDefault':items.isEmpty}));if(c.mounted)Navigator.pop(c);await load();},child:const Text('حفظ'))]));
    label.dispose();address.dispose();
  }
  Future<void> deleteItem(String id)async{
    final path=widget.kind=='العناوين'?'/api/addresses/'+id:'/api/favorites/'+id;
    await http.delete(Uri.parse(apiUrl+path),headers:{'Authorization':'Bearer '+await token()});await load();
  }
  Future<void> markRead(String id)async{await http.patch(Uri.parse(apiUrl+'/api/notifications/'+id+'/read'),headers:{'Authorization':'Bearer '+await token()});await load();}
  Future<void> changePassword()async{
    try{final r=await http.post(Uri.parse(apiUrl+'/api/auth/change-password'),headers:{'Authorization':'Bearer '+await token(),'Content-Type':'application/json'},body:jsonEncode({'currentPassword':current.text,'newPassword':next.text}));if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(r.statusCode>=200&&r.statusCode<300?'تم تغيير كلمة المرور':'تعذر تغيير كلمة المرور')));}
    catch(_){}
  }
  Future<void> support()async{
    final subject=TextEditingController();final message=TextEditingController();
    await showDialog<void>(context:context,builder:(c)=>AlertDialog(title:const Text('تذكرة دعم'),content:Column(mainAxisSize:MainAxisSize.min,children:<Widget>[TextField(controller:subject,decoration:const InputDecoration(labelText:'الموضوع')),TextField(controller:message,maxLines:5,decoration:const InputDecoration(labelText:'التفاصيل'))]),actions:<Widget>[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('إلغاء')),FilledButton(onPressed:()async{await http.post(Uri.parse(apiUrl+'/api/support/tickets'),headers:{'Authorization':'Bearer '+await token(),'Content-Type':'application/json'},body:jsonEncode({'subject':subject.text,'message':message.text}));if(c.mounted)Navigator.pop(c);},child:const Text('إرسال'))]));
    subject.dispose();message.dispose();
  }
  @override Widget build(BuildContext context){
    if(widget.kind=='تعديل الملف الشخصي')return Scaffold(appBar:AppBar(title:Text(widget.kind)),body:ListView(padding:const EdgeInsets.all(18),children:<Widget>[
      TextField(controller:name,decoration:const InputDecoration(labelText:'الاسم الكامل',border:OutlineInputBorder())),const SizedBox(height:12),
      Text('رقم الهاتف: '+_text(widget.user['phone']),style:const TextStyle(color:Colors.grey)),const SizedBox(height:20),
      FilledButton(onPressed:saveProfile,child:const Text('حفظ التغييرات')),
    ]));
    if(widget.kind=='الأمان والخصوصية')return Scaffold(appBar:AppBar(title:Text(widget.kind)),body:ListView(padding:const EdgeInsets.all(18),children:<Widget>[
      TextField(controller:current,obscureText:true,decoration:const InputDecoration(labelText:'كلمة المرور الحالية',border:OutlineInputBorder())),const SizedBox(height:12),
      TextField(controller:next,obscureText:true,decoration:const InputDecoration(labelText:'كلمة المرور الجديدة',border:OutlineInputBorder())),const SizedBox(height:18),
      FilledButton(onPressed:changePassword,child:const Text('تغيير كلمة المرور')),const SizedBox(height:18),
      const Text('يحمي الخادم الطلبات والمحادثات بصلاحيات مرتبطة بالحساب.',style:TextStyle(color:Colors.grey)),
    ]));
    if(widget.kind=='الإعدادات')return Scaffold(appBar:AppBar(title:Text(widget.kind)),body:SwitchListTile(value:true,onChanged:(_){},title:const Text('إشعارات التطبيق'),subtitle:const Text('تنبيهات الطلبات والرسائل')));
    if(widget.kind=='المساعدة والدعم')return Scaffold(appBar:AppBar(title:Text(widget.kind)),body:ListView(padding:const EdgeInsets.all(18),children:<Widget>[
      const ExpansionTile(title:Text('كيف أنشئ طلباً؟'),children:<Widget>[Padding(padding:EdgeInsets.all(16),child:Text('اختر الخدمة واكتب المشكلة والعنوان ثم أرسل الطلب.'))]),
      const ExpansionTile(title:Text('كيف أقبل عرضاً؟'),children:<Widget>[Padding(padding:EdgeInsets.all(16),child:Text('افتح تفاصيل الطلب ثم اختر عرض الفني واضغط قبول.'))]),
      const SizedBox(height:18),FilledButton.icon(onPressed:support,icon:const Icon(Icons.support_agent),label:const Text('إرسال تذكرة دعم')),
    ]));
    if(loading)return Scaffold(appBar:AppBar(title:Text(widget.kind)),body:const Center(child:CircularProgressIndicator()));
    return Scaffold(appBar:AppBar(title:Text(widget.kind),actions:<Widget>[if(widget.kind=='العناوين')IconButton(onPressed:addAddress,icon:const Icon(Icons.add)),IconButton(onPressed:load,icon:const Icon(Icons.refresh))]),body:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:items.isEmpty?<Widget>[const Padding(padding:EdgeInsets.all(40),child:Center(child:Text('لا توجد بيانات بعد.')))]:
      items.map((x){final id=_text(x['id']);final title=widget.kind=='العناوين'?_text(x['label'],'العنوان'):widget.kind=='الفنيون المفضلون'?_text(x['name'],'فني'):_text(x['title'],'دلّيني');final sub=widget.kind=='العناوين'?_text(x['address']):widget.kind=='الفنيون المفضلون'?_text(x['phone']):_text(x['message']);return Card(child:ListTile(leading:Icon(widget.kind=='الفنيون المفضلون'?Icons.engineering:widget.kind=='الإشعارات'?Icons.notifications:Icons.location_on),title:Text(title),subtitle:Text(sub),trailing:widget.kind=='الإشعارات'?null:IconButton(onPressed:()=>deleteItem(id),icon:Icon(widget.kind=='العناوين'?Icons.delete_outline:Icons.favorite,color:Colors.red)),onTap:widget.kind=='الإشعارات'?()=>markRead(id):null));}).toList())));
  }
}

String statusLabel(String? s) {
  const m = <String, String>{
    'matching': 'جاري البحث عن فني',
    'offer': 'وصل عرض فني',
    'accepted': 'تم قبول الطلب',
    'on_way': 'الفني في الطريق',
    'arrived': 'وصل الفني للموقع',
    'in_progress': 'قيد التنفيذ',
    'completed': 'مكتمل',
    'cancelled': 'ملغي',
  };
  return m[s] ?? (s ?? '');
}

const Map<String, String> statusActionLabel = <String, String>{
  'on_way': 'أنا في الطريق',
  'arrived': 'وصلت الموقع',
  'in_progress': 'بدء التنفيذ',
  'completed': 'إتمام الطلب',
};

const List<String> statusFlow = <String>['accepted', 'on_way', 'arrived', 'in_progress', 'completed'];

String? nextStatusOf(String current) {
  final i = statusFlow.indexOf(current);
  if (i < 0 || i >= statusFlow.length - 1) return null;
  return statusFlow[i + 1];
}

String _text(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final t = v.toString();
  return t.isEmpty ? fallback : t;
}

class TimelineList extends StatelessWidget {
  const TimelineList({super.key, required this.events});
  final List<Map<String, dynamic>> events;
  @override Widget build(BuildContext context) {
    if (events.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد أحداث بعد.'));
    return Column(children: events.reversed.map((e) {
      final label = statusLabel(_text(e['status']));
      final when = _text(e['created_at']);
      final note = e['note'] == null ? '' : '\n' + _text(e['note']);
      return Card(child: ListTile(
        leading: CircleAvatar(backgroundColor: const Color(0xFF123B68).withAlpha(30), foregroundColor: const Color(0xFF123B68), child: const Icon(Icons.check_circle_outline)),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(when + note),
        isThreeLine: e['note'] != null,
      ));
    }).toList());
  }
}

class RequestTimelinePage extends StatefulWidget {
  const RequestTimelinePage({super.key, required this.requestId, this.category, this.description});
  final String requestId;
  final String? category;
  final String? description;
  @override State<RequestTimelinePage> createState() => _RequestTimelinePageState();
}

class _RequestTimelinePageState extends State<RequestTimelinePage> {
  Map<String, dynamic>? data;
  bool loading = true;
  String? error;

  @override void initState() { super.initState(); load(); }

  Future<void> load() async {
    if (mounted) setState(() { loading = true; error = null; });
    final p = await SharedPreferences.getInstance();
    final token = p.getString('token') ?? '';
    try {
      final r = await http.get(Uri.parse('$apiUrl/api/requests/${widget.requestId}/timeline'),
        headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 60));
      if (r.statusCode == 200) {
        final raw = jsonDecode(r.body);
        if (raw is Map) data = Map<String, dynamic>.from(raw);
      } else if (r.statusCode == 403) {
        error = 'لا تملك صلاحية عرض هذا الطلب';
      } else {
        error = 'تعذر تحميل حالة الطلب';
      }
    } catch (_) { error = 'تعذر الاتصال بالخادم'; }
    if (mounted) setState(() { loading = false; });
  }

  @override Widget build(BuildContext context) {
    final reqRaw = data?['request'];
    final req = reqRaw is Map ? Map<String, dynamic>.from(reqRaw) : <String, dynamic>{};
    final events = (data?['events'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? <Map<String, dynamic>>[];
    final current = _text(data?['status']);
    final stepIndex = statusFlow.indexOf(current);
    final title = _text(widget.category ?? req['category']);
    final desc = _text(widget.description ?? req['description']);
    final label = _text(data?['statusLabel'], statusLabel(current));
    return Scaffold(
      appBar: AppBar(title: const Text('تتبّع الطلب')),
      body: RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
        if (loading) const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator())),
        if (error != null) Column(children: <Widget>[
          Text(error!, style: const TextStyle(fontSize: 17)),
          const SizedBox(height: 12),
          FilledButton(onPressed: load, child: const Text('إعادة المحاولة')),
        ]),
        if (!loading && error == null) ...<Widget>[
          Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(desc, style: const TextStyle(color: Color(0xFF55606E))),
            const SizedBox(height: 12),
            Row(children: <Widget>[const Icon(Icons.local_shipping_outlined), const SizedBox(width: 8), Expanded(child: Text('الحالة: $label', style: const TextStyle(fontWeight: FontWeight.w900)))]),
          ]))),
          const SizedBox(height: 14),
          const Text('مراحل الطلب', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          ...List<Widget>.generate(statusFlow.length, (i) {
            final reached = stepIndex >= i;
            final isCurrent = stepIndex == i;
            return Card(child: ListTile(
              leading: CircleAvatar(
                backgroundColor: reached ? const Color(0xFF123B68) : const Color(0xFFD9DEE6),
                foregroundColor: Colors.white,
                child: Icon(reached ? Icons.check_circle : Icons.radio_button_unchecked),
              ),
              title: Text(statusLabel(statusFlow[i]), style: TextStyle(fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600)),
              subtitle: Text(isCurrent ? 'المرحلة الحالية' : (reached ? 'تمّت' : 'لم تبدأ')),
            ));
          }),
          const SizedBox(height: 14),
          const Text('سجل الأحداث', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          TimelineList(events: events),
        ],
      ])),
    );
  }
}

class ProviderJobDetailPage extends StatefulWidget {
  const ProviderJobDetailPage({super.key, required this.job});
  final Map<String, dynamic> job;
  @override State<ProviderJobDetailPage> createState() => _ProviderJobDetailPageState();
}

class _ProviderJobDetailPageState extends State<ProviderJobDetailPage> {
  late Map<String, dynamic> job;
  List<Map<String, dynamic>> events = <Map<String, dynamic>>[];
  bool busy = false;
  bool loading = true;

  @override void initState() { super.initState(); job = Map<String, dynamic>.from(widget.job); load(); }

  void message(String s) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }

  Future<String> _token() async { final p = await SharedPreferences.getInstance(); return p.getString('token') ?? ''; }

  Future<void> load() async {
    final token = await _token();
    try {
      final r = await http.get(Uri.parse('$apiUrl/api/requests/${job['id']}/timeline'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 60));
      if (r.statusCode == 200) {
        final raw = jsonDecode(r.body);
        if (raw is Map) {
          final jr = raw['request'];
          if (jr is Map) job = Map<String, dynamic>.from(jr);
          events = (raw['events'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? <Map<String, dynamic>>[];
        }
      }
    } catch (_) {}
    if (mounted) setState(() { loading = false; });
  }

  Future<void> changeStatus(String status) async {
    setState(() { busy = true; });
    final token = await _token();
    try {
      final r = await http.post(Uri.parse('$apiUrl/api/providers/requests/${job['id']}/status'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'status': status})).timeout(const Duration(seconds: 60));
      final raw = jsonDecode(r.body);
      final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final jr = data['request'];
        if (jr is Map) job = Map<String, dynamic>.from(jr);
        message('تم التحديث: ' + statusLabel(status));
        await load();
      } else {
        message(_text(data['error'], 'تعذر تحديث الحالة'));
      }
    } catch (_) { message('تعذر الاتصال بالخادم'); }
    if (mounted) setState(() { busy = false; });
  }

  @override Widget build(BuildContext context) {
    final currentStatus = _text(job['status']);
    final next = nextStatusOf(currentStatus);
    final k = services.indexOf(_text(job['category']));
    final n = k < 0 ? 0 : k;
    final cat = _text(job['category'], '-');
    final desc = _text(job['description']);
    final addr = _text(job['address'], 'لم يُحدد العنوان');
    final label = statusLabel(currentStatus);
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الطلب')),
      body: RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            CircleAvatar(backgroundColor: serviceColors[n].withAlpha(45), foregroundColor: serviceColors[n], child: Icon(serviceIcons[n])),
            const SizedBox(width: 12),
            Expanded(child: Text(cat, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
          ]),
          const SizedBox(height: 14),
          Text(desc, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Row(children: <Widget>[const Icon(Icons.location_on_outlined, size: 20), const SizedBox(width: 6), Expanded(child: Text(addr))]),
          const SizedBox(height: 8),
          Row(children: <Widget>[const Icon(Icons.flag_outlined, size: 20), const SizedBox(width: 6), Expanded(child: Text('الحالة: $label', style: const TextStyle(fontWeight: FontWeight.w900)))]),
        ]))),
        const SizedBox(height: 14),
        if (next != null)
          FilledButton.icon(onPressed: busy ? null : () { changeStatus(next); }, icon: const Icon(Icons.arrow_forward), label: Text(statusActionLabel[next] ?? statusLabel(next)))
        else
          const Card(child: ListTile(leading: Icon(Icons.check_circle, color: Colors.green), title: Text('هذا الطلب مكتمل أو ملغي'))),
        if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: Center(child: CircularProgressIndicator())),
        const SizedBox(height: 18),
        const Text('سجل الأحداث', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        if (loading) const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())) else TimelineList(events: events),
      ])),
    );
  }
}

class ProviderJobsPage extends StatefulWidget {
  const ProviderJobsPage({super.key});
  @override State<ProviderJobsPage> createState() => _ProviderJobsPageState();
}

class _ProviderJobsPageState extends State<ProviderJobsPage> {
  List<Map<String, dynamic>> available = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> assigned = <Map<String, dynamic>>[];
  bool loading = true;
  String? error;

  @override void initState() { super.initState(); load(); }

  Future<String> _token() async { final p = await SharedPreferences.getInstance(); return p.getString('token') ?? ''; }

  Future<void> load() async {
    if (mounted) setState(() { loading = true; error = null; });
    final token = await _token();
    try {
      final a = await http.get(Uri.parse('$apiUrl/api/providers/requests'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 60));
      final b = await http.get(Uri.parse('$apiUrl/api/providers/jobs?filter=active'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 60));
      if (a.statusCode == 200) { final raw = jsonDecode(a.body); available = raw is List ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[]; }
      if (b.statusCode == 200) { final raw = jsonDecode(b.body); assigned = raw is List ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[]; }
      if (a.statusCode != 200 && b.statusCode != 200) error = 'تعذر تحميل الطلبات';
    } catch (_) { error = 'تعذر الاتصال بالخادم'; }
    if (mounted) setState(() { loading = false; });
  }

  Future<void> accept(dynamic id) async {
    final token = await _token();
    try {
      final r = await http.post(Uri.parse('$apiUrl/api/providers/requests/$id/accept'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 60));
      if (r.statusCode >= 200 && r.statusCode < 300) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم قبول الطلب، ستجده في تبويب طلباتي')));
      } else {
        final raw = jsonDecode(r.body);
        final msg = raw is Map ? _text(raw['error'], 'تعذر قبول الطلب') : 'تعذر قبول الطلب';
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر الاتصال بالخادم'))); }
    await load();
  }

  Widget _jobCard(Map<String, dynamic> job, {required bool assignedJob}) {
    final k = services.indexOf(_text(job['category']));
    final n = k < 0 ? 0 : k;
    final cat = _text(job['category'], '-');
    final desc = _text(job['description']);
    final addr = _text(job['address'], '-');
    final label = statusLabel(_text(job['status']));
    final body = desc + '\n' + addr + '\nالحالة: ' + label;
    return Card(child: ListTile(
      leading: CircleAvatar(backgroundColor: serviceColors[n].withAlpha(45), foregroundColor: serviceColors[n], child: Icon(serviceIcons[n])),
      title: Text(cat, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(body, maxLines: 4),
      isThreeLine: true,
      trailing: assignedJob
        ? const Icon(Icons.chevron_left)
        : FilledButton(onPressed: () { accept(job['id']); }, child: const Text('قبول')),
      onTap: assignedJob ? () { Navigator.push(context, MaterialPageRoute(builder: (_) => ProviderJobDetailPage(job: job))).then((_) { load(); }); } : null,
    ));
  }

  @override Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[Text(error!), const SizedBox(height: 12), FilledButton(onPressed: load, child: const Text('إعادة المحاولة'))]));
    return DefaultTabController(
      length: 2,
      child: Column(children: <Widget>[
        const TabBar(tabs: <Widget>[Tab(text: 'طلباتي'), Tab(text: 'طلبات متاحة')]),
        Expanded(child: TabBarView(children: <Widget>[
          RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
            if (assigned.isEmpty) const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: Text('لا توجد طلبات مسندة إليك حالياً.'))) else ...assigned.map((j) => _jobCard(j, assignedJob: true)),
          ])),
          RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
            if (available.isEmpty) const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: Text('لا توجد طلبات متاحة حالياً.'))) else ...available.map((j) => _jobCard(j, assignedJob: false)),
          ])),
        ])),
      ]),
    );
  }
}

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});
  @override State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final phone = TextEditingController();
  final code = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool sent = false;

  @override void dispose() { phone.dispose(); code.dispose(); password.dispose(); super.dispose(); }

  void message(String s) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }

  Future<Map<String, dynamic>?> call(String path, Map<String, dynamic> body) async {
    try {
      final r = await http.post(Uri.parse('$apiUrl/api/auth/$path'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body)).timeout(const Duration(seconds: 60));
      final decoded = jsonDecode(r.body);
      final data = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
      if (r.statusCode >= 200 && r.statusCode < 300) return data;
      message('${data['error'] ?? 'تعذر إتمام العملية (رمز ${r.statusCode})'}');
    } catch (e) {
      message(e is TimeoutException ? 'انتهت مهلة الاتصال' : (e is SocketException ? 'لا يوجد اتصال بالإنترنت' : 'تعذر الاتصال بالخادم'));
    }
    return null;
  }

  Future<void> sendCode() async {
    if (phone.text.trim().length < 9) { message('أدخل رقم هاتف صحيح'); return; }
    setState(() { busy = true; });
    final data = await call('forgot-password', {'phone': phone.text.trim()});
    if (!mounted) return;
    setState(() { busy = false; if (data != null) sent = true; });
    if (data != null) {
      final dev = data['devCode'];
      message(dev != null ? 'رمز التحقق (وضع التجربة): $dev' : '${data['message'] ?? 'تم إرسال رمز التحقق'}');
    }
  }

  Future<void> resetPassword() async {
    if (code.text.trim().length != 6) { message('أدخل رمز التحقق المكوّن من 6 أرقام'); return; }
    if (password.text.length < 6) { message('كلمة المرور يجب أن تكون 6 أحرف على الأقل'); return; }
    setState(() { busy = true; });
    final data = await call('reset-password', {'phone': phone.text.trim(), 'code': code.text.trim(), 'newPassword': password.text});
    if (!mounted) return;
    setState(() { busy = false; });
    if (data != null) {
      await showDialog<void>(context: context, builder: (c) => AlertDialog(
        title: const Text('تم بنجاح'),
        content: Text('${data['message'] ?? 'تم تغيير كلمة المرور'}'),
        actions: <Widget>[TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('حسناً'))],
      ));
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استرجاع كلمة المرور')),
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        const Text('أدخل رقم هاتفك المسجّل، ثم رمز التحقق، ثم كلمة المرور الجديدة.', style: TextStyle(fontSize: 15, color: Color(0xFF55606E))),
        const SizedBox(height: 18),
        TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: busy ? null : sendCode, icon: const Icon(Icons.sms_outlined), label: Text(sent ? 'إعادة إرسال الرمز' : 'إرسال رمز التحقق')),
        if (sent) ...<Widget>[
          const SizedBox(height: 18),
          TextField(controller: code, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'رمز التحقق (6 أرقام)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          FilledButton(onPressed: busy ? null : resetPassword, child: const Text('تغيير كلمة المرور')),
        ],
        if (busy) const Padding(padding: EdgeInsets.only(top: 18), child: Center(child: CircularProgressIndicator())),
      ]))),
    );
  }
}