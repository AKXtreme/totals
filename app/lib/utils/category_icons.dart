import 'package:flutter/material.dart';

class CategoryIconOption {
  final String key;
  final IconData icon;
  final String label;

  const CategoryIconOption({
    required this.key,
    required this.icon,
    required this.label,
  });
}

const List<CategoryIconOption> categoryIconOptions = [
  CategoryIconOption(
    key: 'payments',
    icon: Icons.payments_rounded,
    label: 'Salary',
  ),
  CategoryIconOption(
    key: 'gift',
    icon: Icons.card_giftcard_rounded,
    label: 'Gifts',
  ),
  CategoryIconOption(key: 'home', icon: Icons.home_rounded, label: 'Rent'),
  CategoryIconOption(
    key: 'bolt',
    icon: Icons.bolt_rounded,
    label: 'Utilities',
  ),
  CategoryIconOption(
    key: 'shopping_cart',
    icon: Icons.shopping_cart_rounded,
    label: 'Groceries',
  ),
  CategoryIconOption(
    key: 'directions_car',
    icon: Icons.directions_car_rounded,
    label: 'Transport',
  ),
  CategoryIconOption(
    key: 'restaurant',
    icon: Icons.restaurant_rounded,
    label: 'Eating out',
  ),
  CategoryIconOption(
    key: 'checkroom',
    icon: Icons.checkroom_rounded,
    label: 'Clothing',
  ),
  CategoryIconOption(
    key: 'health',
    icon: Icons.health_and_safety_rounded,
    label: 'Health',
  ),
  CategoryIconOption(
    key: 'phone',
    icon: Icons.phone_android_rounded,
    label: 'Airtime',
  ),
  CategoryIconOption(
    key: 'request_quote',
    icon: Icons.request_quote_rounded,
    label: 'Loan',
  ),
  CategoryIconOption(key: 'spa', icon: Icons.spa_rounded, label: 'Beauty'),
  CategoryIconOption(
    key: 'savings',
    icon: Icons.savings_rounded,
    label: 'Savings',
  ),
  CategoryIconOption(
    key: 'flight',
    icon: Icons.flight_rounded,
    label: 'Travel',
  ),
  CategoryIconOption(
    key: 'school',
    icon: Icons.school_rounded,
    label: 'Education',
  ),
  CategoryIconOption(
    key: 'sports_esports',
    icon: Icons.sports_esports_rounded,
    label: 'Gaming',
  ),
  CategoryIconOption(key: 'pets', icon: Icons.pets_rounded, label: 'Pets'),
  CategoryIconOption(
    key: 'movie',
    icon: Icons.movie_rounded,
    label: 'Entertainment',
  ),
  CategoryIconOption(
    key: 'fitness_center',
    icon: Icons.fitness_center_rounded,
    label: 'Fitness',
  ),
  CategoryIconOption(
    key: 'medical_services',
    icon: Icons.medical_services_rounded,
    label: 'Medical',
  ),
  CategoryIconOption(
    key: 'local_gas_station',
    icon: Icons.local_gas_station_rounded,
    label: 'Fuel',
  ),
  CategoryIconOption(
    key: 'celebration',
    icon: Icons.celebration_rounded,
    label: 'Celebration',
  ),
  CategoryIconOption(
    key: 'subscriptions',
    icon: Icons.subscriptions_rounded,
    label: 'Subscriptions',
  ),
  CategoryIconOption(
    key: 'more_horiz',
    icon: Icons.more_horiz_rounded,
    label: 'Misc',
  ),
];

final Map<String, IconData> _categoryIconDataByKey =
    Map<String, IconData>.unmodifiable({
  for (final option in categoryIconOptions) option.key: option.icon,
});

final Set<String> categoryIconKeys =
    Set<String>.unmodifiable(_categoryIconDataByKey.keys);

IconData iconForCategoryKey(String? iconKey) {
  return _categoryIconDataByKey[iconKey] ?? Icons.category_rounded;
}
