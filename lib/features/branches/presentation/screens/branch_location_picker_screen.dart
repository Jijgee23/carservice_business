import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';

/// Full-screen map with a fixed centre pin (same interaction as signup's
/// location step): drag the map or tap a point, "Миний байршил" asks for
/// the location permission only on tap. Pops with the chosen [LatLng].
class BranchLocationPickerScreen extends StatefulWidget {
  const BranchLocationPickerScreen({super.key, this.initial});

  final LatLng? initial;

  @override
  State<BranchLocationPickerScreen> createState() => _BranchLocationPickerScreenState();
}

class _BranchLocationPickerScreenState extends State<BranchLocationPickerScreen> {
  static const _ulaanbaatar = LatLng(47.9185, 106.9177);
  static const _pickZoom = 17.0;

  final _map = MapController();
  late LatLng _center = widget.initial ?? _ulaanbaatar;
  bool _locating = false;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _moveTo(LatLng point, {double? zoom}) {
    _map.move(point, zoom ?? math.max(_map.camera.zoom, 16));
    setState(() => _center = point);
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        messageWarning('Утасны байршил (GPS) унтраалттай байна. Газрын зургаас гараар сонгоно уу.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        messageWarning('Байршлын зөвшөөрөл өгөөгүй тул газрын зургаас гараар сонгоно уу.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      _moveTo(LatLng(pos.latitude, pos.longitude), zoom: _pickZoom);
    } catch (_) {
      messageWarning('Байршил тогтоож чадсангүй. Газрын зургаас гараар сонгоно уу.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Байршил сонгох')),
      bottomNavigationBar: OpsBottomActionBar(
        children: [
          Expanded(
            child: OpsPrimaryButton(
              key: const ValueKey('branch_location_confirm'),
              label: 'Энэ байршлыг сонгох',
              icon: Icons.check_rounded,
              onPressed: () => Navigator.of(context).pop(_center),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: widget.initial != null ? _pickZoom : 12,
              minZoom: 4,
              maxZoom: 19,
              backgroundColor: t.panel2,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) setState(() => _center = camera.center);
              },
              onTap: (_, point) => _moveTo(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'mn.infosystems.carservice_business',
                maxNativeZoom: 19,
              ),
              SimpleAttributionWidget(
                source: const Text('OpenStreetMap'),
                onTap: () => launchUrl(
                  Uri.parse('https://www.openstreetmap.org/copyright'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
          IgnorePointer(
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -20),
                child: Icon(
                  Icons.location_on_rounded,
                  size: 44,
                  color: t.accent,
                  shadows: const [Shadow(blurRadius: 6, color: Color(0x40000000))],
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: t.panel,
              shape: CircleBorder(side: BorderSide(color: t.border)),
              child: IconButton(
                tooltip: 'Миний байршил',
                onPressed: _locating ? null : _locate,
                color: t.ink,
                icon: _locating
                    ? SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
                      )
                    : const Icon(Icons.my_location_rounded, size: 22),
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: t.panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.border),
              ),
              child: Text(
                '${_center.latitude.toStringAsFixed(6)}, ${_center.longitude.toStringAsFixed(6)}',
                style: opsMono(context, fontSize: 12, color: t.ink),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
