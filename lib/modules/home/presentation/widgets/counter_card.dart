import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/core.dart';
import '../../bloc/counter/counter_bloc.dart';

/// Card widget that displays the counter and increment/decrement actions.
class CounterCard extends StatelessWidget {
  const CounterCard({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return AppCard(
      padding: EdgeInsets.all(AppSizes.space20.r),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppStrings.counterLabel,
            style: AppTextStyles.title.copyWith(color: p.text),
          ),
          SizedBox(height: AppSizes.space8.h),
          Text(
            AppStrings.counterHint,
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: p.text2),
          ),
          SizedBox(height: AppSizes.space16.h),
          BlocBuilder<CounterBloc, CounterState>(
            builder: (context, state) => Text(
              '${state.count}',
              style: AppTextStyles.display.copyWith(color: p.primary),
            ),
          ),
          SizedBox(height: AppSizes.space20.h),
          Row(
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: AppStrings.decrement,
                  icon: Icons.remove_rounded,
                  compact: true,
                  onPressed: () => context.read<CounterBloc>().add(
                    const CounterDecrementPressed(),
                  ),
                ),
              ),
              SizedBox(width: AppSizes.space12.w),
              Expanded(
                child: AppButton.secondary(
                  label: AppStrings.increment,
                  icon: Icons.add_rounded,
                  compact: true,
                  onPressed: () => context.read<CounterBloc>().add(
                    const CounterIncrementPressed(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
