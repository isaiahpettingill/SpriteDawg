import 'package:flutter/material.dart';

/// Space-based layout: tablets retain touch targets; desktop gets simultaneous
/// tools, layers, canvas and timeline rather than a stretched phone screen.
class ResponsiveEditorShell extends StatelessWidget {
  const ResponsiveEditorShell({
    super.key,
    required this.mobileBody,
    required this.canvas,
    required this.tools,
    required this.layers,
    required this.timeline,
    this.documentTabs,
  });
  final Widget mobileBody, canvas, tools, layers, timeline;
  final Widget? documentTabs;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 700 && box.maxHeight >= 500;
      final desktop = box.maxWidth >= 1100 && box.maxHeight >= 600;
      return Column(
        children: [
          if (documentTabs != null) SizedBox(height: 52, child: documentTabs),
          Expanded(
            child: !wide
                ? mobileBody
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 64,
                        child: Material(
                          color: const Color(0xff1c2331),
                          child: SingleChildScrollView(child: tools),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(child: canvas),
                            const Divider(height: 1),
                            SizedBox(height: 260, child: timeline),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      SizedBox(width: desktop ? 240 : 190, child: layers),
                    ],
                  ),
          ),
        ],
      );
    },
  );
}
