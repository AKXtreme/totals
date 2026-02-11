import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/text_utils.dart';

class RedesignHomePage extends StatefulWidget {
  const RedesignHomePage({super.key});

  @override
  State<RedesignHomePage> createState() => _RedesignHomePageState();
}

class _RedesignHomePageState extends State<RedesignHomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<TransactionProvider>(context, listen: false);
      provider.loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<TransactionProvider>(
      builder: (context, provider, child) {
        final summary = provider.summary;
        final totalBalance = summary?.totalBalance ?? 0.0;
        final today = _transactionsForDay(provider.allTransactions, DateTime.now());
        final week = _transactionsForWeek(provider.allTransactions, DateTime.now());
        final todayTotals = _totalsFor(today, provider);
        final weekTotals = _totalsFor(week, provider);
        final todayList = _sortedByTime(today).take(3).toList(growable: false);

        return Scaffold(
          backgroundColor: AppColors.slate50,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TotalBalanceCard(
                    totalBalance: totalBalance,
                    todayIncome: todayTotals.income,
                    todayExpense: todayTotals.expense,
                    weekIncome: weekTotals.income,
                    weekExpense: weekTotals.expense,
                  ),
                  const SizedBox(height: 12),
                  const _InsightCard(),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Today (${today.length})',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.slate900,
                        ),
                      ),
                      TextButton(
                        onPressed: () {},
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: AppColors.primaryLight,
                        ),
                        child: const Text('See all ->'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (provider.isLoading)
                    const _LoadingTransactions()
                  else if (todayList.isEmpty)
                    const _EmptyTransactions()
                  else
                    ...todayList.map((transaction) {
                      final bankLabel = _bankLabel(transaction.bankId);
                      final category = provider.getCategoryById(transaction.categoryId);
                      final categoryLabel = category?.name ?? 'Categorize';
                      final isCategorize = category == null;
                      final isCredit = transaction.type == 'CREDIT';
                      final amountLabel = _amountLabel(
                        transaction.amount,
                        isCredit: isCredit,
                      );
                      final name = _transactionCounterparty(transaction);
                      return _TransactionTile(
                        bank: bankLabel,
                        category: categoryLabel,
                        categoryFilled: isCategorize,
                        amount: amountLabel,
                        amountColor:
                            isCredit ? AppColors.incomeSuccess : AppColors.red,
                        name: name,
                      );
                    }),
                  const SizedBox(height: 16),
                  const _IncomeExpenseCard(),
                  const SizedBox(height: 96),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Totals {
  final double income;
  final double expense;

  const _Totals({required this.income, required this.expense});
}

List<Transaction> _transactionsForDay(
    List<Transaction> transactions, DateTime day) {
  return transactions.where((t) {
    final dt = _parseTransactionTime(t.time);
    if (dt == null) return false;
    return dt.year == day.year && dt.month == day.month && dt.day == day.day;
  }).toList(growable: false);
}

List<Transaction> _transactionsForWeek(
    List<Transaction> transactions, DateTime day) {
  final start = day.subtract(Duration(days: day.weekday - 1));
  final startDate = DateTime(start.year, start.month, start.day);
  final endDate =
      DateTime(day.year, day.month, day.day, 23, 59, 59, 999);
  return transactions.where((t) {
    final dt = _parseTransactionTime(t.time);
    if (dt == null) return false;
    return !dt.isBefore(startDate) && !dt.isAfter(endDate);
  }).toList(growable: false);
}

DateTime? _parseTransactionTime(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return DateTime.parse(raw).toLocal();
  } catch (_) {
    return null;
  }
}

List<Transaction> _sortedByTime(List<Transaction> transactions) {
  final list = List<Transaction>.from(transactions);
  list.sort((a, b) {
    final at = _parseTransactionTime(a.time);
    final bt = _parseTransactionTime(b.time);
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  });
  return list;
}

_Totals _totalsFor(List<Transaction> transactions, TransactionProvider provider) {
  double income = 0.0;
  double expense = 0.0;
  for (final t in transactions) {
    if (provider.isSelfTransfer(t)) continue;
    if (t.type == 'CREDIT') {
      income += t.amount;
    } else if (t.type == 'DEBIT') {
      expense += t.amount;
    }
  }
  return _Totals(income: income, expense: expense);
}

String _bankLabel(int? bankId) {
  if (bankId == null) return 'Bank';
  if (bankId == CashConstants.bankId) return CashConstants.bankShortName;
  try {
    final bank = AppConstants.banks.firstWhere((b) => b.id == bankId);
    return bank.shortName;
  } catch (_) {
    return 'Bank $bankId';
  }
}

String _amountLabel(double amount, {required bool isCredit}) {
  final formatted = formatNumberWithComma(amount);
  return '${isCredit ? '+' : '-'} ETB $formatted';
}

String _transactionCounterparty(Transaction transaction) {
  final receiver = transaction.receiver?.trim();
  final creditor = transaction.creditor?.trim();
  if (receiver != null && receiver.isNotEmpty) return receiver.toUpperCase();
  if (creditor != null && creditor.isNotEmpty) return creditor.toUpperCase();
  return 'UNKNOWN';
}

class _TotalBalanceCard extends StatelessWidget {
  final double totalBalance;
  final double todayIncome;
  final double todayExpense;
  final double weekIncome;
  final double weekExpense;

  const _TotalBalanceCard({
    required this.totalBalance,
    required this.todayIncome,
    required this.todayExpense,
    required this.weekIncome,
    required this.weekExpense,
  });

  @override
  Widget build(BuildContext context) {
    final abbreviated =
        formatNumberAbbreviated(totalBalance).replaceAll('k', 'K');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'TOTAL BALANCE',
                style: TextStyle(
                  color: AppColors.white.withOpacity(0.85),
                  fontSize: 14,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.visibility_off_outlined,
                color: AppColors.white.withOpacity(0.9),
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'ETB$abbreviated',
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 14),
          const _DashedLine(color: AppColors.white, opacity: 0.35),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'How did I get here?',
                style: TextStyle(
                  color: AppColors.white.withOpacity(0.85),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.arrow_forward,
                size: 16,
                color: AppColors.white.withOpacity(0.8),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _DashedLine(color: AppColors.white, opacity: 0.25),
          const SizedBox(height: 14),
          SizedBox(
            height: 56,
            child: Row(
              children: [
                Expanded(
                  child: _BalanceDelta(
                    label: 'TODAY',
                    income: '+ ETB ${_formatDelta(todayIncome)}',
                    expense: '-ETB ${_formatDelta(todayExpense)}',
                  ),
                ),
                const SizedBox(width: 16),
                const _DashedLineVertical(
                  color: AppColors.white,
                  opacity: 0.3,
                  height: 44,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _BalanceDelta(
                    label: 'THIS WEEK',
                    income: '+ ETB ${_formatDelta(weekIncome)}',
                    expense: '-ETB ${_formatDelta(weekExpense)}',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceDelta extends StatelessWidget {
  final String label;
  final String income;
  final String expense;

  const _BalanceDelta({
    required this.label,
    required this.income,
    required this.expense,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.white.withOpacity(0.85),
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          income,
          style: const TextStyle(
            color: AppColors.incomeSuccess,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          expense,
          style: const TextStyle(
            color: AppColors.red,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

String _formatDelta(double value) {
  final formatted = formatNumberAbbreviated(value).replaceAll('k', 'K');
  return formatted;
}

class _DashedLine extends StatelessWidget {
  final Color color;
  final double opacity;

  const _DashedLine({
    required this.color,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 4.0;
        const dashSpace = 4.0;
        final dashCount = (constraints.maxWidth / (dashWidth + dashSpace)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            dashCount,
            (_) => Container(
              width: dashWidth,
              height: 2,
              decoration: BoxDecoration(
                color: color.withOpacity(opacity),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DashedLineVertical extends StatelessWidget {
  final Color color;
  final double opacity;
  final double height;

  const _DashedLineVertical({
    required this.color,
    required this.opacity,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    const dashHeight = 6.0;
    const dashSpace = 6.0;
    final dashCount = (height / (dashHeight + dashSpace)).floor().clamp(1, 12);
    return SizedBox(
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
          dashCount,
          (_) => Container(
            width: 2,
            height: dashHeight,
            decoration: BoxDecoration(
              color: color.withOpacity(opacity),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.amber.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.lightbulb_outline,
              color: AppColors.amber,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'INSIGHT',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.slate500,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "You're on track to save ETB 8,000 this month, that's 25% better than your 3-month average!",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.slate700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final String bank;
  final String category;
  final bool categoryFilled;
  final String amount;
  final Color amountColor;
  final String name;

  const _TransactionTile({
    required this.bank,
    required this.category,
    required this.categoryFilled,
    required this.amount,
    required this.amountColor,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bank,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.slate900,
                  ),
                ),
                const SizedBox(height: 6),
                _CategoryChip(
                  label: category,
                  filled: categoryFilled,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: amountColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                name,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.slate500,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool filled;

  const _CategoryChip({
    required this.label,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    final background = filled
        ? AppColors.primaryLight
        : AppColors.primaryLight.withOpacity(0.12);
    final foreground = filled ? AppColors.white : AppColors.primaryDark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LoadingTransactions extends StatelessWidget {
  const _LoadingTransactions();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (index) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.slate200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'No transactions yet today.',
        style: TextStyle(
          color: AppColors.slate500,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _IncomeExpenseCard extends StatelessWidget {
  const _IncomeExpenseCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Income vs Expense',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate900,
                ),
              ),
              const Spacer(),
              Row(
                children: const [
                  Text(
                    'Week',
                    style: TextStyle(
                      color: AppColors.slate500,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down, size: 16, color: AppColors.slate500),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            width: double.infinity,
            child: CustomPaint(
              painter: _IncomeExpenseChartPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

class _IncomeExpenseChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.slate200
      ..strokeWidth = 1;
    final dashWidth = 4.0;
    final dashSpace = 4.0;

    for (int i = 1; i <= 3; i++) {
      final y = size.height * (i / 4);
      double x = 0;
      while (x < size.width) {
        canvas.drawLine(Offset(x, y), Offset(x + dashWidth, y), gridPaint);
        x += dashWidth + dashSpace;
      }
    }

    final incomePaint = Paint()
      ..color = AppColors.incomeSuccess
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final expensePaint = Paint()
      ..color = AppColors.red
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final incomePoints = [0.2, 0.5, 0.28, 0.6, 0.35, 0.55, 0.42];
    final expensePoints = [0.55, 0.25, 0.62, 0.3, 0.7, 0.38, 0.6];

    Path buildPath(List<double> values) {
      final path = Path();
      for (int i = 0; i < values.length; i++) {
        final x = size.width * (i / (values.length - 1));
        final y = size.height * (1 - values[i]);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      return path;
    }

    canvas.drawPath(buildPath(incomePoints), incomePaint);
    canvas.drawPath(buildPath(expensePoints), expensePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
