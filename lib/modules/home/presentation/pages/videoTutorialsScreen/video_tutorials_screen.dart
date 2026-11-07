import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/core.dart';
import '../../../../../core/localization/app_localizations.dart';

class VideoTutorialsScreen extends StatefulWidget {
  const VideoTutorialsScreen({super.key});

  @override
  State<VideoTutorialsScreen> createState() => _VideoTutorialsScreenState();
}

class _VideoTutorialsScreenState extends State<VideoTutorialsScreen> {
  String selectedFilter = 'All';
  String selectedDifficulty = 'All';
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// Built-in SAMPLE catalogue: there is no tutorial backend (no endpoint
  /// lists or serves videos), so these entries are placeholders and the
  /// screen labels them as such. Titles/costs are localization keys; the
  /// view/rating figures are illustrative only. `icon` is the thumbnail
  /// placeholder (also shown by the player).
  late List<Map<String, dynamic>> _tutorials;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _tutorials = [
      {
        'id': '1',
        'titleKey': 'tut_title_o2_sensor',
        'code': 'P0420',
        'duration': '15 min',
        'difficulty': 'Intermediate',
        'views': '125K',
        'rating': 4.8,
        'icon': Icons.sensors_rounded,
        'costKey': 'cost_low',
        'bookmarked': false,
      },
      {
        'id': '2',
        'titleKey': 'tut_title_misfire',
        'code': 'P0301',
        'duration': '22 min',
        'difficulty': 'Advanced',
        'views': '89K',
        'rating': 4.9,
        'icon': Icons.bolt_rounded,
        'costKey': 'cost_medium',
        'bookmarked': true,
      },
      {
        'id': '3',
        'titleKey': 'tut_title_check_engine',
        'code': 'General',
        'duration': '8 min',
        'difficulty': 'Beginner',
        'views': '250K',
        'rating': 4.7,
        'icon': Icons.lightbulb_outline_rounded,
        'costKey': 'cost_free',
        'bookmarked': false,
      },
      {
        'id': '4',
        'titleKey': 'tut_title_abs',
        'code': 'C1201',
        'duration': '18 min',
        'difficulty': 'Intermediate',
        'views': '67K',
        'rating': 4.6,
        'icon': Icons.tire_repair_rounded,
        'costKey': 'cost_medium',
        'bookmarked': false,
      },
      {
        'id': '5',
        'titleKey': 'tut_title_maf',
        'code': 'P0100',
        'duration': '10 min',
        'difficulty': 'Beginner',
        'views': '180K',
        'rating': 4.9,
        'icon': Icons.air_rounded,
        'costKey': 'cost_low',
        'bookmarked': true,
      },
    ];
  }

  String _title(Map<String, dynamic> t) => context.tr(t['titleKey'] as String);

  List<Map<String, dynamic>> get filteredTutorials {
    final query = _query.trim().toLowerCase();
    return _tutorials.where((tutorial) {
      final matchesFilter =
          selectedFilter == 'All' ||
          tutorial['code'].toString().contains(selectedFilter);
      final matchesDifficulty =
          selectedDifficulty == 'All' ||
          tutorial['difficulty'] == selectedDifficulty;
      final matchesQuery =
          query.isEmpty ||
          _title(tutorial).toLowerCase().contains(query) ||
          tutorial['code'].toString().toLowerCase().contains(query);
      return matchesFilter && matchesDifficulty && matchesQuery;
    }).toList();
  }

  /// Route arguments for the player: the entry with its display strings
  /// resolved for the current locale.
  Map<String, dynamic> _playerArgs(Map<String, dynamic> t) => {
    ...t,
    'title': _title(t),
    if (t['code'] == 'General') 'code': context.tr('tutorial_filter_general'),
    'instructor': context.tr('tutorial_sample_author'),
    'uploadedBy': context.tr('tutorial_sample_badge'),
    'cost': context.tr(t['costKey'] as String),
    'duration': _durationLabel(t['duration'] as String?),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: context.tr('video_tutorials'),
              actions: [
                HeaderAction(
                  icon: Icons.bookmarks_outlined,
                  tooltip: context.tr('saved_tutorials'),
                  onPressed: () {},
                ),
              ],
            ),
            _buildSearchBar(),
            SizedBox(height: AppSizes.space12.h),
            _buildFilterChips(),
            _buildSampleNotice(),
            Expanded(child: _buildTutorialsList()),
          ],
        ),
      ),
      floatingActionButton: _buildUploadButton(),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSizes.space20.w),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _query = v),
        style: AppTextStyles.body,
        decoration: InputDecoration(
          hintText: context.tr('search_tutorials'),
          prefixIcon: const Icon(Icons.search_rounded),
        ),
      ),
    );
  }

  Widget _buildSampleNotice() {
    final p = context.colors;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSizes.space20.w,
        AppSizes.space8.h,
        AppSizes.space20.w,
        0,
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16.r, color: p.muted),
          SizedBox(width: AppSizes.space8.w),
          Expanded(
            child: Text(
              context.tr('tutorial_sample_notice'),
              style: AppTextStyles.label.copyWith(
                fontWeight: FontWeight.w400,
                color: p.text2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Two rows of filter pills: DTC code (row 0) and difficulty (row 1).
  Widget _buildFilterChips() {
    Widget row(List<Widget> chips) => SizedBox(
      height: 44.h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.space20.w,
          vertical: AppSizes.space4.h,
        ),
        itemCount: chips.length,
        separatorBuilder: (_, _) => SizedBox(width: AppSizes.space8.w),
        itemBuilder: (_, i) => chips[i],
      ),
    );

    Widget codeChip(String value, String label) => AppFilterChip(
      label: label,
      selected: selectedFilter == value,
      onTap: () => setState(() => selectedFilter = value),
    );

    Widget levelChip(String value, String label) => AppFilterChip(
      label: label,
      selected: selectedDifficulty == value,
      onTap: () => setState(() => selectedDifficulty = value),
    );

    return Column(
      children: [
        row([
          codeChip('All', context.tr('all')),
          codeChip('P0420', 'P0420'),
          codeChip('P0301', 'P0301'),
          codeChip('General', context.tr('tutorial_filter_general')),
        ]),
        row([
          levelChip('All', context.tr('all_levels')),
          for (final d in const ['Beginner', 'Intermediate', 'Advanced'])
            levelChip(d, _difficultyLabel(d)),
        ]),
      ],
    );
  }

  Widget _buildTutorialsList() {
    final filtered = filteredTutorials;

    if (filtered.isEmpty) {
      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(vertical: AppSizes.space32.h),
        child: EmptyState(
          icon: Icons.video_library_outlined,
          title: context.tr('no_tutorials_found'),
        ),
      );
    }

    return ListView.separated(
      // Bottom inset keeps the last card clear of the Upload button.
      padding: EdgeInsets.fromLTRB(
        AppSizes.space20.w,
        AppSizes.space16.h,
        AppSizes.space20.w,
        96.h,
      ),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => SizedBox(height: AppSizes.space12.h),
      itemBuilder: (context, index) => _buildTutorialCard(filtered[index]),
    );
  }

  Widget _buildTutorialCard(Map<String, dynamic> tutorial) {
    final p = context.colors;
    final difficulty = tutorial['difficulty'] as String? ?? '';
    final bookmarked = tutorial['bookmarked'] as bool? ?? false;
    final code = tutorial['code'] == 'General'
        ? context.tr('tutorial_filter_general')
        : tutorial['code'] as String? ?? '—';
    final metaStyle = AppTextStyles.label.copyWith(
      fontWeight: FontWeight.w400,
      color: p.text2,
    );
    Widget dot() => Padding(
      padding: EdgeInsets.symmetric(horizontal: 6.w),
      child: Text('·', style: metaStyle.copyWith(color: p.muted)),
    );

    return AppCard(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSizes.space12.r,
        AppSizes.space12.r,
        AppSizes.space4.r,
        AppSizes.space12.r,
      ),
      onTap: () {
        Navigator.pushNamed(
          context,
          AppRoutes.videoPlayer,
          arguments: _playerArgs(tutorial),
        );
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Thumbnail(
            icon:
                tutorial['icon'] as IconData? ??
                Icons.play_circle_outline_rounded,
          ),
          SizedBox(width: AppSizes.space12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _CodePill(code),
                    SizedBox(width: AppSizes.space8.w),
                    Flexible(
                      child: Text(
                        context.tr(tutorial['costKey'] as String),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(color: p.muted),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6.h),
                Text(
                  _title(tutorial),
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: AppSizes.space4.h),
                // duration · difficulty · rating
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _durationLabel(tutorial['duration'] as String?),
                      style: AppTextStyles.numeric(metaStyle),
                    ),
                    dot(),
                    Text(_difficultyLabel(difficulty), style: metaStyle),
                    dot(),
                    Icon(Icons.star_rounded, size: 14.r, color: p.text2),
                    SizedBox(width: 2.w),
                    Text(
                      (tutorial['rating'] ?? '—').toString(),
                      style: AppTextStyles.numeric(metaStyle),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.tr('save'),
            isSelected: bookmarked,
            onPressed: () {
              setState(() => tutorial['bookmarked'] = !bookmarked);
            },
            icon: Icon(
              bookmarked
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              color: bookmarked ? p.primary : p.muted,
              size: 22.r,
            ),
          ),
        ],
      ),
    );
  }

  String _difficultyLabel(String difficulty) {
    switch (difficulty) {
      case 'Beginner':
        return context.tr('difficulty_beginner');
      case 'Intermediate':
        return context.tr('difficulty_intermediate');
      case 'Advanced':
        return context.tr('difficulty_advanced');
      default:
        return difficulty;
    }
  }

  /// Localizes mock durations such as "15 min".
  String _durationLabel(String? duration) {
    if (duration == null) return '—';
    final m = RegExp(r'^(\d+) min$').firstMatch(duration);
    return m == null
        ? duration
        : context.tr('minutes_n').replaceAll('{n}', m.group(1)!);
  }

  Widget _buildUploadButton() {
    return FloatingActionButton.extended(
      onPressed: () {
        Navigator.pushNamed(context, AppRoutes.uploadVideo);
      },
      icon: const Icon(Icons.upload_rounded),
      label: Text(
        context.tr('upload'),
        style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Thumbnail placeholder: the tutorial's icon on a neutral tile (the sample
/// catalogue has no real thumbnails).
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return ExcludeSemantics(
      child: Container(
        width: 72.r,
        height: 72.r,
        decoration: BoxDecoration(
          color: p.surface2,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd.r),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 30.r, color: p.text2),
      ),
    );
  }
}

/// Small DTC code label ("P0420", "General").
class _CodePill extends StatelessWidget {
  const _CodePill(this.code);

  final String code;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.space8.w,
        vertical: 2.h,
      ),
      decoration: BoxDecoration(
        color: p.primarySoft,
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Text(
        code,
        style: AppTextStyles.numeric(
          AppTextStyles.caption,
        ).copyWith(color: p.primary, fontWeight: FontWeight.w600),
      ),
    );
  }
}
