import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/localization/app_localizations.dart';

/// Screen for uploading a tutorial video with metadata and optional tools list.
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
  bool isUploading = false;
  double uploadProgress = 0.0;

  final List<String> codes = [
    'P0420',
    'P0301',
    'P0171',
    'C1201',
    'U0100',
    'Other',
  ];
  final List<String> difficulties = [
    'Beginner',
    'Intermediate',
    'Advanced',
  ];
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
            colors: [
              AppColors.backgroundDark,
              AppColors.backgroundDarkBlue,
            ],
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
            'Upload Tutorial',
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

  Widget _buildVideoUploadSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Video File'),
        GestureDetector(
          onTap: () {
            // Pick video file
          },
          child: Container(
            height: 180.h,
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: AppColors.accentCyan.withValues(alpha: 0.3),
                width: 2,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_upload,
                  size: 60.r,
                  color: AppColors.accentCyan.withValues(alpha: 0.7),
                ),
                SizedBox(height: 15.h),
                Text(
                  'Tap to select video',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentCyan,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'Max 500MB • MP4, MOV, AVI',
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColors.textLight.withValues(alpha: 0.6),
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
        _buildSectionTitle('Thumbnail'),
        GestureDetector(
          onTap: () {
            // Pick thumbnail
          },
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
                Text(
                  'Select thumbnail image',
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentCyan,
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
        _buildSectionTitle('Title'),
        TextFormField(
          controller: _titleController,
          style: const TextStyle(color: AppColors.textLight),
          decoration: InputDecoration(
            hintText: 'Enter tutorial title...',
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
              return 'Please enter a title';
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
        _buildSectionTitle('Description'),
        TextFormField(
          controller: _descriptionController,
          style: const TextStyle(color: AppColors.textLight),
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'Describe what viewers will learn...',
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
              return 'Please enter a description';
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
        _buildSectionTitle('Related Code'),
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
                padding: EdgeInsets.symmetric(
                  horizontal: 16.w,
                  vertical: 10.h,
                ),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [
                            AppColors.accentCyan,
                            AppColors.accentOrange,
                          ],
                        )
                      : null,
                  color: isSelected ? null : AppColors.white.withValues(alpha: 0.05),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.transparent
                        : AppColors.accentCyan.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Text(
                  code,
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? AppColors.white
                        : AppColors.accentCyan,
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
        _buildSectionTitle('Difficulty Level'),
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
                  margin: EdgeInsets.only(right: 10.w),
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
                    color: isSelected ? null : AppColors.white.withValues(alpha: 0.05),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.transparent
                          : AppColors.accentCyan.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Center(
                    child: Text(
                      difficulty,
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
        _buildSectionTitle('Estimated Cost'),
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
                    cost,
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
        _buildSectionTitle('Tools & Parts (Optional)'),
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
                'Add tools and parts list',
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
        onPressed: isUploading ? null : _handleUpload,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.transparent,
          shadowColor: AppColors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15.r),
          ),
        ),
        child: isUploading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20.w,
                    height: 20.h,
                    child: const CircularProgressIndicator(
                      color: AppColors.white,
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(width: 15.w),
                  Text(
                    '${(uploadProgress * 100).toInt()}% Uploading...',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.white,
                    ),
                  ),
                ],
              )
            : Text(
                'PUBLISH TUTORIAL',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: AppColors.white,
                ),
              ),
      ),
    );
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
    if (_formKey.currentState!.validate()) {
      setState(() {
        isUploading = true;
      });

      Future.delayed(const Duration(seconds: 1), () {
        if (!mounted) return;
        setState(() {
          uploadProgress = 0.3;
        });
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() {
          uploadProgress = 0.6;
        });
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() {
          uploadProgress = 1.0;
        });

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.surfaceDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20.r),
            ),
            title: const Text(
              'Success!',
              style: TextStyle(color: AppColors.textLight),
            ),
            content: const Text(
              'Your tutorial has been uploaded successfully!',
              style: TextStyle(color: AppColors.textLight),
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentCyan,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                ),
                child: Text(context.tr('done')),
              ),
            ],
          ),
        );
      });
    }
  }
}
