import 'package:flutter/material.dart';

import '../../../../core/constants/constants.dart';
import '../widgets/counter_card.dart';
import '../widgets/welcome_header.dart';

/// Home screen: welcome header and counter card.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.homeTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(
            top: AppSizes.space8,
            left: AppSizes.space16,
            right: AppSizes.space16,
            bottom: AppSizes.space24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              WelcomeHeader(),
              SizedBox(height: AppSizes.space24),
              CounterCard(),
            ],
          ),
        ),
      ),
    );
  }
}
