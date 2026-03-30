import 'package:flutter/material.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

class AccountShareQrCode extends StatelessWidget {
  static const Color _defaultForegroundColor = Color(0xFF1976D2);
  static const PrettyQrDecorationImage _defaultQrImage =
      PrettyQrDecorationImage(
    image: AssetImage('assets/icon/totals_icon.png'),
    scale: 0.2,
    padding: EdgeInsets.all(6),
  );

  final String data;
  final double size;
  final double borderRadius;
  final EdgeInsets padding;
  final Color backgroundColor;
  final Color foregroundColor;
  final Widget? fallback;

  const AccountShareQrCode({
    super.key,
    required this.data,
    this.size = 220,
    this.borderRadius = 24,
    this.padding = const EdgeInsets.all(18),
    this.backgroundColor = Colors.white,
    this.foregroundColor = _defaultForegroundColor,
    this.fallback,
  });

  static PrettyQrShape buildShape(Color foregroundColor) {
    return PrettyQrShape.custom(
      PrettyQrSmoothSymbol(
        color: foregroundColor,
        roundFactor: 0.9,
      ),
      finderPattern: PrettyQrSquaresSymbol(
        color: foregroundColor,
        density: 1,
        rounding: 0.35,
        unifiedFinderPattern: true,
      ),
      alignmentPatterns: PrettyQrSquaresSymbol(
        color: foregroundColor,
        density: 1,
        rounding: 0.3,
      ),
      timingPatterns: PrettyQrSmoothSymbol(
        color: foregroundColor,
        roundFactor: 0.9,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget qrView;
    try {
      qrView = PrettyQrView.data(
        key: ValueKey<String>('account-share-qr:$data'),
        data: data,
        decoration: PrettyQrDecoration(
          background: backgroundColor,
          shape: buildShape(foregroundColor),
          image: _defaultQrImage,
        ),
      );
    } catch (_) {
      qrView = fallback ?? const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        color: backgroundColor,
        padding: padding,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: qrView),
        ),
      ),
    );
  }
}
