import 'package:flutter/material.dart';
import 'package:bean_budget/core/theme/app_theme.dart';

/// A grid of predefined colors for category selection.
class ColorPickerGrid extends StatelessWidget {
  final int selectedColor;
  final ValueChanged<int> onColorSelected;

  const ColorPickerGrid({
    super.key,
    required this.selectedColor,
    required this.onColorSelected,
  });

  // 9 main colors across the spectrum
  static const List<MaterialColor> _baseColors = [
    Colors.red,
    Colors.deepOrange,
    Colors.orange,
    Colors.amber,
    Colors.green,
    Colors.teal,
    Colors.blue,
    Colors.indigo,
    Colors.purple,
  ];

  // 1 Main color (500) + 5 tints/shades
  static const List<int> _shadeIndices = [50, 100, 300, 500, 700, 900];

  static final List<int> presetColors = () {
    final List<int> colors = [];
    // Row-major order: iterate shades first, so each column represents a single hue
    for (int shade in _shadeIndices) {
      for (MaterialColor color in _baseColors) {
        colors.add(color[shade]!.value);
      }
    }
    return colors;
  }();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 9,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: presetColors.length,
      itemBuilder: (context, index) {
        final color = presetColors[index];
        final isSelected = color == selectedColor;
        
        return GestureDetector(
          onTap: () => onColorSelected(color),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: Color(color),
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(color: Colors.white, width: 2.5)
                  : Border.all(color: Colors.transparent, width: 2.5),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Color(color).withAlpha(100),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                : null,
          ),
        );
      },
    );
  }
}

/// A grid of predefined icons for category selection.
class IconPickerGrid extends StatelessWidget {
  final String selectedIcon;
  final ValueChanged<String> onIconSelected;

  const IconPickerGrid({
    super.key,
    required this.selectedIcon,
    required this.onIconSelected,
  });

  static const Map<String, IconData> presetIcons = {
    // Housing / Utilities
    'home': Icons.home_rounded,
    'apartment': Icons.apartment_rounded,
    'water_drop': Icons.water_drop_rounded,
    'flash_on': Icons.flash_on_rounded,
    'wifi': Icons.wifi_rounded,
    'phone': Icons.phone_rounded,
    'cleaning': Icons.cleaning_services_rounded,
    
    // Transport
    'directions_car': Icons.directions_car_rounded,
    'local_gas_station': Icons.local_gas_station_rounded,
    'transit': Icons.directions_transit_rounded,
    'flight': Icons.flight_rounded,
    'local_taxi': Icons.local_taxi_rounded,
    'two_wheeler': Icons.two_wheeler_rounded,
    'commute': Icons.commute_rounded,

    // Food & Dining
    'restaurant': Icons.restaurant_rounded,
    'local_cafe': Icons.local_cafe_rounded,
    'fastfood': Icons.fastfood_rounded,
    'shopping_cart': Icons.shopping_cart_rounded,
    'grocery': Icons.local_grocery_store_rounded,
    'liquor': Icons.liquor_rounded,
    'bakery': Icons.bakery_dining_rounded,

    // Health & Wellness
    'health': Icons.health_and_safety_rounded,
    'hospital': Icons.local_hospital_rounded,
    'medical': Icons.medical_services_rounded,
    'favorite': Icons.favorite_rounded,
    'healing': Icons.healing_rounded,
    'fitness_center': Icons.fitness_center_rounded,
    'psychology': Icons.psychology_rounded,
    'medication': Icons.medication_rounded,

    // Entertainment & Leisure
    'movie': Icons.movie_rounded,
    'sports_esports': Icons.sports_esports_rounded,
    'sports_soccer': Icons.sports_soccer_rounded,
    'music_note': Icons.music_note_rounded,
    'ticket': Icons.confirmation_number_rounded,
    'casino': Icons.casino_rounded,
    'attractions': Icons.attractions_rounded,
    'palette': Icons.palette_rounded,
    'book': Icons.menu_book_rounded,

    // Shopping & Retail
    'shopping_bag': Icons.shopping_bag_rounded,
    'checkroom': Icons.checkroom_rounded,
    'storefront': Icons.storefront_rounded,
    'devices': Icons.devices_rounded,
    'diamond': Icons.diamond_rounded,

    // Finance & Admin
    'account_balance': Icons.account_balance_rounded,
    'credit_card': Icons.credit_card_rounded,
    'savings': Icons.savings_rounded,
    'attach_money': Icons.attach_money_rounded,
    'receipt': Icons.receipt_long_rounded,
    'description': Icons.description_rounded,
    'wallet': Icons.account_balance_wallet_rounded,
    'subscriptions': Icons.subscriptions_rounded,

    // Kids, Pets & Education
    'child_care': Icons.child_care_rounded,
    'stroller': Icons.stroller_rounded,
    'pets': Icons.pets_rounded,
    'school': Icons.school_rounded,

    // Personal & Misc
    'content_cut': Icons.content_cut_rounded,
    'spa': Icons.spa_rounded,
    'card_giftcard': Icons.card_giftcard_rounded,
    'work': Icons.work_rounded,
    'build': Icons.build_rounded,
    'shield': Icons.shield_rounded,
    'explore': Icons.explore_rounded,
    'category': Icons.category_rounded,
    'label': Icons.label_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: presetIcons.entries.map((entry) {
        final isSelected = entry.key == selectedIcon;
        return GestureDetector(
          onTap: () => onIconSelected(entry.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withAlpha(30)
                  : AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.border,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Icon(
              entry.value,
              size: 20,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Resolve an icon name string to an IconData.
  static IconData resolveIcon(String name) {
    return presetIcons[name] ?? Icons.category_rounded;
  }
}
