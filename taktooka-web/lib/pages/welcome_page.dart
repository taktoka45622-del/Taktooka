import 'package:flutter/material.dart';
import 'package:taktooka/app_shell.dart';
import 'package:taktooka/core/app_preferences.dart';

class FirstLaunchGate extends StatelessWidget {
  const FirstLaunchGate({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appPreferences,
    builder: (context, _) =>
    appPreferences.onboardingSeen ? const Shell() : const WelcomePage(),
  );
}

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final pages = PageController();
  int index = 0;
  bool saving = false;
  bool artworkReady = false;
  bool preparingArtwork = false;
  final artwork = List<ImageProvider>.generate(
    3,
    (page) => ResizeImage(
      AssetImage('assets/onboarding/screen_${page + 1}.png'),
      width: 1080,
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (preparingArtwork) return;
    preparingArtwork = true;
    Future.wait(artwork.map((image) => precacheImage(image, context))).then((_) {
        if (mounted) setState(() => artworkReady = true);
    });
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  Future<void> finish() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await appPreferences.completeOnboarding();
    } catch (_) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر المتابعة، حاول مرة ثانية')),
        );
      }
    }
  }

  void next() {
    if (saving || !artworkReady) return;
    if (index == 2) {
      finish();
    } else {
      pages.animateToPage(
        index + 1,
        duration: Duration(
          milliseconds: MediaQuery.disableAnimationsOf(context) ? 1 : 380,
        ),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: pages,
            itemCount: 3,
            physics: artworkReady ? null : const NeverScrollableScrollPhysics(),
            onPageChanged: (value) => setState(() => index = value),
            itemBuilder: (context, page) => _RetainedWelcomePage(
              child: Semantics(
                label: const [
                  'أهلاً بيك بتكتوكة. مشوارك يبدأ بلمسة. حدد وجهتك واطلب تكتك من مكانك',
                  'من مكانك لوجهتك. حدد وجهتك وتابع مشوارك. شوف تفاصيل الرحلة وتابع الكابتن على الخريطة',
                  'عندك تكتك؟ سجّل كابتن ويانا واستقبل طلبات المشاوير',
                ][page],
                image: true,
                child: ExcludeSemantics(
                  child: Image(
                    image: artwork[page],
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: TextButton(
                  onPressed: saving ? null : finish,
                  child: const Text('تخطي', style: TextStyle(color: Colors.grey)),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          label: 'الصفحة ${index + 1} من 3',
                          child: ExcludeSemantics(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(3, (dot) => Container(
                                  width: 10,
                                  height: 10,
                                  margin: const EdgeInsets.symmetric(horizontal: 5),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: dot == index
                                    ? const Color(0xffed202d)
                                    : Colors.grey.shade300,
                                  ),
                              )),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 52),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              backgroundColor: const Color(0xffed202d),
                              foregroundColor: Colors.white,
                              shape: const StadiumBorder(),
                            ),
                            onPressed: saving || !artworkReady ? null : next,
                            child: Text(saving ? 'لحظة…' : index == 2 ? 'ابدأ الآن' : 'التالي'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _RetainedWelcomePage extends StatefulWidget {
  const _RetainedWelcomePage({required this.child});
  final Widget child;
  @override
  State<_RetainedWelcomePage> createState() => _RetainedWelcomePageState();
}

class _RetainedWelcomePageState extends State<_RetainedWelcomePage>
with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RepaintBoundary(child: widget.child);
  }
}
