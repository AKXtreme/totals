import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/models/category.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/category_icons.dart';
import 'package:totals/utils/category_style.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Categories Page
// ═════════════════════════════════════════════════════════════════════════════

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _currentFlow => _tabController.index == 1 ? 'income' : 'expense';

  Future<void> _openEditor({Category? existing, String? initialFlow}) async {
    final provider = Provider.of<TransactionProvider>(context, listen: false);

    final result = await showModalBottomSheet<_CategoryEditorResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryEditorSheet(
        existing: existing,
        initialFlow: initialFlow ?? _currentFlow,
      ),
    );

    if (result == null || result.name.trim().isEmpty) return;
    final isUncategorized = result.type == CategoryType.uncategorized;
    final isEssential = result.type == CategoryType.essential;

    try {
      if (existing == null) {
        await provider.createCategory(
          name: result.name,
          essential: isEssential,
          uncategorized: isUncategorized,
          iconKey: result.iconKey,
          colorKey: result.colorKey,
          description: result.description,
          flow: result.flow,
          recurring: result.recurring,
        );
      } else {
        await provider.updateCategory(
          existing.copyWith(
            name: result.name,
            essential: isEssential,
            uncategorized: isUncategorized,
            iconKey: result.iconKey,
            colorKey: result.colorKey,
            description: result.description,
            flow: result.flow,
            recurring: result.recurring,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save category: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background(context),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: AppColors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      appBar: AppBar(
        backgroundColor: AppColors.background(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary(context),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Categories',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary(context),
          ),
        ),
        centerTitle: true,
        actions: const [SizedBox.shrink()],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.mutedFill(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppColors.cardColor(context),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: AppColors.textPrimary(context),
              unselectedLabelColor: AppColors.textSecondary(context),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              tabs: const [
                Tab(text: 'Expenses'),
                Tab(text: 'Income'),
              ],
            ),
          ),
        ),
      ),
      body: Consumer<TransactionProvider>(
        builder: (context, provider, _) {
          final categories = provider.categories;
          final expenseCategories = categories
              .where((c) => c.flow.toLowerCase() != 'income')
              .toList(growable: false);
          final incomeCategories = categories
              .where((c) => c.flow.toLowerCase() == 'income')
              .toList(growable: false);

          return TabBarView(
            controller: _tabController,
            children: [
              _CategoryList(
                categories: expenseCategories,
                emptyLabel: 'No expense categories yet',
                sections: _buildExpenseSections(expenseCategories),
                onEdit: (c) => _openEditor(existing: c),
              ),
              _CategoryList(
                categories: incomeCategories,
                emptyLabel: 'No income categories yet',
                sections: _buildIncomeSections(incomeCategories),
                onEdit: (c) => _openEditor(existing: c),
              ),
            ],
          );
        },
      ),
    );
  }

  List<_CategorySection> _buildExpenseSections(List<Category> cats) {
    final essential =
        cats.where((c) => c.type == CategoryType.essential).toList();
    final nonEssential =
        cats.where((c) => c.type == CategoryType.nonEssential).toList();
    final uncategorized =
        cats.where((c) => c.type == CategoryType.uncategorized).toList();
    return [
      if (essential.isNotEmpty)
        _CategorySection(title: 'Essential', items: essential),
      if (nonEssential.isNotEmpty)
        _CategorySection(title: 'Non-essential', items: nonEssential),
      if (uncategorized.isNotEmpty)
        _CategorySection(title: 'Uncategorized', items: uncategorized),
    ];
  }

  List<_CategorySection> _buildIncomeSections(List<Category> cats) {
    final main = cats.where((c) => c.type == CategoryType.essential).toList();
    final side =
        cats.where((c) => c.type == CategoryType.nonEssential).toList();
    final uncategorized =
        cats.where((c) => c.type == CategoryType.uncategorized).toList();
    return [
      if (main.isNotEmpty) _CategorySection(title: 'Main income', items: main),
      if (side.isNotEmpty) _CategorySection(title: 'Side income', items: side),
      if (uncategorized.isNotEmpty)
        _CategorySection(title: 'Uncategorized', items: uncategorized),
    ];
  }
}

// ── Section data ────────────────────────────────────────────────────────────
class _CategorySection {
  final String title;
  final List<Category> items;
  const _CategorySection({required this.title, required this.items});
}

// ── Category List ───────────────────────────────────────────────────────────
class _CategoryList extends StatelessWidget {
  final List<Category> categories;
  final String emptyLabel;
  final List<_CategorySection> sections;
  final ValueChanged<Category> onEdit;

  const _CategoryList({
    required this.categories,
    required this.emptyLabel,
    required this.sections,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.category_outlined,
              size: 48,
              color: AppColors.textTertiary(context),
            ),
            const SizedBox(height: 12),
            Text(
              emptyLabel,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        for (int s = 0; s < sections.length; s++) ...[
          if (s > 0) const SizedBox(height: 20),
          _SectionHeader(
            title: sections[s].title,
            count: sections[s].items.length,
          ),
          const SizedBox(height: 10),
          for (final c in sections[s].items) ...[
            _CategoryTile(category: c, onTap: () => onEdit(c)),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

// ── Section Header ──────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: AppColors.textTertiary(context),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.mutedFill(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary(context),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Category Tile ───────────────────────────────────────────────────────────
class _CategoryTile extends StatelessWidget {
  final Category category;
  final VoidCallback onTap;

  const _CategoryTile({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = categoryTypeColor(category, context);
    final description = (category.description ?? '').trim();

    return Material(
      color: AppColors.cardColor(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  iconForCategoryKey(category.iconKey),
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            category.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary(context),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (category.recurring) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.refresh_rounded,
                            size: 14,
                            color: AppColors.textTertiary(context),
                          ),
                        ],
                      ],
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary(context),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary(context),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Editor Result
// ═════════════════════════════════════════════════════════════════════════════
class _CategoryEditorResult {
  final String name;
  final CategoryType type;
  final String? iconKey;
  final String? colorKey;
  final String? description;
  final String flow;
  final bool recurring;

  const _CategoryEditorResult({
    required this.name,
    required this.type,
    required this.iconKey,
    required this.colorKey,
    required this.description,
    required this.flow,
    required this.recurring,
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// Editor Sheet
// ═════════════════════════════════════════════════════════════════════════════
class _CategoryEditorSheet extends StatefulWidget {
  final Category? existing;
  final String initialFlow;

  const _CategoryEditorSheet({
    required this.existing,
    required this.initialFlow,
  });

  @override
  State<_CategoryEditorSheet> createState() => _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends State<_CategoryEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late CategoryType _categoryType;
  String? _iconKey;
  String? _colorKey;
  late String _flow;
  late bool _recurring;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _descriptionController =
        TextEditingController(text: widget.existing?.description ?? '');
    _categoryType = widget.existing?.type ?? CategoryType.nonEssential;
    _iconKey = widget.existing?.iconKey ?? 'more_horiz';
    _flow =
        (widget.existing?.flow ?? widget.initialFlow).toLowerCase() == 'income'
            ? 'income'
            : 'expense';
    _recurring = widget.existing?.recurring ?? false;
    _colorKey = resolvedCategoryColorKey(widget.existing ?? _draftCategory());
    _colorKey ??= suggestedCategoryColorKey(
      flow: _flow,
      essential: _categoryType == CategoryType.essential,
      uncategorized: _categoryType == CategoryType.uncategorized,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.pop(
      context,
      _CategoryEditorResult(
        name: _nameController.text,
        type: _categoryType,
        iconKey: _iconKey,
        colorKey: _colorKey,
        description: _descriptionController.text,
        flow: _flow,
        recurring: _recurring,
      ),
    );
  }

  Category _draftCategory() {
    return Category(
      name: _nameController.text.trim(),
      essential: _categoryType == CategoryType.essential,
      uncategorized: _categoryType == CategoryType.uncategorized,
      iconKey: _iconKey,
      colorKey: _colorKey,
      flow: _flow,
      recurring: _recurring,
    );
  }

  Future<void> _handleDelete() async {
    final existing = widget.existing;
    if (existing == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardColor(ctx),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Delete category?',
          style: TextStyle(color: AppColors.textPrimary(ctx)),
        ),
        content: Text(
          'This will remove "${existing.name}" and uncategorize '
          'any transactions using it.',
          style: TextStyle(color: AppColors.textSecondary(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary(ctx)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: TextStyle(color: AppColors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final provider = Provider.of<TransactionProvider>(context, listen: false);
      await provider.deleteCategory(existing);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Category deleted'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete category: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;
    final canDelete = isEdit && (widget.existing?.builtIn != true);
    final isIncome = _flow == 'income';
    final selectedColorKey = _colorKey ??
        suggestedCategoryColorKey(
          flow: _flow,
          essential: _categoryType == CategoryType.essential,
          uncategorized: _categoryType == CategoryType.uncategorized,
        );
    final selectedCategoryColor = categoryColorFromKey(selectedColorKey);

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.slate400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEdit ? 'Edit Category' : 'New Category',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    foregroundColor: AppColors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Flow toggle
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.mutedFill(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _FlowTab(
                      label: 'Expense',
                      selected: !isIncome,
                      onTap: () => setState(() => _flow = 'expense'),
                    ),
                  ),
                  Expanded(
                    child: _FlowTab(
                      label: 'Income',
                      selected: isIncome,
                      onTap: () => setState(() => _flow = 'income'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Name
            _buildTextField(
              context: context,
              controller: _nameController,
              label: 'Name',
              hint: 'e.g. Groceries',
            ),
            const SizedBox(height: 14),

            // Description
            _buildTextField(
              context: context,
              controller: _descriptionController,
              label: 'Description',
              hint: 'Optional note about this category',
              maxLines: 2,
            ),
            const SizedBox(height: 20),

            // Category type
            _buildLabel(context, 'Type'),
            const SizedBox(height: 8),
            _TypeOption(
              title: isIncome ? 'Main income' : 'Essential',
              subtitle: isIncome
                  ? 'Primary income sources'
                  : 'Needs — used for spending insights',
              selected: _categoryType == CategoryType.essential,
              onTap: () => setState(() {
                _categoryType = CategoryType.essential;
              }),
            ),
            const SizedBox(height: 8),
            _TypeOption(
              title: isIncome ? 'Side income' : 'Non-essential',
              subtitle: isIncome
                  ? 'Secondary income sources'
                  : 'Wants — discretionary spending',
              selected: _categoryType == CategoryType.nonEssential,
              onTap: () => setState(() {
                _categoryType = CategoryType.nonEssential;
              }),
            ),
            const SizedBox(height: 8),
            _TypeOption(
              title: 'Uncategorized',
              subtitle: 'Catch-all or mixed transactions',
              selected: _categoryType == CategoryType.uncategorized,
              onTap: () => setState(() {
                _categoryType = CategoryType.uncategorized;
              }),
            ),
            const SizedBox(height: 16),

            // Color picker
            _buildLabel(context, 'Color'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: categoryColorOptions.map((option) {
                final selected = option.key == selectedColorKey;
                return Tooltip(
                  message: option.label,
                  child: GestureDetector(
                    onTap: () => setState(() => _colorKey = option.key),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: option.color,
                        border: Border.all(
                          color: selected
                              ? AppColors.textPrimary(context)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 16),

            // Recurring toggle
            Material(
              color: AppColors.surfaceColor(context),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => setState(() => _recurring = !_recurring),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderColor(context)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.refresh_rounded,
                        size: 20,
                        color: AppColors.textSecondary(context),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recurring',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                            Text(
                              'Monthly/weekly repeating expenses',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary(context),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _recurring,
                        onChanged: (v) => setState(() => _recurring = v),
                        activeColor: selectedCategoryColor,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Icon picker
            _buildLabel(context, 'Icon'),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                const itemSize = 42.0;
                const gap = 8.0;
                final rawCount =
                    ((constraints.maxWidth + gap) / (itemSize + gap)).floor();
                final crossAxisCount = rawCount.clamp(3, 8);

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: categoryIconOptions.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: gap,
                    crossAxisSpacing: gap,
                    mainAxisExtent: itemSize,
                  ),
                  itemBuilder: (context, index) {
                    final option = categoryIconOptions[index];
                    final selected = _iconKey == option.key;
                    return Tooltip(
                      message: option.label,
                      child: Material(
                        color: selected
                            ? selectedCategoryColor.withValues(alpha: 0.16)
                            : AppColors.surfaceColor(context),
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setState(() => _iconKey = option.key),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? selectedCategoryColor
                                    : AppColors.borderColor(context),
                                width: selected ? 2 : 1,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              option.icon,
                              size: 20,
                              color: selected
                                  ? selectedCategoryColor
                                  : AppColors.textSecondary(context),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),

            // Delete button
            if (canDelete) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  // icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Delete category'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.red,
                    side: const BorderSide(color: AppColors.red),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _handleDelete,
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.sentences,
      maxLines: maxLines,
      style: TextStyle(color: AppColors.textPrimary(context)),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: AppColors.textSecondary(context)),
        hintStyle: TextStyle(color: AppColors.textTertiary(context)),
        filled: true,
        fillColor: AppColors.surfaceColor(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderColor(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderColor(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.primaryLight,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _buildLabel(BuildContext context, String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
        color: AppColors.textTertiary(context),
      ),
    );
  }
}

// ── Flow Tab ────────────────────────────────────────────────────────────────
class _FlowTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FlowTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.cardColor(context) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected
                  ? AppColors.textPrimary(context)
                  : AppColors.textSecondary(context),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Type Option ─────────────────────────────────────────────────────────────
class _TypeOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _TypeOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: selected
          ? AppColors.primaryLight.withValues(alpha: 0.08)
          : AppColors.surfaceColor(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.primaryLight
                  : AppColors.borderColor(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? AppColors.primaryLight
                        : AppColors.textTertiary(context),
                    width: 2,
                  ),
                  color: selected ? AppColors.primaryLight : Colors.transparent,
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: AppColors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
