import 'package:fav/core/theme/app_dimens.dart';
import 'package:flutter/material.dart';

/// A compact top bar whose title follows the width of the page content.
class ResponsiveAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Creates a responsive top bar.
  const ResponsiveAppBar({
    required this.title,
    required this.maxContentWidth,
    this.actions = const [],
    super.key,
  });

  /// Text displayed in the bar.
  final String title;

  /// Maximum width shared with the screen body.
  final double maxContentWidth;

  /// Actions shown at the trailing edge of the content column.
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return AppBar(title: Text(title), actions: actions);
        }
        return ColoredBox(
          color: theme.scaffoldBackgroundColor,
          child: SizedBox(
            width: double.infinity,
            height: kToolbarHeight,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.lg),
                    child: Row(
                      children: [
                        if (Navigator.of(context).canPop()) ...[
                          const BackButton(),
                          const SizedBox(width: AppSpacing.xs),
                        ] else
                          const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(
                              title,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        ...actions,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
