import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/core.dart';
import '../../../../../core/localization/app_localizations.dart';

/// Screen for uploading a tutorial video with metadata and optional tools list.
///
/// There is no tutorial backend (no upload or catalogue endpoint), so the
/// form validates — including that a video was actually picked — but
/// publishing tells the user it is not available yet instead of faking an
/// upload.
class UploadVideoScreen extends StatefulWidget {
  const UploadVideoScreen({super.key});

  @override
  State<UploadVideoScreen> createState() => _UploadVideoScreenState();
}

class _UploadVideoScreenState extends State<UploadVideoScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  String selectedCode = 'P0420';
  String selectedDifficulty = 'Intermediate';
  String selectedCost = 'Low (\$0-\$100)';

  final ImagePicker _picker = ImagePicker();
  XFile? _video;
  XFile? _thumbnail;

  /// Set when publish was attempted without a video, to flag the picker.
  bool _videoMissing = false;

  final List<String> codes = [
    'P0420',
    'P0301',
    'P0171',
    'C1201',
    'U0100',
    'Other',
  ];
  final List<String> difficulties = ['Beginner', 'Intermediate', 'Advanced'];
  final List<String> costRanges = [
    'Free',
    'Low (\$0-\$100)',
    'Medium (\$100-\$500)',
    'High (\$500+)',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(title: context.tr('upload_tutorial'), close: true),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSizes.space20.w,
                  AppSizes.space4.h,
                  AppSizes.space20.w,
                  AppSizes.space24.h,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildUnavailableNotice(),
                      SizedBox(height: AppSizes.space24.h),
                      _buildVideoUploadSection(),
                      SizedBox(height: AppSizes.space20.h),
                      _buildThumbnailSection(),
                      SizedBox(height: AppSizes.space20.h),
                      _buildTitleField(),
                      SizedBox(height: AppSizes.space20.h),
                      _buildDescriptionField(),
                      SizedBox(height: AppSizes.space20.h),
                      _buildCodeSelector(),
                      SizedBox(height: AppSizes.space20.h),
                      _buildDifficultySelector(),
                      SizedBox(height: AppSizes.space20.h),
                      _buildCostSelector(),
                      SizedBox(height: AppSizes.space20.h),
                      _buildToolsSection(),
                      SizedBox(height: AppSizes.space32.h),
                      AppButton(
                        label: context.tr('publish_tutorial'),
                        icon: Icons.publish_rounded,
                        onPressed: _handleUpload,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnavailableNotice() {
    final p = context.colors;
    return AppCard(
      accent: p.primary,
      padding: EdgeInsets.all(AppSizes.space12.r),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: p.primary,
            size: AppSizes.iconSm.r,
          ),
          SizedBox(width: AppSizes.space12.w),
          Expanded(
            child: Text(
              context.tr('tutorial_upload_unavailable'),
              style: AppTextStyles.label.copyWith(
                fontWeight: FontWeight.w400,
                color: p.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickVideo() async {
    final file = await _pick(
      () => _picker.pickVideo(source: ImageSource.gallery),
    );
    if (file == null || !mounted) return;
    setState(() {
      _video = file;
      _videoMissing = false;
    });
  }

  Future<void> _pickThumbnail() async {
    final file = await _pick(
      () => _picker.pickImage(source: ImageSource.gallery, maxWidth: 1280),
    );
    if (file == null || !mounted) return;
    setState(() => _thumbnail = file);
  }

  /// Runs a picker call; null when cancelled or when the picker failed
  /// (permission denied, plugin unavailable — reported in a snackbar).
  Future<XFile?> _pick(Future<XFile?> Function() pick) async {
    try {
      return await pick();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('media_pick_failed'))),
        );
      }
      return null;
    }
  }

  Widget _buildVideoUploadSection() {
    final p = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldLabel(context.tr('video_file')),
        // Outlined in the critical color while "video required" is shown.
        AppCard(
          onTap: _pickVideo,
          accent: _videoMissing ? p.crit : null,
          accentStyle: AppCardAccent.outline,
          padding: EdgeInsets.symmetric(
            horizontal: AppSizes.space16.w,
            vertical: AppSizes.space24.h,
          ),
          child: Column(
            children: [
              IconBox(
                _video == null
                    ? Icons.cloud_upload_outlined
                    : Icons.movie_outlined,
                size: 52,
              ),
              SizedBox(height: AppSizes.space12.h),
              Text(
                _video?.name ?? context.tr('tap_select_video'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: _video == null ? p.primary : p.text,
                ),
              ),
              SizedBox(height: AppSizes.space4.h),
              Text(
                _videoMissing
                    ? context.tr('video_required')
                    : context.tr('video_constraints'),
                textAlign: TextAlign.center,
                style: AppTextStyles.label.copyWith(
                  fontWeight: FontWeight.w400,
                  color: _videoMissing ? p.crit : p.text2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThumbnailSection() {
    final p = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldLabel(context.tr('thumbnail')),
        AppCard(
          onTap: _pickThumbnail,
          padding: EdgeInsets.all(AppSizes.space12.r),
          child: Row(
            children: [
              const IconBox(Icons.image_outlined),
              SizedBox(width: AppSizes.space12.w),
              Expanded(
                child: Text(
                  _thumbnail?.name ?? context.tr('select_thumbnail'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w500,
                    color: _thumbnail == null ? p.primary : p.text,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: p.muted, size: 22.r),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTitleField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldLabel(context.tr('tutorial_title_label')),
        TextFormField(
          controller: _titleController,
          style: AppTextStyles.body,
          decoration: InputDecoration(
            hintText: context.tr('tutorial_title_hint'),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return context.tr('tutorial_title_required');
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildDescriptionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldLabel(context.tr('description_label')),
        TextFormField(
          controller: _descriptionController,
          style: AppTextStyles.body,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: context.tr('tutorial_desc_hint'),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return context.tr('tutorial_desc_required');
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildCodeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldLabel(context.tr('related_code')),
        Wrap(
          spacing: AppSizes.space8.w,
          runSpacing: AppSizes.space8.h,
          children: [
            // IntrinsicWidth: AppFilterChip fills the width it is given.
            for (final code in codes)
              IntrinsicWidth(
                child: AppFilterChip(
                  label: code == 'Other' ? context.tr('code_other') : code,
                  selected: selectedCode == code,
                  onTap: () => setState(() => selectedCode = code),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDifficultySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldLabel(context.tr('difficulty_level')),
        AppSegmentedControl<String>(
          segments: [
            for (final d in difficulties)
              (d, context.tr('difficulty_${d.toLowerCase()}')),
          ],
          value: selectedDifficulty,
          onChanged: (d) => setState(() => selectedDifficulty = d),
        ),
      ],
    );
  }

  Widget _buildCostSelector() {
    final p = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldLabel(context.tr('estimated_cost')),
        SettingsGroup(
          children: [
            for (final cost in costRanges)
              Semantics(
                inMutuallyExclusiveGroup: true,
                checked: selectedCost == cost,
                child: SettingsTile(
                  leading: Icon(
                    selectedCost == cost
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selectedCost == cost ? p.primary : p.muted,
                    size: 22.r,
                  ),
                  title: _costLabel(cost),
                  trailing: const SizedBox.shrink(),
                  onTap: () => setState(() => selectedCost = cost),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildToolsSection() {
    final p = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldLabel(context.tr('tools_parts_optional')),
        AppCard(
          padding: EdgeInsets.all(AppSizes.space12.r),
          child: Row(
            children: [
              const IconBox(Icons.add_rounded),
              SizedBox(width: AppSizes.space12.w),
              Expanded(
                child: Text(
                  context.tr('add_tools_list'),
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w500,
                    color: p.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _costLabel(String cost) {
    switch (costRanges.indexOf(cost)) {
      case 0:
        return context.tr('cost_free');
      case 1:
        return context.tr('cost_low');
      case 2:
        return context.tr('cost_medium');
      case 3:
        return context.tr('cost_high');
      default:
        return cost;
    }
  }

  /// Label above a form field ("Title", "Difficulty Level").
  Widget _buildFieldLabel(String title) {
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: AppSizes.space4.w,
        bottom: AppSizes.space8.h,
      ),
      child: Text(
        title,
        style: AppTextStyles.label.copyWith(
          fontWeight: FontWeight.w600,
          color: context.colors.text,
        ),
      ),
    );
  }

  void _handleUpload() {
    final formValid = _formKey.currentState!.validate();
    setState(() => _videoMissing = _video == null);
    if (!formValid || _video == null) return;

    // Nothing to upload to: say so instead of simulating a publish.
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('tutorial_upload_unavailable_title')),
        content: Text(context.tr('tutorial_upload_unavailable')),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('ok')),
          ),
        ],
      ),
    );
  }
}
