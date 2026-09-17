import 'dart:convert';
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
    try {
      final endpoint = register ? 'register' : 'login';
      final response = await http.post(Uri.parse('$apiUrl/api/auth/$endpoint'), headers: const {'Content-Type': 'application/json'}, body: jsonEncode({'name': name.text.trim(), 'phone': phone.text.trim(), 'password': password.text, 'role': role})).timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(response.body);
      final data = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
      if (response.statusCode >= 200 && response.statusCode < 300 && data['user'] is Map) {
        await widget.onDone('${data['token']}', Map<String, dynamic>.from(data['user'] as Map));
      } else { message('${data['error'] ?? 'تعذر إتمام العملية'}'); }
    } catch (_) { message('تعذر الاتصال بالخادم'); }
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
      final r = await http.post(Uri.parse('$apiUrl/api/requests'), headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'}, body: jsonEncode({'category': service, 'description': desc.text.trim(), 'address': address.text.trim()})).timeout(const Duration(seconds: 15));
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
      final r = await http.get(Uri.parse('$apiUrl/api/requests/mine'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) { final raw = jsonDecode(r.body); items = raw is List ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[]; } else { error = 'تعذر تحميل الطلبات'; }
    } catch (_) { error = 'تعذر الاتصال بالخادم'; }
    if (mounted) setState(() { loading = false; });
  }
  String statusText(dynamic status) { const map = <String, String>{'matching': 'جاري البحث عن فني', 'offer': 'وصل عرض فني', 'accepted': 'تم قبول الفني', 'on_way': 'الفني بالطريق', 'arrived': 'وصل الفني', 'in_progress': 'قيد التنفيذ', 'completed': 'مكتمل', 'cancelled': 'ملغي'}; return map['${status ?? ''}'] ?? '${status ?? ''}'; }
  @override Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[Text(error!), const SizedBox(height: 12), FilledButton(onPressed: load, child: const Text('إعادة المحاولة'))]));
    if (items.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[const Icon(Icons.receipt_long, size: 70, color: Colors.grey), const SizedBox(height: 12), const Text('ما عندك طلبات بعد', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)), const SizedBox(height: 12), FilledButton.icon(onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const NewRequestPage())).then((_) { load(); }); }, icon: const Icon(Icons.add), label: const Text('إنشاء طلب'))]));
    return RefreshIndicator(onRefresh: load, child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: items.length, itemBuilder: (context, i) { final x = items[i]; final k = services.indexOf('${x['category']}'); final n = k < 0 ? 0 : k; return Card(child: ListTile(leading: CircleAvatar(backgroundColor: serviceColors[n].withAlpha(45), foregroundColor: serviceColors[n], child: Icon(serviceIcons[n])), title: Text('${x['category']}', style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text('${x['description']}\n${statusText(x['status'])}'), isThreeLine: true, trailing: const Icon(Icons.chevron_left), onTap: () { Navigator.push(context, MaterialPageRoute(builder: (_) => RequestDetailPage(request: x))).then((_) { load(); }); })); }));
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
      final r = await http.post(Uri.parse('$apiUrl/api/requests/${widget.id}/accept-offer'), headers: {'Authorization': 'Bearer $token'});
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
  final Map<String, dynamic> user; final Future<void> Function() onLogout;
  @override Widget build(BuildContext context) {
    final entries = <Map<String, dynamic>>[
      {'title': 'تعديل الملف الشخصي', 'icon': Icons.edit_outlined, 'text': 'إدارة معلومات الحساب.'},
      {'title': 'العناوين', 'icon': Icons.location_on_outlined, 'text': 'إدارة العناوين المحفوظة.'},
      {'title': 'الإشعارات', 'icon': Icons.notifications_none, 'text': 'إعدادات إشعارات الطلبات والعروض.'},
      {'title': 'الإعدادات', 'icon': Icons.settings_outlined, 'text': 'إعدادات التطبيق العامة.'},
      {'title': 'الأمان والخصوصية', 'icon': Icons.security_outlined, 'text': 'خيارات حماية الحساب.'},
      {'title': 'المساعدة', 'icon': Icons.help_outline, 'text': 'الأسئلة الشائعة والدعم.'},
    ];
    return SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: <Widget>[
      Card(child: Padding(padding: const EdgeInsets.all(20), child: Row(children: <Widget>[const CircleAvatar(radius: 32, child: Icon(Icons.person, size: 34)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text('${user['name'] ?? 'مستخدم'}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text('${user['phone'] ?? ''}')]))]))),
      const SizedBox(height: 12),
      ...entries.map((e) => Card(child: ListTile(leading: Icon(e['icon'] as IconData), title: Text(e['title'] as String, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(e['text'] as String), trailing: const Icon(Icons.chevron_left), onTap: () { Navigator.push(context, MaterialPageRoute(builder: (_) => SimplePage(title: e['title'] as String, icon: e['icon'] as IconData, text: e['text'] as String))); }))),
      const SizedBox(height: 16), FilledButton.tonalIcon(onPressed: onLogout, icon: const Icon(Icons.logout), label: const Text('تسجيل الخروج'))
    ]));
  }
}

class SimplePage extends StatelessWidget {
  const SimplePage({super.key, required this.title, required this.icon, required this.text});
  final String title; final IconData icon; final String text;
  @override Widget build(BuildContext context) { return Scaffold(appBar: AppBar(title: Text(title)), body: Center(child: Padding(padding: const EdgeInsets.all(28), child: Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[CircleAvatar(radius: 36, child: Icon(icon, size: 36)), const SizedBox(height: 16), Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 10), Text(text, textAlign: TextAlign.center)])))))); }
}

class ProviderJobsPage extends StatefulWidget { const ProviderJobsPage({super.key}); @override State<ProviderJobsPage> createState() => _ProviderJobsPageState(); }
class _ProviderJobsPageState extends State<ProviderJobsPage> {
  List<Map<String, dynamic>> jobs = <Map<String, dynamic>>[];
  bool loading = true;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    final p = await SharedPreferences.getInstance(); final token = p.getString('token') ?? '';
    try { final r = await http.get(Uri.parse('$apiUrl/api/providers/requests'), headers: {'Authorization': 'Bearer $token'}); if (r.statusCode == 200) { final raw = jsonDecode(r.body); jobs = raw is List ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[]; } } catch (_) {}
    if (mounted) setState(() { loading = false; });
  }
  Future<void> accept(dynamic id) async {
    final p = await SharedPreferences.getInstance(); final token = p.getString('token') ?? '';
    try { await http.post(Uri.parse('$apiUrl/api/providers/requests/$id/accept'), headers: {'Authorization': 'Bearer $token'}); } catch (_) {}
    await load();
  }
  @override Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (jobs.isEmpty) return RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(18), children: const <Widget>[SizedBox(height: 150), Center(child: Text('لا توجد طلبات حالياً.'))]));
    return RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(18), children: <Widget>[const Text('طلبات قريبة', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)), const SizedBox(height: 12), ...jobs.map((job) => Card(child: ListTile(title: Text('${job['category']}', style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text('${job['description']}\n${job['address'] ?? '-'}'), isThreeLine: true, trailing: FilledButton(onPressed: () { accept(job['id']); }, child: const Text('قبول'))))) ]));
  }
}
