import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';

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
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildVideoUploadSection(),
                        const SizedBox(height: 25),
                        _buildThumbnailSection(),
                        const SizedBox(height: 25),
                        _buildTitleField(),
                        const SizedBox(height: 20),
                        _buildDescriptionField(),
                        const SizedBox(height: 25),
                        _buildCodeSelector(),
                        const SizedBox(height: 20),
                        _buildDifficultySelector(),
                        const SizedBox(height: 20),
                        _buildCostSelector(),
                        const SizedBox(height: 25),
                        _buildToolsSection(),
                        const SizedBox(height: 30),
                        _buildUploadButton(),
                        const SizedBox(height: 20),
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
      padding: const EdgeInsets.all(20.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.accentCyan),
            onPressed: () => Navigator.pop(context),
          ),
          const Text(
            'Upload Tutorial',
            style: TextStyle(
              fontSize: 24,
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
            height: 180,
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: AppColors.accentCyan.withValues(alpha: 0.3),
                width: 2,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_upload,
                  size: 60,
                  color: AppColors.accentCyan.withValues(alpha: 0.7),
                ),
                const SizedBox(height: 15),
                const Text(
                  'Tap to select video',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentCyan,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Max 500MB • MP4, MOV, AVI',
                  style: TextStyle(
                    fontSize: 13,
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
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: AppColors.accentCyan.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.image,
                  size: 40,
                  color: AppColors.accentCyan.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 15),
                const Text(
                  'Select thumbnail image',
                  style: TextStyle(
                    fontSize: 15,
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
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(
                color: AppColors.accentCyan.withValues(alpha: 0.3),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(
                color: AppColors.accentCyan.withValues(alpha: 0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
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
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(
                color: AppColors.accentCyan.withValues(alpha: 0.3),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(
                color: AppColors.accentCyan.withValues(alpha: 0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
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
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  code,
                  style: TextStyle(
                    fontSize: 13,
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
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(vertical: 12),
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
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      difficulty,
                      style: TextStyle(
                        fontSize: 13,
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
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.accentCyan.withValues(alpha: 0.1)
                    : AppColors.white.withValues(alpha: 0.05),
                border: Border.all(
                  color: isSelected
                      ? AppColors.accentCyan
                      : AppColors.white.withValues(alpha: 0.1),
                ),
                borderRadius: BorderRadius.circular(12),
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
                  const SizedBox(width: 15),
                  Text(
                    cost,
                    style: TextStyle(
                      fontSize: 15,
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
        }).toList(),
      ],
    );
  }

  Widget _buildToolsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Tools & Parts (Optional)'),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.05),
            border: Border.all(
              color: AppColors.accentCyan.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              const Icon(Icons.add_circle_outline, color: AppColors.accentCyan),
              const SizedBox(width: 15),
              const Text(
                'Add tools and parts list',
                style: TextStyle(
                  fontSize: 15,
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
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.accentCyan, AppColors.accentOrange],
        ),
        borderRadius: BorderRadius.circular(15),
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
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        child: isUploading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: AppColors.white,
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Text(
                    '${(uploadProgress * 100).toInt()}% Uploading...',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.white,
                    ),
                  ),
                ],
              )
            : const Text(
                'PUBLISH TUTORIAL',
                style: TextStyle(
                  fontSize: 16,
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
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
              borderRadius: BorderRadius.circular(20),
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
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      });
    }
  }
}
