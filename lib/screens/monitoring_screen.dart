import 'package:flutter/material.dart';
import '../widgets/custom_header.dart';
import '../widgets/camera_stream_card.dart';
import '../widgets/scrollable_page.dart';

class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  // null = not yet known (still connecting), true/false = actual stream state.
  bool? _isStreamConnected;

  @override
  Widget build(BuildContext context) {
    return ScrollablePage(
      child: Column(
        children: [
          const CustomHeader(
            title: "Monitoring",
            subtitle: "Live Stream from Syncubator",
            icon: Icons.videocam_rounded,
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                CameraStreamCard(
                  onConnectionChanged: (connected) {
                    if (mounted) setState(() => _isStreamConnected = connected);
                  },
                ),
                const SizedBox(height: 20),
                const _InfoTile(
                  icon: Icons.sensors,
                  title: "Source",
                  value: "IMX708 Camera Sensor",
                ),
                const SizedBox(height: 12),
                const _InfoTile(
                  icon: Icons.speed,
                  // BUG FIX: Flask's rpicam-vid is configured with
                  // --framerate 20, not 30 — this label was just wrong.
                  title: "Resolution",
                  value: "640x480 @ 20fps",
                ),
                const SizedBox(height: 12),
                _InfoTile(
                  icon: Icons.wifi,
                  title: "Status",
                  // BUG FIX: this used to always read "Connected" in green,
                  // even when the stream was down — now reflects the real
                  // state reported by CameraStreamCard.
                  value: _statusLabel(),
                  statusColor: _statusColor(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel() {
    switch (_isStreamConnected) {
      case true:
        return "Connected";
      case false:
        return "Disconnected";
      default:
        return "Connecting...";
    }
  }

  Color _statusColor() {
    switch (_isStreamConnected) {
      case true:
        return Colors.green;
      case false:
        return Colors.red;
      default:
        return Colors.orange;
    }
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color? statusColor;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
    this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).primaryColor),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: statusColor ?? Colors.black87,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}