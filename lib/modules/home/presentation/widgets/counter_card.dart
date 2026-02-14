import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/constants.dart';
import '../../../../core/utils/app_extensions.dart';
import '../../bloc/counter/counter_bloc.dart';

/// Card widget that displays the counter and increment/decrement actions.
class CounterCard extends StatelessWidget {
  const CounterCard({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppStrings.counterLabel,
              style: textTheme.titleMedium?.copyWith(
                color: context.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSizes.space12),
            Text(
              AppStrings.counterHint,
              style: textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSizes.space16),
            BlocBuilder<CounterBloc, CounterState>(
              builder: (context, state) {
                return Text(
                  '${state.count}',
                  style: textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: context.colorScheme.primary,
                  ),
                );
              },
            ),
            const SizedBox(height: AppSizes.space24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => context.read<CounterBloc>().add(
                        const CounterDecrementPressed(),
                      ),
                  icon: const Icon(Icons.remove, size: AppSizes.iconSm),
                  label: const Text(AppStrings.decrement),
                ),
                const SizedBox(width: AppSizes.space16),
                FilledButton.tonalIcon(
                  onPressed: () => context.read<CounterBloc>().add(
                        const CounterIncrementPressed(),
                      ),
                  icon: const Icon(Icons.add, size: AppSizes.iconSm),
                  label: const Text(AppStrings.increment),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
