import 'package:flutter/material.dart';

import '../../core/theme/circa_theme.dart';
import '../../widgets/circa_widgets.dart';
import 'legal_content.dart';

// Re-exported so a caller that renders a LegalScreen also gets the
// documents to hand it, without importing both halves.
export 'legal_content.dart';

/// Renders a [LegalDocument].
///
/// Bundled rather than fetched: Circa is offline-first, and legal text a user
/// can only read with a working connection is not meaningfully "available" at
/// the moment they are deciding whether to pay.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final t = context.circa;
    final colors = t.color;
    final gutter = t.space.gutter(MediaQuery.sizeOf(context).width);

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(title: Text(document.title)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(gutter, t.space.base, gutter, t.space.x4),
        children: [
          Text(
            'Effective $kLegalEffectiveDate',
            style: t.type.caption.copyWith(color: colors.textTertiary),
          ),
          SizedBox(height: t.space.md),
          GlassCard(
            child: Text(
              document.summary,
              style: t.type.bodyM.copyWith(color: colors.textPrimary),
            ),
          ),
          SizedBox(height: t.space.section),
          for (final section in document.sections) ...[
            SectionLabel(section.heading),
            SizedBox(height: t.space.sm),
            for (final paragraph in section.body)
              Padding(
                padding: EdgeInsets.only(bottom: t.space.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: t.space.sm),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.textTertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    SizedBox(width: t.space.md),
                    Expanded(
                      child: Text(
                        paragraph,
                        style: t.type.bodyM
                            .copyWith(color: colors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(height: t.space.lg),
          ],
        ],
      ),
    );
  }
}
