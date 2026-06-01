// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────

/// GeoLockData – backward-compatible with old format {text, lat, lng}.
class GeoLockData {
  final String text;
  final double lat;
  final double lng;
  final bool hideLocation;  // true = ẩn địa điểm, false = hiện địa điểm
  final String locationName;
  final double radius; // meters

  const GeoLockData({
    required this.text,
    required this.lat,
    required this.lng,
    this.hideLocation = true,
    this.locationName = '',
    this.radius = 100.0,
  });

  factory GeoLockData.fromJson(Map<String, dynamic> json) => GeoLockData(
    text: json['text'] as String? ?? '',
    lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
    lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
    hideLocation: json['hideLocation'] as bool? ?? true,
    locationName: json['locationName'] as String? ?? '',
    radius: (json['radius'] as num?)?.toDouble() ?? 100.0,
  );

  Map<String, dynamic> toJson() => {
    'text': text,
    'lat': lat,
    'lng': lng,
    'hideLocation': hideLocation,
    'locationName': locationName,
    'radius': radius,
  };
}

class _SearchResult {
  final String name, address;
  final double lat, lng;
  const _SearchResult(
      {required this.name,
        required this.address,
        required this.lat,
        required this.lng});
}

// ─────────────────────────────────────────────────────────────────────────────
// GEO LOCK PICKER PAGE
// ─────────────────────────────────────────────────────────────────────────────

/// Full-screen page to pick an unlock location and compose the secret message.
///
/// Returns [GeoLockData] on confirm, null on cancel.
class GeoLockPickerPage extends StatefulWidget {
  const GeoLockPickerPage({super.key});

  @override
  State<GeoLockPickerPage> createState() => _GeoLockPickerPageState();
}

class _GeoLockPickerPageState extends State<GeoLockPickerPage>
    with TickerProviderStateMixin {
  // ── Controllers ──────────────────────────────────────────────────────────
  final Completer<GoogleMapController> _mapCtrl = Completer();
  final TextEditingController _msgCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _msgFocus = FocusNode();
  final FocusNode _searchFocus = FocusNode();

  // ── State ─────────────────────────────────────────────────────────────────
  LatLng? _selected;
  String _locName = '';
  String _locAddress = '';
  bool _hideLocation = true;
  double _radius = 100.0;
  bool _loadingAddr = false;
  bool _gettingMyLoc = false;
  List<_SearchResult> _searchResults = [];
  bool _showResults = false;
  Timer? _debounce;
  bool _canSend = false;
  Set<Marker> _markers = {};
  bool _mapReady = false;

  // Animations
  late final AnimationController _sendBtnAnim;
  late final AnimationController _panelAnim;

  static const _defaultPos = LatLng(16.047079, 108.206230); // Đà Nẵng

  static const _gradientPrimary = [Color(0xFF4A148C), Color(0xFFAB47BC)];
  static const _gradientSend = [Color(0xFF6A1B9A), Color(0xFFCE93D8)];

  @override
  void initState() {
    super.initState();
    _sendBtnAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _panelAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350))
      ..forward();
    _msgCtrl.addListener(_updateCanSend);
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _msgCtrl.removeListener(_updateCanSend);
    _msgCtrl.dispose();
    _searchCtrl.dispose();
    _msgFocus.dispose();
    _searchFocus.dispose();
    _sendBtnAnim.dispose();
    _panelAnim.dispose();
    super.dispose();
  }

  void _updateCanSend() {
    final can = _selected != null && _msgCtrl.text.trim().isNotEmpty;
    if (can != _canSend) {
      setState(() => _canSend = can);
      can ? _sendBtnAnim.forward() : _sendBtnAnim.reverse();
    }
  }

  // ── Location ──────────────────────────────────────────────────────────────

  Future<void> _getCurrentLocation() async {
    setState(() => _gettingMyLoc = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) return;
      }
      if (perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() => _selected = ll);
      _placeMarker(ll);
      _reverseGeocode(ll);
      if (_mapReady) {
        final ctrl = await _mapCtrl.future;
        ctrl.animateCamera(CameraUpdate.newLatLngZoom(ll, 15));
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _gettingMyLoc = false);
    }
  }

  void _placeMarker(LatLng pos) {
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('geolock'),
          position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(270), // purple
          draggable: true,
          onDragEnd: (newPos) {
            setState(() => _selected = newPos);
            _reverseGeocode(newPos);
            _updateCanSend();
          },
        ),
      };
    });
  }

  Future<void> _reverseGeocode(LatLng pos) async {
    setState(() => _loadingAddr = true);
    try {
      final pms = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (!mounted || pms.isEmpty) return;
      final p = pms.first;
      final full = <String>[
        if (p.name?.isNotEmpty == true) p.name!,
        if (p.street?.isNotEmpty == true && p.street != p.name) p.street!,
        if (p.subLocality?.isNotEmpty == true) p.subLocality!,
        if (p.locality?.isNotEmpty == true) p.locality!,
        if (p.administrativeArea?.isNotEmpty == true) p.administrativeArea!,
        if (p.country?.isNotEmpty == true) p.country!,
      ];
      final short = <String>[
        if (p.name?.isNotEmpty == true) p.name!,
        if (p.locality?.isNotEmpty == true) p.locality!,
      ];
      setState(() {
        _locAddress = full.join(', ');
        _locName =
        short.join(', ').isNotEmpty ? short.join(', ') : 'Vị trí đã chọn';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _locName = 'Vị trí đã chọn';
          _locAddress =
          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
        });
      }
    } finally {
      if (mounted) setState(() => _loadingAddr = false);
    }
  }

  void _onMapTap(LatLng pos) {
    _searchFocus.unfocus();
    setState(() {
      _selected = pos;
      _showResults = false;
    });
    _placeMarker(pos);
    _reverseGeocode(pos);
    _updateCanSend();
  }

  // ── Search ────────────────────────────────────────────────────────────────

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _showResults = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 600), () => _doSearch(q));
  }

  Future<void> _doSearch(String q) async {
    if (!mounted) return;
    try {
      final locations = await locationFromAddress(q);
      if (!mounted) return;
      final out = <_SearchResult>[];
      for (final loc in locations.take(5)) {
        try {
          final pms =
          await placemarkFromCoordinates(loc.latitude, loc.longitude);
          if (!mounted) return;
          final p = pms.isNotEmpty ? pms.first : null;
          final name =
          p?.name?.isNotEmpty == true ? p!.name! : q.split(',').first;
          final addr = [p?.street, p?.locality, p?.country]
              .where((s) => s?.isNotEmpty == true)
              .join(', ');
          out.add(_SearchResult(
              name: name, address: addr, lat: loc.latitude, lng: loc.longitude));
        } catch (_) {}
      }
      if (mounted) setState(() {
        _searchResults = out;
        _showResults = out.isNotEmpty;
      });
    } catch (_) {
      if (mounted) setState(() {
        _searchResults = [];
        _showResults = false;
      });
    }
  }

  void _pickResult(_SearchResult r) {
    final ll = LatLng(r.lat, r.lng);
    _searchCtrl.text = r.name;
    _searchFocus.unfocus();
    setState(() {
      _selected = ll;
      _locName = r.name;
      _locAddress = r.address;
      _showResults = false;
    });
    _placeMarker(ll);
    _mapCtrl.future
        .then((c) => c.animateCamera(CameraUpdate.newLatLngZoom(ll, 16)));
    _updateCanSend();
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  void _onSend() {
    if (!_canSend || _selected == null) return;
    HapticFeedback.mediumImpact();
    Navigator.pop(
        context,
        GeoLockData(
          text: _msgCtrl.text.trim(),
          lat: _selected!.latitude,
          lng: _selected!.longitude,
          hideLocation: _hideLocation,
          locationName: _locName,
          radius: _radius,
        ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final mapH = mq.size.height * 0.44;

    return Scaffold(
      backgroundColor: const Color(0xFFF3E5F5),
      body: Column(
        children: [
          _buildHeader(),
          SizedBox(
            height: mapH,
            child: Stack(children: [
              GoogleMap(
                initialCameraPosition:
                const CameraPosition(target: _defaultPos, zoom: 13),
                onMapCreated: (c) {
                  if (!_mapCtrl.isCompleted) {
                    _mapCtrl.complete(c);
                    setState(() => _mapReady = true);
                  }
                },
                markers: _markers,
                onTap: _onMapTap,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                compassEnabled: false,
                padding: const EdgeInsets.only(top: 62),
              ),
              // Search bar
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: _buildSearchBar(),
              ),
              // Search results dropdown
              if (_showResults)
                Positioned(
                  top: 66,
                  left: 12,
                  right: 12,
                  child: _buildSearchResultsList(),
                ),
              // My location FAB
              Positioned(
                bottom: 14,
                right: 14,
                child: _buildMyLocFab(),
              ),
              // Loading geocode
              if (_loadingAddr)
                Positioned(
                  bottom: 14,
                  left: 0,
                  right: 0,
                  child: Center(child: _buildGeocodingBadge()),
                ),
            ]),
          ),
          // Options panel
          Expanded(
            child: SlideTransition(
              position: Tween<Offset>(
                  begin: const Offset(0, 0.3), end: Offset.zero)
                  .animate(CurvedAnimation(
                  parent: _panelAnim, curve: Curves.easeOutCubic)),
              child: FadeTransition(
                opacity: _panelAnim,
                child: _buildOptionsPanel(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: _gradientPrimary),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Chọn Điểm Mở Khóa',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      Text('Chạm bản đồ hoặc tìm địa chỉ',
                          style:
                          TextStyle(color: Colors.white60, fontSize: 11)),
                    ]),
              ),
              AnimatedOpacity(
                opacity: _canSend ? 1.0 : 0.35,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: _canSend ? _onSend : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.5), width: 1),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.lock_rounded, color: Colors.white, size: 14),
                        SizedBox(width: 5),
                        Text('Gửi',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child:
            Icon(Icons.search_rounded, color: Color(0xFF9C27B0), size: 20),
          ),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              onChanged: _onSearchChanged,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              decoration: const InputDecoration.collapsed(
                hintText: 'Nhập địa chỉ hoặc tên địa điểm...',
                hintStyle: TextStyle(color: Colors.grey, fontSize: 13.5),
              ),
            ),
          ),
          if (_searchCtrl.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchCtrl.clear();
                setState(() {
                  _searchResults = [];
                  _showResults = false;
                });
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child:
                Icon(Icons.close_rounded, color: Colors.grey, size: 18),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsList() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 230),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: _searchResults.length,
          separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 48),
          itemBuilder: (_, i) {
            final r = _searchResults[i];
            return ListTile(
              dense: true,
              leading: Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                    color: Color(0xFFF3E5F5),
                    shape: BoxShape.circle),
                child: const Icon(Icons.location_on_rounded,
                    color: Color(0xFF9C27B0), size: 18),
              ),
              title: Text(r.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: Colors.black87)),
              subtitle: r.address.isNotEmpty
                  ? Text(r.address,
                  style: const TextStyle(
                      fontSize: 11.5, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)
                  : null,
              onTap: () => _pickResult(r),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMyLocFab() {
    return GestureDetector(
      onTap: _gettingMyLoc ? null : _getCurrentLocation,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 3))
          ],
        ),
        child: _gettingMyLoc
            ? const Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFF9C27B0)))
            : const Icon(Icons.my_location_rounded,
            color: Color(0xFF9C27B0), size: 22),
      ),
    );
  }

  Widget _buildGeocodingBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
            width: 12,
            height: 12,
            child:
            CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
        SizedBox(width: 8),
        Text('Đang lấy địa chỉ...',
            style: TextStyle(color: Colors.white, fontSize: 12)),
      ]),
    );
  }

  Widget _buildOptionsPanel() {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 14,
          bottom: MediaQuery.of(context).padding.bottom + 14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Selected location card
            if (_selected != null) ...[
              _buildLocationCard(),
              const SizedBox(height: 14),
            ] else ...[
              _buildNoLocationHint(),
              const SizedBox(height: 14),
            ],

            // Message input
            _buildMessageInput(),
            const SizedBox(height: 14),

            // Hide/show toggle
            _buildHideToggle(),

            // Radius slider
            if (_hideLocation) ...[
              const SizedBox(height: 12),
              _buildRadiusSlider(),
            ],

            const SizedBox(height: 18),

            // Send button
            _buildSendButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildNoLocationHint() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3E5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFF9C27B0).withOpacity(0.2), width: 1),
      ),
      child: const Row(children: [
        Icon(Icons.touch_app_rounded, color: Color(0xFF9C27B0), size: 22),
        SizedBox(width: 10),
        Expanded(
          child: Text('Chạm lên bản đồ hoặc tìm địa chỉ để chọn điểm mở khóa',
              style: TextStyle(
                  color: Color(0xFF4A148C),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.4)),
        ),
      ]),
    );
  }

  Widget _buildLocationCard() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF4A148C).withOpacity(0.06),
            const Color(0xFF9C27B0).withOpacity(0.04)
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFF9C27B0).withOpacity(0.25), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
                color: Color(0xFF9C27B0), shape: BoxShape.circle),
            child: const Icon(Icons.pin_drop_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _locName.isNotEmpty ? _locName : 'Vị trí đã chọn',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Color(0xFF4A148C)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_locAddress.isNotEmpty)
                    Text(_locAddress,
                        style: const TextStyle(
                            fontSize: 11.5, color: Colors.grey, height: 1.3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ]),
          ),
          if (_loadingAddr)
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF9C27B0))),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(children: [
          Icon(Icons.lock_rounded, size: 14, color: Color(0xFF6A1B9A)),
          SizedBox(width: 6),
          Text('Tin nhắn bí mật',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4A148C))),
        ]),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: TextField(
            controller: _msgCtrl,
            focusNode: _msgFocus,
            maxLines: 3,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.all(14),
              border: InputBorder.none,
              hintText:
              'Nội dung sẽ hiện ra khi người nhận đến đúng vị trí...',
              hintStyle:
              TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHideToggle() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: _hideLocation
            ? const Color(0xFF311B92).withOpacity(0.05)
            : Colors.teal.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _hideLocation
              ? const Color(0xFF9C27B0).withOpacity(0.2)
              : Colors.teal.withOpacity(0.25),
        ),
      ),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              _hideLocation ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              key: ValueKey(_hideLocation),
              color: _hideLocation ? const Color(0xFF9C27B0) : Colors.teal,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _hideLocation ? '🔒 Ẩn địa điểm đến' : '👁️ Hiện địa điểm đến',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: _hideLocation
                            ? const Color(0xFF4A148C)
                            : Colors.teal.shade700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _hideLocation
                        ? 'Người nhận không biết phải đến đâu để mở khóa'
                        : 'Người nhận thấy địa điểm và có thể chỉ đường',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                        height: 1.35),
                  ),
                ]),
          ),
          Switch(
            value: _hideLocation,
            onChanged: (v) => setState(() => _hideLocation = v),
            activeColor: const Color(0xFF9C27B0),
            activeTrackColor: const Color(0xFF9C27B0).withOpacity(0.3),
            inactiveThumbColor: Colors.teal,
            inactiveTrackColor: Colors.teal.withOpacity(0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildRadiusSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.radar_rounded, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Text('Bán kính mở khóa: ${_radius.toInt()}m',
              style: const TextStyle(
                  fontSize: 12.5,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF9C27B0).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('${_radius.toInt()}m',
                style: const TextStyle(
                    color: Color(0xFF4A148C),
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: const Color(0xFF9C27B0),
            thumbColor: const Color(0xFF6A1B9A),
            inactiveTrackColor: Colors.grey.shade200,
            overlayColor: const Color(0xFF9C27B0).withOpacity(0.12),
            trackHeight: 4,
            thumbShape:
            const RoundSliderThumbShape(enabledThumbRadius: 9),
          ),
          child: Slider(
            value: _radius,
            min: 50,
            max: 500,
            divisions: 9,
            onChanged: (v) => setState(() => _radius = v),
          ),
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('50m', style: TextStyle(fontSize: 10.5, color: Colors.grey)),
            Text('250m',
                style: TextStyle(fontSize: 10.5, color: Colors.grey)),
            Text('500m',
                style: TextStyle(fontSize: 10.5, color: Colors.grey)),
          ],
        ),
      ],
    );
  }

  Widget _buildSendButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        gradient: _canSend
            ? const LinearGradient(colors: _gradientSend)
            : null,
        color: _canSend ? null : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
        boxShadow: _canSend
            ? [
          BoxShadow(
              color: const Color(0xFF9C27B0).withOpacity(0.45),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _canSend ? _onSend : null,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.lock_rounded,
                color: _canSend ? Colors.white : Colors.grey.shade400,
                size: 18),
            const SizedBox(width: 8),
            Text(
              'GỬI TIN NHẮN ẨN ĐỊA ĐIỂM',
              style: TextStyle(
                color:
                _canSend ? Colors.white : Colors.grey.shade400,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                letterSpacing: 0.4,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GEO LOCKED MESSAGE WIDGET  (receiver bubble)
// ─────────────────────────────────────────────────────────────────────────────

class GeoLockedMessageWidget extends StatefulWidget {
  final String content;
  final bool isMe;

  const GeoLockedMessageWidget({
    super.key,
    required this.content,
    required this.isMe,
  });

  @override
  State<GeoLockedMessageWidget> createState() =>
      _GeoLockedMessageWidgetState();
}

class _GeoLockedMessageWidgetState extends State<GeoLockedMessageWidget>
    with SingleTickerProviderStateMixin {
  GeoLockData? _data;
  bool _hasError = false;

  bool _isUnlocked = false;
  bool _checking = false;
  double? _distanceM;
  String _statusMsg = 'Chạm để kiểm tra vị trí của bạn';

  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 480));
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 7), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 7, end: -7), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -7, end: 5), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 5, end: -5), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -5, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeInOut));

    _parseData();
    if (widget.isMe) _isUnlocked = true;
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _parseData() {
    try {
      final json = jsonDecode(widget.content) as Map<String, dynamic>;
      _data = GeoLockData.fromJson(json);
    } catch (_) {
      _hasError = true;
    }
  }

  Future<void> _check() async {
    if (_checking || _isUnlocked || _data == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      _checking = true;
      _statusMsg = 'Đang định vị...';
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _fail('❌ GPS đang tắt, vui lòng bật định vị');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          _fail('❌ Quyền định vị bị từ chối');
          return;
        }
      }
      if (perm == LocationPermission.deniedForever) {
        _fail('❌ Vào Cài đặt để cấp quyền định vị');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      final dist = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, _data!.lat, _data!.lng);

      if (!mounted) return;
      setState(() => _distanceM = dist);

      if (dist <= _data!.radius) {
        HapticFeedback.heavyImpact();
        setState(() {
          _isUnlocked = true;
          _checking = false;
        });
      } else {
        final ds = dist < 1000
            ? '${dist.toInt()}m'
            : '${(dist / 1000).toStringAsFixed(1)}km';
        _fail('Còn cách $ds • cần đến trong ${_data!.radius.toInt()}m');
        _shakeCtrl.forward(from: 0);
        HapticFeedback.vibrate();
      }
    } on LocationServiceDisabledException {
      _fail('❌ Dịch vụ GPS chưa được bật');
    } catch (_) {
      _fail('❌ Không thể xác định vị trí. Thử lại.');
    }
  }

  void _fail(String msg) {
    if (mounted) setState(() {
      _statusMsg = msg;
      _checking = false;
    });
  }

  Future<void> _openMaps() async {
    if (_data == null) return;
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${_data!.lat},${_data!.lng}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError || _data == null) return _buildError();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child:
          ScaleTransition(scale: anim, child: child)),
      child: _isUnlocked
          ? _buildUnlocked(key: const ValueKey('open'))
          : _data!.hideLocation
          ? _buildHidden(key: const ValueKey('hidden'))
          : _buildVisible(key: const ValueKey('visible')),
    );
  }

  // ── Unlocked ──────────────────────────────────────────────────────────────

  Widget _buildUnlocked({Key? key}) {
    final d = _data!;
    return Container(
      key: key,
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.green.withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(children: [
              Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.lock_open_rounded,
                      color: Colors.white, size: 15)),
              const SizedBox(width: 8),
              const Text('🔓 ĐÃ MỞ KHÓA',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 1.2)),
            ]),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.text,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.5)),
                if (d.locationName.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    height: 1,
                    color: Colors.white.withOpacity(0.2),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.check_circle_rounded,
                        color: Colors.white70, size: 13),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Xác thực tại: ${d.locationName}',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontStyle: FontStyle.italic),
                      ),
                    ),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Hidden locked (no location info shown) ────────────────────────────────

  Widget _buildHidden({Key? key}) {
    final d = _data!;
    return AnimatedBuilder(
      key: key,
      animation: _shakeCtrl,
      builder: (_, child) => Transform.translate(
          offset: Offset(_shakeAnim.value, 0), child: child),
      child: GestureDetector(
        onTap: _check,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260, minWidth: 200),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A0533), Color(0xFF2D1B5E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: const Color(0xFFAB47BC).withOpacity(0.35), width: 1),
            boxShadow: [
              BoxShadow(
                  color: Colors.purple.withOpacity(0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20)),
                ),
                child: const Row(children: [
                  Icon(Icons.lock_rounded, color: Color(0xFFCE93D8), size: 14),
                  SizedBox(width: 6),
                  Text('GEO-LOCKED',
                      style: TextStyle(
                          color: Color(0xFFCE93D8),
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 1.8)),
                ]),
              ),

              // Mystery body
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Column(
                  children: [
                    // Mystery map visual
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Column(children: [
                        Stack(alignment: Alignment.center, children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: const Color(0xFF9C27B0).withOpacity(0.15),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: const Color(0xFF9C27B0)
                                      .withOpacity(0.3),
                                  width: 1.5),
                            ),
                            child: const Icon(Icons.pin_drop_rounded,
                                color: Colors.amber, size: 30),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: const BoxDecoration(
                                  color: Color(0xFF9C27B0),
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.lock_rounded,
                                  color: Colors.white, size: 11),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        const Text('Vị trí bí mật',
                            style: TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text('? ? ? ? ?',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.2),
                                fontSize: 14,
                                letterSpacing: 5,
                                fontWeight: FontWeight.w800)),
                      ]),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),

              // Check button
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF5B2D8E), Color(0xFFAB47BC)]),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: const Color(0xFF9C27B0).withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ],
                    ),
                    child: Center(
                      child: _checking
                          ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                          : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.radar_rounded,
                                color: Colors.white, size: 15),
                            SizedBox(width: 6),
                            Text('KIỂM TRA VỊ TRÍ',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    letterSpacing: 0.8)),
                          ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _statusMsg,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        height: 1.4),
                  ),
                  const SizedBox(height: 4),
                  Text('Bán kính: ${d.radius.toInt()}m',
                      style: const TextStyle(
                          color: Colors.white24, fontSize: 10)),
                  const SizedBox(height: 4),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Visible locked (location info shown) ─────────────────────────────────

  Widget _buildVisible({Key? key}) {
    final d = _data!;
    return AnimatedBuilder(
      key: key,
      animation: _shakeCtrl,
      builder: (_, child) => Transform.translate(
          offset: Offset(_shakeAnim.value, 0), child: child),
      child: GestureDetector(
        onTap: _check,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280, minWidth: 200),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0D1B6E), Color(0xFF1565C0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.blue.withOpacity(0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20)),
                ),
                child: const Row(children: [
                  Icon(Icons.lock_rounded, color: Colors.white60, size: 14),
                  SizedBox(width: 6),
                  Text('GEO-LOCKED',
                      style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 1.8)),
                ]),
              ),

              // Location card
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on_rounded,
                              color: Colors.amber, size: 18),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              d.locationName.isNotEmpty
                                  ? d.locationName
                                  : 'Địa điểm mở khóa',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  height: 1.3),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Distance row
                      if (_distanceM != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            const Icon(Icons.straighten_rounded,
                                color: Colors.white60, size: 13),
                            const SizedBox(width: 5),
                            Text(
                              'Cách bạn: ${_distanceM! < 1000 ? "${_distanceM!.toInt()}m" : "${(_distanceM! / 1000).toStringAsFixed(1)}km"}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ]),
                        ),
                      // Directions button
                      GestureDetector(
                        onTap: _openMaps,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.3)),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.directions_rounded,
                                color: Colors.white, size: 14),
                            SizedBox(width: 5),
                            Text('Xem chỉ đường',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Hint
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded,
                      color: Colors.white38, size: 13),
                  const SizedBox(width: 5),
                  Text(
                    'Đến địa điểm trên để mở khóa tin nhắn',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 11.5),
                  ),
                ]),
              ),

              // Check button
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: Column(children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF1E88E5), Color(0xFF42A5F5)]),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.blue.withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ],
                    ),
                    child: Center(
                      child: _checking
                          ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                          : const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.radar_rounded,
                            color: Colors.white, size: 15),
                        SizedBox(width: 6),
                        Text('KIỂM TRA VỊ TRÍ',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                letterSpacing: 0.8)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _statusMsg,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        height: 1.4),
                  ),
                  const SizedBox(height: 3),
                  Text('Bán kính: ${d.radius.toInt()}m',
                      style: const TextStyle(
                          color: Colors.white24, fontSize: 10)),
                  const SizedBox(height: 2),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Error ─────────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline_rounded, color: Colors.red, size: 16),
        SizedBox(width: 6),
        Text('Nội dung tin nhắn không hợp lệ',
            style: TextStyle(color: Colors.red, fontSize: 13)),
      ]),
    );
  }
}