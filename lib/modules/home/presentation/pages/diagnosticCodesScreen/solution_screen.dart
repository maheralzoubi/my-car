import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/core.dart';
import '../../../../../core/localization/app_localizations.dart';

class SolutionScreen extends StatelessWidget {
  const SolutionScreen({super.key, required this.code});

  final Map<String, dynamic> code;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final title =
        (isArabic ? code['title_ar'] ?? code['title'] : code['title'])
            as String? ??
        context.tr('diagnostic_code_fallback');
    final codeStr = code['code'] as String? ?? '—';

    final p = context.colors;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(title: context.tr('solution')),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsetsDirectional.fromSTEB(
                  AppSizes.space20.w,
                  AppSizes.space8.h,
                  AppSizes.space20.w,
                  AppSizes.space24.h,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppCard(
                      padding: EdgeInsets.all(AppSizes.space20.r),
                      child: Row(
                        children: [
                          const IconBox(Icons.build_outlined, size: 48),
                          SizedBox(width: AppSizes.space12.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  codeStr,
                                  style: AppTextStyles.headline.copyWith(
                                    color: p.text,
                                  ),
                                ),
                                SizedBox(height: AppSizes.space4.h),
                                Text(
                                  title,
                                  style: AppTextStyles.body.copyWith(
                                    color: p.text2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: AppSizes.space24.h),
                    SectionTitle(context.tr('solution_details')),
                    AppCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const IconBox.neutral(Icons.schedule_rounded),
                          SizedBox(width: AppSizes.space12.w),
                          Expanded(
                            child: Text(
                              context
                                  .tr('solution_coming_soon')
                                  .replaceAll('{code}', codeStr),
                              style: AppTextStyles.body.copyWith(color: p.text),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
