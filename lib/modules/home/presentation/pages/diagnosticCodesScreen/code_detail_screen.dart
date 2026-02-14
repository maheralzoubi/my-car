import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_routes.dart';

class CodeDetailScreen extends StatefulWidget {
  const CodeDetailScreen({super.key, required this.code});

  final Map<String, dynamic> code;

  @override
  State<CodeDetailScreen> createState() => _CodeDetailScreenState();
}

class _CodeDetailScreenState extends State<CodeDetailScreen> {
  final List<String> images = ['🔧', '🔩', '⚙️', '🛠️'];

  static const Color _severityCritical = Color(0xFFFF1744);
  static const Color _severityWarning = Color(0xFFFF6B35);
  static const Color _severityInfo = Color(0xFFFFD600);

  Color getSeverityColor() {
    switch (widget.code['severity']) {
      case 'critical':
        return _severityCritical;
      case 'warning':
        return _severityWarning;
      case 'info':
        return _severityInfo;
      default:
        return AppColors.accentCyan;
    }
  }

  @override
  Widget build(BuildContext context) {
    final severityColor = getSeverityColor();

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCodeCard(severityColor),
                      const SizedBox(height: 25),
                      _buildDetailsSection(),
                      const SizedBox(height: 25),
                      _buildImageGallery(),
                      const SizedBox(height: 25),
                      _buildRelatedCodes(),
                      const SizedBox(height: 25),
                      _buildActionButton(),
                    ],
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
            icon: const Icon(Icons.arrow_back, color: AppColors.accentCyan),
            onPressed: () => Navigator.pop(context),
          ),
          const Text(
            'Code Details',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.share, color: AppColors.accentCyan),
            onPressed: () {
              // Share functionality
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCodeCard(Color severityColor) {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            severityColor.withValues(alpha: 0.15),
            severityColor.withValues(alpha: 0.05),
          ],
        ),
        border: Border.all(
          color: severityColor.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: severityColor.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.2),
                  border: Border.all(color: severityColor, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.code['code'] as String? ?? '—',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: severityColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentCyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.code['system'] as String? ?? '—',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.accentCyan,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            widget.code['title'] as String? ?? '—',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.code['description'] as String? ?? '—',
            style: TextStyle(
              fontSize: 15,
              color: AppColors.textLight.withValues(alpha: 0.7),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.accentCyan, AppColors.accentOrange],
                ),
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'What This Means',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        _buildDetailCard(
          '⚠️',
          'Severity',
          (widget.code['severity'] as String? ?? 'info').toUpperCase(),
          getSeverityColor(),
        ),
        _buildDetailCard(
          '🔍',
          'Cause',
          'Faulty oxygen sensor or catalytic converter malfunction',
          AppColors.accentCyan,
        ),
        _buildDetailCard(
          '💰',
          'Estimated Cost',
          '\$200 - \$800',
          _severityInfo,
        ),
        _buildDetailCard(
          '⏱️',
          'Repair Time',
          '2-4 hours',
          AppColors.accentCyan,
        ),
      ],
    );
  }

  Widget _buildDetailCard(
    String icon,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: AppColors.white.withValues(alpha: 0.1),
        ),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(icon, style: const TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textLight.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGallery() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.accentCyan, AppColors.accentOrange],
                ),
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Related Images',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            itemBuilder: (context, index) {
              return Container(
                width: 120,
                margin: const EdgeInsets.only(right: 15),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.accentCyan.withValues(alpha: 0.2),
                      AppColors.accentOrange.withValues(alpha: 0.1),
                    ],
                  ),
                  border: Border.all(
                    color: AppColors.accentCyan.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  child: Text(
                    images[index],
                    style: const TextStyle(fontSize: 48),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRelatedCodes() {
    final relatedCodes = ['P0171', 'P0174', 'P0430'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.accentCyan, AppColors.accentOrange],
                ),
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Related Codes',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: relatedCodes.map((code) {
            return Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.05),
                border: Border.all(
                  color: AppColors.accentCyan.withValues(alpha: 0.3),
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                code,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentCyan,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildActionButton() {
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
        onPressed: () {
          Navigator.pushNamed(
            context,
            AppRoutes.solution,
            arguments: widget.code,
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.transparent,
          shadowColor: AppColors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        child: const Text(
          'VIEW SOLUTION',
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
}
