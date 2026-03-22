import 'package:flutter/material.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/category_icons.dart';

Future<void> showCategorizeTransactionSheet({
  required BuildContext context,
  required TransactionProvider provider,
  required Transaction transaction,
}) async {
  final desiredFlow = transaction.type == 'CREDIT' ? 'income' : 'expense';
  final filtered = provider.categories
      .where((c) => c.flow.toLowerCase() == desiredFlow)
      .toList(growable: false);
  final categories = filtered.isEmpty ? provider.categories : filtered;
  final current = provider.getCategoryById(transaction.categoryId);

  if (categories.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No categories available')),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return _CategorizeSheet(
        provider: provider,
        transaction: transaction,
        categories: categories,
        current: current,
      );
    },
  );
}

class _CategorizeSheet extends StatefulWidget {
  const _CategorizeSheet({
    required this.provider,
    required this.transaction,
    required this.categories,
    required this.current,
  });

  final TransactionProvider provider;
  final Transaction transaction;
  final List<Category> categories;
  final Category? current;

  @override
  State<_CategorizeSheet> createState() => _CategorizeSheetState();
}

class _CategorizeSheetState extends State<_CategorizeSheet> {
  bool _editingNote = false;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _noteController =
        TextEditingController(text: widget.transaction.note ?? '');
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    final note = _noteController.text.trim();
    await widget.provider.updateNoteForTransaction(
      widget.transaction,
      note.isEmpty ? null : note,
    );
    if (mounted) setState(() => _editingNote = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Categorize',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),

            // Note section
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: _editingNote
                  ? Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _noteController,
                            autofocus: true,
                            maxLines: 2,
                            decoration: InputDecoration(
                              hintText: 'Add a note...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check_rounded),
                              color: theme.colorScheme.primary,
                              onPressed: _saveNote,
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() {
                                _noteController.text =
                                    widget.transaction.note ?? '';
                                _editingNote = false;
                              }),
                            ),
                          ],
                        ),
                      ],
                    )
                  : InkWell(
                      onTap: () => setState(() => _editingNote = true),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.note_outlined,
                                size: 16,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.transaction.note?.isNotEmpty == true
                                    ? widget.transaction.note!
                                    : 'Add a note...',
                                style: TextStyle(
                                  color: widget.transaction.note?.isNotEmpty ==
                                          true
                                      ? theme.colorScheme.onSurface
                                      : theme.colorScheme.onSurface
                                          .withValues(alpha: 0.4),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Icon(Icons.edit_outlined,
                                size: 14,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.4)),
                          ],
                        ),
                      ),
                    ),
            ),

            const Divider(height: 16),

            if (widget.current != null)
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('Clear category'),
                onTap: () async {
                  Navigator.pop(context);
                  await widget.provider
                      .clearCategoryForTransaction(widget.transaction);
                },
              ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: ListView.builder(
                itemCount: widget.categories.length,
                itemBuilder: (context, index) {
                  final c = widget.categories[index];
                  final selected = widget.current?.id != null &&
                      c.id == widget.current!.id;

                  return ListTile(
                    leading: Icon(iconForCategoryKey(c.iconKey)),
                    title: Text(c.name),
                    subtitle: Text(c.typeLabel()),
                    trailing:
                        selected ? const Icon(Icons.check_rounded) : null,
                    onTap: () async {
                      if (c.id == null) return;
                      Navigator.pop(context);
                      await widget.provider
                          .setCategoryForTransaction(widget.transaction, c);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
