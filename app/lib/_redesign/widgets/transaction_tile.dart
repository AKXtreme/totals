import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:totals/_redesign/theme/app_colors.dart';

/// Shared transaction tile used across all redesign pages.
///
/// Layout matches the money-page "transactions section" style:
///   Left:  bank name  +  category chip
///   Right: amount     +  name (marquee if long)  +  optional timestamp
class TransactionTile extends StatelessWidget {
  final String bank;
  final String category;
  final bool isCategorized;

  /// Whether the transaction is a debit (expense).
  /// Used to pick the category chip color.
  final bool isDebit;

  /// Whether the transaction is a self-transfer (e.g. ATM withdrawal → deposit).
  /// When true the tile is rendered in a faded/muted style.
  final bool isSelfTransfer;

  /// Whether the transaction is categorized as Misc/uncategorized.
  /// When true the tile is rendered faded with a grey chip.
  final bool isMisc;

  final String amount;
  final Color amountColor;
  final String name;

  /// Optional timestamp line shown below the name.
  final String? timestamp;

  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TransactionTile({
    super.key,
    required this.bank,
    required this.category,
    required this.isCategorized,
    required this.isDebit,
    required this.amount,
    required this.amountColor,
    required this.name,
    this.isSelfTransfer = false,
    this.isMisc = false,
    this.timestamp,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faded = isSelfTransfer || isMisc;

    return Opacity(
      opacity: faded ? 0.5 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryLight.withValues(alpha: 0.08)
              : AppColors.cardColor(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                selected ? AppColors.primaryLight : AppColors.borderColor(context),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                if (selected) ...[
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: AppColors.primaryLight,
                  ),
                  const SizedBox(width: 10),
                ],
                // Left: bank + category
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bank,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(context),
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TransactionCategoryChip(
                        label: category,
                        isCategorized: isCategorized,
                        isDebit: isDebit,
                        isSelfTransfer: isSelfTransfer,
                        isMisc: isMisc,
                      ),
                    ],
                  ),
                ),
                // Right: amount + name + timestamp
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        amount,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: faded
                              ? AppColors.textTertiary(context)
                              : amountColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TileMarqueeText(
                        text: name,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.textSecondary(context),
                          letterSpacing: 0.4,
                        ),
                      ),
                      if (timestamp != null && timestamp!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          timestamp!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.textTertiary(context),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Category Chip ───────────────────────────────────────────────────────────

class TransactionCategoryChip extends StatelessWidget {
  final String label;
  final bool isCategorized;
  final bool isDebit;
  final bool isSelfTransfer;
  final bool isMisc;

  const TransactionCategoryChip({
    super.key,
    required this.label,
    required this.isCategorized,
    required this.isDebit,
    this.isSelfTransfer = false,
    this.isMisc = false,
  });

  @override
  Widget build(BuildContext context) {
    // Self-transfer or Misc: neutral gray filled chip
    if (isSelfTransfer || isMisc) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.textTertiary(context),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (isCategorized) {
      final color = isDebit ? AppColors.red : AppColors.incomeSuccess;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.textTertiary(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.isDark(context)
              ? AppColors.slate400
              : AppColors.slate700,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Marquee Text ────────────────────────────────────────────────────────────

class TileMarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const TileMarqueeText({super.key, required this.text, this.style});

  @override
  State<TileMarqueeText> createState() => _TileMarqueeTextState();
}

class _TileMarqueeTextState extends State<TileMarqueeText>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  final _px = ValueNotifier<double>(0.0);
  double _scrollDistance = 0;
  static const _gap = 20.0;
  static const _pxPerSec = 30.0;

  @override
  void dispose() {
    _ticker?.dispose();
    _px.dispose();
    super.dispose();
  }

  void _ensureScroll(double distance) {
    _scrollDistance = distance;
    if (_ticker != null) return;
    _ticker = createTicker((elapsed) {
      _px.value =
          (elapsed.inMicroseconds * _pxPerSec / 1000000.0) % _scrollDistance;
    })..start();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final tp = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();

      if (tp.width <= constraints.maxWidth) {
        return Text(widget.text, style: widget.style, maxLines: 1);
      }

      _ensureScroll(tp.width + _gap);

      return SizedBox(
        width: constraints.maxWidth,
        height: tp.height,
        child: ClipRect(
          child: ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: [0.0, 0.06, 0.94, 1.0],
            ).createShader(bounds),
            blendMode: BlendMode.dstIn,
            child: OverflowBox(
              maxWidth: double.infinity,
              alignment: Alignment.centerLeft,
              child: ValueListenableBuilder<double>(
                valueListenable: _px,
                builder: (context, px, child) => Transform.translate(
                  offset: Offset(-px, 0),
                  child: child,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.text, style: widget.style),
                    const SizedBox(width: _gap),
                    Text(widget.text, style: widget.style),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}
