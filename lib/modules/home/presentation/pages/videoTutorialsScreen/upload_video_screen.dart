import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/constants/app_colors.dart';
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.backgroundDark, AppColors.backgroundDarkBlue],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20.r),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildUnavailableNotice(),
                        SizedBox(height: 20.h),
                        _buildVideoUploadSection(),
                        SizedBox(height: 25.h),
                        _buildThumbnailSection(),
                        SizedBox(height: 25.h),
                        _buildTitleField(),
                        SizedBox(height: 20.h),
                        _buildDescriptionField(),
                        SizedBox(height: 25.h),
                        _buildCodeSelector(),
                        SizedBox(height: 20.h),
                        _buildDifficultySelector(),
                        SizedBox(height: 20.h),
                        _buildCostSelector(),
                        SizedBox(height: 25.h),
                        _buildToolsSection(),
                        SizedBox(height: 30.h),
                        _buildUploadButton(),
                        SizedBox(height: 20.h),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.all(20.r),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.close, color: AppColors.accentCyan, size: 24.r),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            context.tr('upload_tutorial'),
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnavailableNotice() {
    return Container(
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: AppColors.accentOrange.withValues(alpha: 0.1),
        border: Border.all(
          color: AppColors.accentOrange.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.accentOrange, size: 20.r),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              context.tr('tutorial_upload_unavailable'),
              style: TextStyle(fontSize: 13.sp, color: AppColors.textLight),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context.tr('video_file')),
        GestureDetector(
          onTap: _pickVideo,
          child: Container(
            height: 180.h,
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: _videoMissing
                    ? const Color(0xFFFF1744)
                    : AppColors.accentCyan.withValues(alpha: 0.3),
                width: 2,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _video == null ? Icons.cloud_upload : Icons.movie,
                  size: 60.r,
                  color: AppColors.accentCyan.withValues(alpha: 0.7),
                ),
                SizedBox(height: 15.h),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: Text(
                    _video?.name ?? context.tr('tap_select_video'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentCyan,
                    ),
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  _videoMissing
                      ? context.tr('video_required')
                      : context.tr('video_constraints'),
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: _videoMissing
                        ? const Color(0xFFFF1744)
                        : AppColors.textLight.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThumbnailSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context.tr('thumbnail')),
        GestureDetector(
          onTap: _pickThumbnail,
          child: Container(
            height: 120.h,
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: AppColors.accentCyan.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(15.r),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.image,
                  size: 40.r,
                  color: AppColors.accentCyan.withValues(alpha: 0.7),
                ),
                SizedBox(width: 15.w),
                Flexible(
                  child: Text(
                    _thumbnail?.name ?? context.tr('select_thumbnail'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentCyan,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTitleField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context.tr('tutorial_title_label')),
        TextFormField(
          controller: _titleController,
          style: const TextStyle(color: AppColors.textLight),
          decoration: InputDecoration(
            hintText: context.tr('tutorial_title_hint'),
            hintStyle: TextStyle(
              color: AppColors.textLight.withValues(alpha: 0.5),
            ),
            filled: true,
            fillColor: AppColors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15.r),
              borderSide: BorderSide(
                color: AppColors.accentCyan.withValues(alpha: 0.3),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15.r),
              borderSide: BorderSide(
                color: AppColors.accentCyan.withValues(alpha: 0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15.r),
              borderSide: const BorderSide(
                color: AppColors.accentCyan,
                width: 2,
              ),
            ),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context.tr('description_label')),
        TextFormField(
          controller: _descriptionController,
          style: const TextStyle(color: AppColors.textLight),
          maxLines: 5,
          decoration: InputDecoration(
            hintText: context.tr('tutorial_desc_hint'),
            hintStyle: TextStyle(
              color: AppColors.textLight.withValues(alpha: 0.5),
            ),
            filled: true,
            fillColor: AppColors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15.r),
              borderSide: BorderSide(
                color: AppColors.accentCyan.withValues(alpha: 0.3),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15.r),
              borderSide: BorderSide(
                color: AppColors.accentCyan.withValues(alpha: 0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15.r),
              borderSide: const BorderSide(
                color: AppColors.accentCyan,
                width: 2,
              ),
            ),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context.tr('related_code')),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: codes.map((code) {
            final isSelected = selectedCode == code;
            return GestureDetector(
              onTap: () {
                setState(() {
                  selectedCode = code;
                });
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [
                            AppColors.accentCyan,
                            AppColors.accentOrange,
                          ],
                        )
                      : null,
                  color: isSelected
                      ? null
                      : AppColors.white.withValues(alpha: 0.05),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.transparent
                        : AppColors.accentCyan.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Text(
                  code == 'Other' ? context.tr('code_other') : code,
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? AppColors.white : AppColors.accentCyan,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDifficultySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context.tr('difficulty_level')),
        Row(
          children: difficulties.map((difficulty) {
            final isSelected = selectedDifficulty == difficulty;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    selectedDifficulty = difficulty;
                  });
                },
                child: Container(
                  margin: EdgeInsetsDirectional.only(end: 10.w),
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? const LinearGradient(
                            colors: [
                              AppColors.accentCyan,
                              AppColors.accentOrange,
                            ],
                          )
                        : null,
                    color: isSelected
                        ? null
                        : AppColors.white.withValues(alpha: 0.05),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.transparent
                          : AppColors.accentCyan.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Center(
                    child: Text(
                      context.tr('difficulty_${difficulty.toLowerCase()}'),
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? AppColors.white
                            : AppColors.textLight,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCostSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context.tr('estimated_cost')),
        ...costRanges.map((cost) {
          final isSelected = selectedCost == cost;
          return GestureDetector(
            onTap: () {
              setState(() {
                selectedCost = cost;
              });
            },
            child: Container(
              margin: EdgeInsets.only(bottom: 10.h),
              padding: EdgeInsets.all(15.r),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.accentCyan.withValues(alpha: 0.1)
                    : AppColors.white.withValues(alpha: 0.05),
                border: Border.all(
                  color: isSelected
                      ? AppColors.accentCyan
                      : AppColors.white.withValues(alpha: 0.1),
                ),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: isSelected
                        ? AppColors.accentCyan
                        : AppColors.white.withValues(alpha: 0.5),
                  ),
                  SizedBox(width: 15.w),
                  Text(
                    _costLabel(cost),
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppColors.accentCyan
                          : AppColors.textLight,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildToolsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context.tr('tools_parts_optional')),
        Container(
          padding: EdgeInsets.all(15.r),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.05),
            border: Border.all(
              color: AppColors.accentCyan.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(15.r),
          ),
          child: Row(
            children: [
              const Icon(Icons.add_circle_outline, color: AppColors.accentCyan),
              SizedBox(width: 15.w),
              Text(
                context.tr('add_tools_list'),
                style: TextStyle(
                  fontSize: 15.sp,
                  color: AppColors.accentCyan,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUploadButton() {
    return Container(
      width: double.infinity,
      height: 56.h,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.accentCyan, AppColors.accentOrange],
        ),
        borderRadius: BorderRadius.circular(15.r),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentCyan.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _handleUpload,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.transparent,
          shadowColor: AppColors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15.r),
          ),
        ),
        child: Text(
          context.tr('publish_tutorial'),
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: _isArabic ? 0 : 2,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }

  bool get _isArabic => Localizations.localeOf(context).languageCode == 'ar';

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

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16.sp,
          fontWeight: FontWeight.w700,
          color: AppColors.textLight,
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
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        title: Text(
          context.tr('tutorial_upload_unavailable_title'),
          style: const TextStyle(color: AppColors.textLight),
        ),
        content: Text(
          context.tr('tutorial_upload_unavailable'),
          style: const TextStyle(color: AppColors.textLight),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentCyan,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.r),
              ),
            ),
            child: Text(context.tr('ok')),
          ),
        ],
      ),
    );
  }
}
