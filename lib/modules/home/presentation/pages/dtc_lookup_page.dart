import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/core.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/services/dtc_repository.dart';

class DtcLookupPage extends StatefulWidget {
  const DtcLookupPage({super.key});

  @override
  State<DtcLookupPage> createState() => _DtcLookupPageState();
}

class _DtcLookupPageState extends State<DtcLookupPage> {
  final _controller = TextEditingController();
  final _repository = DtcRepository();

  String? _result;
  String? _error;
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() {
        _error = context.tr('dtc_enter_code_error');
        _result = null;
      });
      return;
    }

    // Pre-translate error messages before async gap
    final noDescMsg = '${context.tr('dtc_no_description_prefix')} "$code".';
    final fetchFailedMsg = context.tr('dtc_fetch_failed');

    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    try {
      final languageCode = Localizations.localeOf(context).languageCode;
      final description = await _repository.getDtcDescription(
        code,
        languageCode: languageCode,
      );
      setState(() {
        if (description == null || description.isEmpty) {
          _result = null;
          _error = noDescMsg;
        } else {
          _result = description;
          _error = null;
        }
      });
    } catch (e) {
      setState(() {
        _result = null;
        _error = fetchFailedMsg;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(title: context.tr('dtc_lookup_title')),
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
                    TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.search,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: context.tr('dtc_enter_code_hint'),
                        prefixIcon: const Icon(Icons.search_rounded),
                      ),
                      onSubmitted: (_) => _lookup(),
                    ),
                    SizedBox(height: AppSizes.space16.h),
                    AppButton(
                      label: context.tr('dtc_get_description'),
                      icon: Icons.manage_search_rounded,
                      onPressed: _lookup,
                      isLoading: _isLoading,
                    ),
                    SizedBox(height: AppSizes.space24.h),
                    if (_result != null)
                      AppCard(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const IconBox(Icons.description_outlined),
                            SizedBox(width: AppSizes.space12.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.tr('dtc_description_label'),
                                    style: AppTextStyles.label.copyWith(
                                      color: p.text2,
                                    ),
                                  ),
                                  SizedBox(height: AppSizes.space4.h),
                                  Text(
                                    _result!,
                                    style: AppTextStyles.body.copyWith(
                                      color: p.text,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_error != null)
                      AppCard(
                        accent: p.crit,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 20.r,
                              color: p.crit,
                            ),
                            SizedBox(width: AppSizes.space12.w),
                            Expanded(
                              child: Text(
                                _error!,
                                style: AppTextStyles.body.copyWith(
                                  color: p.text,
                                ),
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
