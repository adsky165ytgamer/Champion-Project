import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'data.dart';

// Design tokens: radius 4 (inputs, rows) / 8 (buttons, tiles) / 12 (sheets). Spacing 4-pt grid, 16 margin. One accent.
TextStyle ts(double s, {FontWeight w = FontWeight.w400, Color? c}) => TextStyle(fontSize: s, fontWeight: w, color: c ?? Pal.tx, height: 1.3);
Color al(Color c, double o) => c.withAlpha((o * 255).round());
const _brand = Color(0xFF1F5FD1);

(IconData, Color) kind(Item i) {
  if (i.folder) return (Icons.folder_rounded, const Color(0xFFD9A441));
  final m = i.mime, e = i.ext;
  if (m.contains('spreadsheet') || e == 'xlsx' || e == 'csv') return (Icons.table_chart_rounded, const Color(0xFF2E9E6B));
  if (m.contains('presentation') || e == 'pptx') return (Icons.slideshow_rounded, const Color(0xFFD9623B));
  if (m.contains('document') || e == 'docx' || e == 'doc') return (Icons.description_rounded, const Color(0xFF4F7FD6));
  if (m.contains('pdf') || e == 'pdf') return (Icons.picture_as_pdf_rounded, Pal.danger);
  if (i.isImage) return (Icons.image_rounded, const Color(0xFF1F9AA8));
  if (e == 'zip') return (Icons.folder_zip_rounded, const Color(0xFF8764B8));
  return (Icons.insert_drive_file_rounded, Pal.sub);
}

class Mark extends StatelessWidget {
  const Mark({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _MarkP()));
}

class _MarkP extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final w = s.width;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(w * .22)), Paint()..color = _brand);
    final p = Path()
      ..addOval(Rect.fromCircle(center: Offset(w * .40, w * .52), radius: w * .15))
      ..addOval(Rect.fromCircle(center: Offset(w * .58, w * .44), radius: w * .19))
      ..addRRect(RRect.fromLTRBR(w * .2, w * .52, w * .8, w * .69, Radius.circular(w * .085)));
    c.drawPath(p, Paint()..color = Colors.white);
    c.drawRRect(RRect.fromLTRBR(w * .38, w * .60, w * .62, w * .64, Radius.circular(w * .02)), Paint()..color = _brand);
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}

class Tap extends StatelessWidget {
  const Tap({super.key, required this.child, this.onTap, this.onLong, this.r = 8, this.color = Colors.transparent, this.border = false});
  final Widget child;
  final VoidCallback? onTap, onLong;
  final double r;
  final Color color;
  final bool border;
  @override
  Widget build(BuildContext c) => Material(
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r), side: border ? BorderSide(color: Pal.line) : BorderSide.none),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, onLongPress: onLong, child: child));
}

class Btn extends StatelessWidget {
  const Btn(this.label, {super.key, this.onTap, this.primary = true, this.busy = false, this.danger = false, this.icon});
  final String label;
  final VoidCallback? onTap;
  final bool primary, busy, danger;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final fg = danger ? Colors.white : (primary ? Pal.onAc : Pal.tx);
    return SizedBox(
        width: double.infinity,
        height: 48,
        child: Tap(
            color: danger ? Pal.danger : (primary ? Pal.ac : Colors.transparent),
            border: !primary && !danger,
            onTap: busy ? null : onTap,
            child: Center(
                child: busy
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: 8)],
                        Text(label, style: ts(15, w: FontWeight.w600, c: fg)),
                      ]))));
  }
}

Future<T?> sheet<T>(BuildContext c, Widget child) => showModalBottomSheet<T>(
    context: c,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (b) => Container(
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(color: Pal.surf, borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), border: Border.all(color: Pal.line)),
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(b).viewInsets.bottom),
        child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 32, height: 4, decoration: BoxDecoration(color: Pal.line, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          child,
        ]))));

class Action extends StatelessWidget {
  const Action(this.icon, this.label, {super.key, this.onTap, this.color, this.trailing});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Tap(
      r: 4,
      onTap: onTap,
      child: SizedBox(height: 48, child: Row(children: [
        const SizedBox(width: 4),
        Icon(icon, size: 22, color: color ?? Pal.sub),
        const SizedBox(width: 16),
        Expanded(child: Text(label, style: ts(15, c: color))),
        if (trailing != null) trailing!,
        const SizedBox(width: 4),
      ])));
}

Future<String?> askName(BuildContext c, String title, String initial, String cta) {
  final ctl = TextEditingController(text: initial);
  return sheet<String>(
      c,
      Builder(builder: (b) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: ts(18, w: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
                controller: ctl,
                autofocus: true,
                style: ts(15),
                decoration: InputDecoration(isDense: true, filled: true, fillColor: Pal.canvas, enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Pal.line)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Pal.ac, width: 2))),
                onSubmitted: (v) => Navigator.pop(b, v.trim())),
            const SizedBox(height: 12),
            Btn(cta, onTap: () => Navigator.pop(b, ctl.text.trim())),
          ])));
}

Future<bool> confirm(BuildContext c, String msg, String cta) async =>
    (await sheet<bool>(
        c,
        Builder(builder: (b) => Column(children: [
              Text(msg, style: ts(16, w: FontWeight.w600), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Btn(cta, danger: true, onTap: () => Navigator.pop(b, true)),
              const SizedBox(height: 8),
              Btn('Cancel', primary: false, onTap: () => Navigator.pop(b, false)),
            ])))) ??
    false;

// ---------- Welcome ----------
class Welcome extends StatelessWidget {
  const Welcome({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store,
      builder: (c, _) => Scaffold(
          backgroundColor: Pal.surf,
          body: SafeArea(
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const SizedBox(height: 24),
                            Row(children: [const Mark(size: 32), const SizedBox(width: 10), Text('Cloud Box', style: ts(18, w: FontWeight.w600))]),
                            const Spacer(),
                            Text('Sign in', style: ts(28, w: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Text('Browse and manage the files in your Google Drive.', style: ts(15, c: Pal.sub)),
                            const SizedBox(height: 24),
                            if (store.authError != null)
                              Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: al(Pal.danger, .1), borderRadius: BorderRadius.circular(4), border: Border(left: BorderSide(color: Pal.danger, width: 3))),
                                  child: Text(store.authError!, style: ts(13))),
                            Btn('Sign in with Google', icon: Icons.login_rounded, busy: store.signingIn, onTap: store.signIn),
                            const SizedBox(height: 16),
                            Text('Cloud Box asks Google for access to view and manage your real Drive files. Nothing is uploaded by Cloud Box except actions you explicitly request.', style: ts(12, c: Pal.sub)),
                            const Spacer(flex: 2),
                          ])))))));
}

// ---------- Shell ----------
const _dests = [
  (Dest.files, Icons.folder_outlined, Icons.folder_rounded, 'My files'),
  (Dest.recent, Icons.schedule_rounded, Icons.schedule_rounded, 'Recent'),
  (Dest.photos, Icons.photo_outlined, Icons.photo_rounded, 'Photos'),
  (Dest.shared, Icons.people_outline_rounded, Icons.people_rounded, 'Shared'),
  (Dest.offline, Icons.download_for_offline_outlined, Icons.download_for_offline_rounded, 'Offline'),
];
String destName(Dest d) => _dests.firstWhere((e) => e.$1 == d).$4;

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && store.signedIn) store.refresh();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store,
      builder: (c, _) => LayoutBuilder(builder: (c, box) {
            final wide = box.maxWidth >= 840;
            return PopScope(
                canPop: !store.canBack,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) store.back();
                },
                child: Scaffold(
                    backgroundColor: Pal.surf,
                    drawer: wide ? null : Drawer(width: 304, backgroundColor: Pal.surf, shape: const RoundedRectangleBorder(), child: const SafeArea(child: NavPanel(inDrawer: true))),
                    floatingActionButton: store.dest == Dest.files && store.selected.isEmpty && !store.searching
                        ? FloatingActionButton.extended(
                            onPressed: () async {
                              final n = await askName(c, 'New folder', '', 'Create');
                              if (n != null && n.isNotEmpty) store.newFolder(n);
                            },
                            backgroundColor: Pal.ac,
                            foregroundColor: Pal.onAc,
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            icon: const Icon(Icons.create_new_folder_outlined),
                            label: Text('New folder', style: ts(14, w: FontWeight.w600, c: Pal.onAc)))
                        : null,
                    body: SafeArea(
                        child: Row(children: [
                      if (wide) Container(width: 264, decoration: BoxDecoration(color: Pal.canvas, border: Border(right: BorderSide(color: Pal.line))), child: const NavPanel()),
                      Expanded(child: Column(children: [_Bar(wide: wide), if (store.dest == Dest.files && !store.searching) const _Crumbs(), if (store.loading) LinearProgressIndicator(minHeight: 2, color: Pal.ac, backgroundColor: Colors.transparent) else const SizedBox(height: 2), const Expanded(child: _Content())])),
                    ]))));
          }));
}

class NavPanel extends StatelessWidget {
  const NavPanel({super.key, this.inDrawer = false});
  final bool inDrawer;
  @override
  Widget build(BuildContext c) => ListenableBuilder(listenable: store, builder: (c, _) => _body(c));
  Widget _body(BuildContext c) {
    final q = store.quota;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 12), child: Row(children: [const Mark(size: 28), const SizedBox(width: 10), Text('Cloud Box', style: ts(17, w: FontWeight.w600))])),
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(store.user?.email ?? '', style: ts(13, c: Pal.sub), maxLines: 1, overflow: TextOverflow.ellipsis)),
      for (final d in _dests)
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            child: Tap(
                r: 4,
                color: store.dest == d.$1 ? Pal.acSoft : Colors.transparent,
                onTap: () {
                  if (inDrawer) Navigator.pop(c);
                  store.go(d.$1);
                },
                child: SizedBox(height: 44, child: Row(children: [
                  const SizedBox(width: 12),
                  Icon(store.dest == d.$1 ? d.$3 : d.$2, size: 22, color: store.dest == d.$1 ? Pal.ac : Pal.sub),
                  const SizedBox(width: 16),
                  Text(d.$4, style: ts(15, w: store.dest == d.$1 ? FontWeight.w600 : FontWeight.w400, c: store.dest == d.$1 ? Pal.ac : Pal.tx)),
                ])))),
      const Spacer(),
      Divider(height: 1, color: Pal.line),
      Padding(
          padding: const EdgeInsets.all(8),
          child: Tap(
              r: 4,
              onTap: () {
                if (inDrawer) Navigator.pop(c);
                Navigator.push(c, MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
              },
              child: SizedBox(height: 44, child: Row(children: [const SizedBox(width: 12), Icon(Icons.settings_outlined, size: 22, color: Pal.sub), const SizedBox(width: 16), Text('Settings', style: ts(15))])))),
      if (q != null)
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(q.$2 == null ? '${fmtSize(q.$1)} used' : '${fmtSize(q.$1)} of ${fmtSize(q.$2!)} used', style: ts(13, c: Pal.sub)),
              const SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: q.$2 == null ? 0 : (q.$1 / q.$2!).clamp(0.0, 1.0), minHeight: 4, backgroundColor: Pal.line, color: Pal.ac)),
            ])),
    ]);
  }
}

class _Bar extends StatefulWidget {
  const _Bar({required this.wide});
  final bool wide;
  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> {
  final ctl = TextEditingController();
  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget bar(List<Widget> kids) => Container(height: 56, padding: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Pal.line))), child: Row(children: kids));
    IconButton ib(IconData i, VoidCallback f, {Color? c, String? tip}) => IconButton(onPressed: f, tooltip: tip, icon: Icon(i, color: c ?? Pal.tx));
    if (store.selected.isNotEmpty) {
      final sel = store.shown.where((i) => store.selected.contains(i.id)).toList();
      return bar([
        ib(Icons.close_rounded, store.back, tip: 'Clear selection'),
        Expanded(child: Text('${sel.length} selected', style: ts(17, w: FontWeight.w600))),
        if (store.repo.canOffline) ib(Icons.download_for_offline_outlined, () { for (final i in sel) { store.saveOffline(i); } store.set(store.selected.clear); }, tip: 'Make available offline'),
        ib(Icons.delete_outline_rounded, () async { if (await confirm(context, 'Move ${sel.length} item(s) to the bin?', 'Move to bin')) store.trash(sel); }, c: Pal.danger, tip: 'Move to bin'),
      ]);
    }
    if (store.searching) {
      return bar([
        ib(Icons.arrow_back_rounded, store.endSearch),
        Expanded(child: TextField(controller: ctl, autofocus: true, textInputAction: TextInputAction.search, style: ts(16), decoration: InputDecoration(border: InputBorder.none, hintText: 'Search My Drive', hintStyle: ts(16, c: Pal.sub)), onSubmitted: (v) { if (v.trim().isNotEmpty) store.search(v); })),
        if (store.query.isNotEmpty) ib(Icons.close_rounded, () { ctl.clear(); store.endSearch(); }),
      ]);
    }
    return bar([
      if (!widget.wide) ib(Icons.menu_rounded, () => Scaffold.of(context).openDrawer(), tip: 'Menu') else const SizedBox(width: 12),
      Expanded(child: Text(destName(store.dest), style: ts(20, w: FontWeight.w600))),
      ib(Icons.search_rounded, () { ctl.clear(); store.set(() => store.searching = true); }, tip: 'Search'),
      ib(Icons.refresh_rounded, () => store.refresh(), tip: 'Refresh Drive data'),
      if (store.dest != Dest.photos) ib(store.grid ? Icons.view_list_rounded : Icons.grid_view_rounded, () => store.set(() => store.grid = !store.grid), tip: store.grid ? 'List view' : 'Grid view'),
    ]);
  }
}

class _Crumbs extends StatelessWidget {
  const _Crumbs();
  @override
  Widget build(BuildContext c) => ListenableBuilder(listenable: store, builder: (c, _) => _body(c));
  Widget _body(BuildContext c) => Container(
      height: 44,
      padding: const EdgeInsets.only(left: 8, right: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Pal.line))),
      child: Row(children: [
        Expanded(
            child: ListView(scrollDirection: Axis.horizontal, reverse: true, children: [
          Row(children: [
            for (var i = 0; i < store.path.length; i++) ...[
              if (i > 0) Icon(Icons.chevron_right_rounded, size: 18, color: Pal.sub),
              Tap(r: 4, onTap: i == store.path.length - 1 ? null : () => store.crumbTo(i), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10), child: Text(store.path[i].name, style: ts(14, w: i == store.path.length - 1 ? FontWeight.w600 : FontWeight.w400, c: i == store.path.length - 1 ? Pal.tx : Pal.ac)))),
            ]
          ]),
        ])),
        Tap(r: 4, onTap: () => sortSheet(c), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10), child: Row(children: [Icon(store.asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 16, color: Pal.sub), const SizedBox(width: 4), Text(store.sort.name[0].toUpperCase() + store.sort.name.substring(1), style: ts(14, c: Pal.sub))]))),
      ]));
}

// ---------- Content ----------
class _Content extends StatelessWidget {
  const _Content();
  @override
  Widget build(BuildContext c) => ListenableBuilder(listenable: store, builder: (c, _) => _body(c));
  Widget _body(BuildContext c) {
    final l = store.shown;
    Diag.change('ui:content', 'loading=${store.loading} err=${store.err != null} items=${l.length} dest=${store.dest.name}');
    if (store.loading && l.isEmpty && store.dest != Dest.offline) return Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: Pal.ac));
    if (store.err != null) return Msg(Icons.error_outline_rounded, 'Couldn\'t load files', store.err!, action: 'Try again', onAction: store.load);
    if (l.isEmpty) {
      return switch (store.dest) {
        Dest.files => store.query.isNotEmpty ? Msg(Icons.search_off_rounded, 'No results', 'Nothing matches “${store.query}”.') : const Msg(Icons.folder_open_rounded, 'This folder is empty', 'Use New folder to add one.'),
        Dest.recent => const Msg(Icons.schedule_rounded, 'No recent files', 'Files you change will appear here.'),
        Dest.photos => const Msg(Icons.photo_outlined, 'No photos', 'Images stored in your Drive appear here.'),
        Dest.shared => const Msg(Icons.people_outline_rounded, 'Nothing shared with you', 'Files others share with you appear here.'),
        Dest.offline => Msg(Icons.download_for_offline_outlined, 'No offline files', store.repo.canOffline ? 'Open a file’s menu and choose “Make available offline”.' : 'Offline files need a connected Google Drive account.'),
      };
    }
    if (store.dest == Dest.photos) return const PhotoGrid();
    if (store.grid) return GridView.builder(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 200, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: .95), itemCount: l.length, itemBuilder: (_, k) => ItemTile(l[k]));
    return ListView.builder(padding: const EdgeInsets.only(bottom: 96), itemCount: l.length, itemBuilder: (_, k) => ItemRow(l[k]));
  }
}

class Msg extends StatelessWidget {
  const Msg(this.icon, this.title, this.sub, {super.key, this.action, this.onAction});
  final IconData icon;
  final String title, sub;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 64),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40, color: Pal.sub),
            const SizedBox(height: 12),
            Text(title, style: ts(17, w: FontWeight.w600), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(sub, style: ts(14, c: Pal.sub), textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), SizedBox(width: 160, child: Btn(action!, primary: false, onTap: onAction))],
          ])));
}

void activate(BuildContext c, Item i) {
  if (store.selected.isNotEmpty) {
    store.toggleSel(i.id);
  } else if (i.folder) {
    store.open(i);
  } else {
    itemSheet(c, i, preview: true);
  }
}

String meta(Item i) => i.folder || i.size == 0 ? fmtDate(i.date) : '${fmtDate(i.date)} · ${fmtSize(i.size)}';

class ItemRow extends StatelessWidget {
  const ItemRow(this.i, {super.key});
  final Item i;
  @override
  Widget build(BuildContext c) {
    final sel = store.selected.contains(i.id), selecting = store.selected.isNotEmpty;
    final (ic, col) = kind(i);
    final dl = store.downloads[i.id];
    return Tap(
        r: 0,
        color: sel ? Pal.acSoft : Colors.transparent,
        onTap: () => activate(c, i),
        onLong: () => store.toggleSel(i.id),
        child: Container(
            height: 60,
            padding: const EdgeInsets.only(left: 16),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Pal.line))),
            child: Row(children: [
              Icon(selecting ? (sel ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded) : ic, color: selecting ? (sel ? Pal.ac : Pal.sub) : col, size: 28),
              const SizedBox(width: 16),
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(i.name, style: ts(15, w: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(dl != null ? 'Downloading ${(dl * 100).round()}%' : meta(i), style: ts(13, c: Pal.sub), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              if (i.shared) Padding(padding: const EdgeInsets.only(left: 8), child: Icon(Icons.people_outline_rounded, size: 18, color: Pal.sub)),
              if (store.isSaved(i.id)) Padding(padding: const EdgeInsets.only(left: 8), child: Icon(Icons.offline_pin_rounded, size: 18, color: Pal.ac)),
              if (dl != null) Padding(padding: const EdgeInsets.only(left: 8), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(value: dl > 0 ? dl : null, strokeWidth: 2, color: Pal.ac))),
              IconButton(onPressed: () => itemSheet(c, i), tooltip: 'More actions', icon: Icon(Icons.more_vert_rounded, color: Pal.sub)),
            ])));
  }
}

class ItemTile extends StatelessWidget {
  const ItemTile(this.i, {super.key});
  final Item i;
  @override
  Widget build(BuildContext c) {
    final sel = store.selected.contains(i.id);
    final (ic, col) = kind(i);
    return Tap(
        color: sel ? Pal.acSoft : Pal.surf,
        border: true,
        onTap: () => activate(c, i),
        onLong: () => store.toggleSel(i.id),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Container(width: double.infinity, color: Pal.canvas, child: i.thumb != null ? Image.network(i.thumb!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(ic, size: 36, color: col)) : Icon(ic, size: 36, color: col))),
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
              child: Row(children: [
                Icon(sel ? Icons.check_box_rounded : ic, size: 20, color: sel ? Pal.ac : col),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.name, style: ts(14, w: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(meta(i), style: ts(12, c: Pal.sub), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                InkWell(onTap: () => itemSheet(c, i), child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.more_vert_rounded, size: 20, color: Pal.sub))),
              ])),
        ]));
  }
}

// ---------- Photos ----------
class PhotoGrid extends StatelessWidget {
  const PhotoGrid({super.key});
  @override
  Widget build(BuildContext c) => ListenableBuilder(listenable: store, builder: (c, _) => _body(c));
  Widget _body(BuildContext c) {
    final l = store.shown;
    final g = <String, List<Item>>{};
    for (final p in l) {
      g.putIfAbsent(fmtMonth(p.date), () => []).add(p);
    }
    return CustomScrollView(slivers: [
      for (final e in g.entries) ...[
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text(e.key, style: ts(14, w: FontWeight.w600)))),
        SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            sliver: SliverGrid.count(crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2, children: [
              for (final p in e.value)
                Tap(r: 0, color: Pal.canvas, onTap: () => Navigator.push(c, MaterialPageRoute<void>(builder: (_) => Viewer(l, l.indexOf(p)))), child: p.thumb != null ? Image.network(p.thumb!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.image_rounded, color: Pal.sub)) : Icon(Icons.image_rounded, color: Pal.sub)),
            ])),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 32)),
    ]);
  }
}

class Viewer extends StatelessWidget {
  const Viewer(this.l, this.start, {super.key});
  final List<Item> l;
  final int start;
  @override
  Widget build(BuildContext c) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(l[start].name, style: ts(16, c: Colors.white))),
      body: PageView.builder(
          controller: PageController(initialPage: start),
          itemCount: l.length,
          itemBuilder: (_, k) {
            final t = l[k].thumb?.replaceAll(RegExp(r'=s\d+$'), '=s1600');
            return Center(child: t == null ? const Icon(Icons.image_rounded, size: 64, color: Colors.white38) : InteractiveViewer(child: Image.network(t, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, size: 64, color: Colors.white38))));
          }));
}

// ---------- Sheets ----------
void itemSheet(BuildContext c, Item i, {bool preview = false}) {
  final (ic, col) = kind(i);
  sheet(
      c,
      Builder(builder: (b) {
        final saved = store.isSaved(i.id);
        return Column(children: [
          if (preview) Container(height: 140, width: double.infinity, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Pal.canvas, borderRadius: BorderRadius.circular(8)), clipBehavior: Clip.antiAlias, child: i.thumb != null ? Image.network(i.thumb!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(ic, size: 48, color: col)) : Icon(ic, size: 48, color: col)),
          Row(children: [
            Icon(ic, color: col, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.name, style: ts(16, w: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
              Text(meta(i), style: ts(13, c: Pal.sub)),
            ])),
          ]),
          const SizedBox(height: 8),
          Divider(height: 1, color: Pal.line),
          if (i.link != null) Action(Icons.open_in_new_rounded, 'Open in Google Drive', onTap: () { Navigator.pop(b); launchUrl(Uri.parse(i.link!), mode: LaunchMode.externalApplication); }),
          if (store.repo.canOffline && !i.folder)
            Action(saved ? Icons.cloud_off_rounded : Icons.download_for_offline_outlined, saved ? 'Remove from offline' : (i.native ? 'Google file: can\'t be saved offline yet' : 'Make available offline'),
                onTap: i.native ? null : () { Navigator.pop(b); saved ? store.removeOffline(i) : store.saveOffline(i); }),
          Action(Icons.edit_outlined, 'Rename', onTap: () async {
            Navigator.pop(b);
            final n = await askName(c, 'Rename', i.name, 'Save');
            if (n != null && n.isNotEmpty && n != i.name) store.rename(i, n);
          }),
          Action(Icons.info_outline_rounded, 'Details', onTap: () { Navigator.pop(b); details(c, i); }),
          Action(Icons.delete_outline_rounded, 'Move to bin', color: Pal.danger, onTap: () async {
            Navigator.pop(b);
            if (await confirm(c, 'Move “${i.name}” to the bin?', 'Move to bin')) store.trash([i]);
          }),
        ]);
      }));
}

void details(BuildContext c, Item i) {
  Widget r(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 96, child: Text(k, style: ts(14, c: Pal.sub))), Expanded(child: Text(v, style: ts(14)))]));
  sheet(c, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Details', style: ts(18, w: FontWeight.w600)),
    const SizedBox(height: 8),
    r('Name', i.name),
    r('Type', i.folder ? 'Folder' : (i.mime.isEmpty ? (i.ext.isEmpty ? 'File' : i.ext.toUpperCase()) : i.mime.replaceFirst('application/vnd.google-apps.', 'Google ').replaceFirst('application/', ''))),
    if (!i.folder && i.size > 0) r('Size', fmtSize(i.size)),
    r('Modified', fmtDate(i.date)),
    r('Sharing', i.shared ? 'Shared' : 'Only you'),
    r('Offline', store.isSaved(i.id) ? 'Available' : 'No'),
  ]));
}

void sortSheet(BuildContext c) => sheet(
    c,
    ListenableBuilder(
        listenable: store,
        builder: (b, _) => Column(children: [
              Align(alignment: Alignment.centerLeft, child: Text('Sort by', style: ts(18, w: FontWeight.w600))),
              const SizedBox(height: 4),
              for (final s in Sort.values)
                Action(Icons.sort_rounded, s.name[0].toUpperCase() + s.name.substring(1),
                    trailing: store.sort == s ? Icon(store.asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 20, color: Pal.ac) : null,
                    color: store.sort == s ? Pal.ac : null,
                    onTap: () => store.set(() {
                          if (store.sort == s) {
                            store.asc = !store.asc;
                          } else {
                            store.sort = s;
                            store.asc = true;
                          }
                        })),
            ])));

// ---------- Settings ----------
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store,
      builder: (c, _) {
        Widget h(String t) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 4), child: Text(t.toUpperCase(), style: ts(12, w: FontWeight.w600, c: Pal.sub)));
        Widget opt(String t, bool on, VoidCallback f) => Tap(r: 0, onTap: f, child: Container(height: 48, padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [Expanded(child: Text(t, style: ts(15))), if (on) Icon(Icons.check_rounded, color: Pal.ac)])));
        final u = store.user;
        return Scaffold(
            backgroundColor: Pal.surf,
            appBar: AppBar(backgroundColor: Pal.surf, surfaceTintColor: Colors.transparent, title: Text('Settings', style: ts(20, w: FontWeight.w600))),
            body: ListView(children: [
              h('Account'),
              Padding(padding: const EdgeInsets.all(16), child: Row(children: [
                CircleAvatar(radius: 22, backgroundColor: Pal.acSoft, backgroundImage: u?.photoUrl != null ? NetworkImage(u!.photoUrl!) : null, child: u?.photoUrl == null ? Icon(Icons.person_rounded, color: Pal.ac) : null),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u?.displayName ?? 'Google account', style: ts(16, w: FontWeight.w600)),
                  Text(u?.email ?? '', style: ts(13, c: Pal.sub)),
                ])),
              ])),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Provider: Google Drive · connected')),
              h('Appearance'),
              opt('System default', store.mode == ThemeMode.system, () => store.set(() => store.mode = ThemeMode.system)),
              opt('Light', store.mode == ThemeMode.light, () => store.set(() => store.mode = ThemeMode.light)),
              opt('Dark', store.mode == ThemeMode.dark, () => store.set(() => store.mode = ThemeMode.dark)),
              h('Files view'),
              opt('List', !store.grid, () => store.set(() => store.grid = false)),
              opt('Grid', store.grid, () => store.set(() => store.grid = true)),
              Tap(r: 0, onTap: () => Navigator.push(c, MaterialPageRoute<void>(builder: (_) => const DiagPage())), child: Container(height: 48, padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [Expanded(child: Text('Diagnostics (temporary)', style: ts(15))), Icon(Icons.chevron_right_rounded, color: Pal.sub)]))),
              h('About'),
              Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: Text('Cloud Box 0.2.0\ncom.cloudbox.cloud_box', style: ts(14, c: Pal.sub))),
              const SizedBox(height: 16),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Btn('Sign out', primary: false, onTap: () async {
                Navigator.pop(c);
                await store.signOut();
              })),
              const SizedBox(height: 32),
            ]));
      });
}

class DiagPage extends StatefulWidget {
  const DiagPage({super.key});
  @override
  State<DiagPage> createState() => _DiagState();
}

class _DiagState extends State<DiagPage> {
  @override
  Widget build(BuildContext context) {
    final text = Diag.log.join('\n');
    return Scaffold(
        backgroundColor: Pal.surf,
        appBar: AppBar(backgroundColor: Pal.surf, surfaceTintColor: Colors.transparent, title: Text('Diagnostics', style: ts(20, w: FontWeight.w600)), actions: [
          IconButton(tooltip: 'Refresh', onPressed: () => setState(() {}), icon: const Icon(Icons.refresh_rounded)),
          IconButton(tooltip: 'Copy', onPressed: () { Clipboard.setData(ClipboardData(text: text)); toast('Diagnostic log copied.'); }, icon: const Icon(Icons.copy_rounded)),
        ]),
        body: SingleChildScrollView(padding: const EdgeInsets.all(12), child: SelectableText(text.isEmpty ? 'No entries yet.' : text, style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: Pal.tx, height: 1.4))));
  }
}
