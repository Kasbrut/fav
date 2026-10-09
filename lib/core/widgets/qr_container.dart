import 'package:fav/core/theme/app_dimens.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// A white, rounded frame rendering [data] as a QR code.
///
/// The frame stays white in both themes so the code remains scannable.
class QrContainer extends StatelessWidget {
  /// Creates a [QrContainer] encoding [data].
  const QrContainer({required this.data, this.size = 220, super.key});

  /// The payload encoded in the QR code.
  final String data;

  /// The side length, in logical pixels, of the QR image.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: QrImageView(
        data: data,
        size: size,
        backgroundColor: Colors.white,
      ),
    );
  }
}
