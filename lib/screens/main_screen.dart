import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/navigation_provider.dart';
import '../widgets/alarm_banner.dart';
import '../widgets/bottom_navbar.dart';
import '../widgets/sos_button.dart';
import 'home_screen.dart';
import 'monitoring_screen.dart';
import 'settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    final navProvider = Provider.of<NavigationProvider>(context, listen: false);
    _pageController = PageController(initialPage: navProvider.currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Sits outside the PageView on purpose: each screen scrolls
          // independently, so a banner placed inside one would scroll away
          // and would only exist on that tab. An alarm must stay visible
          // regardless of tab or scroll position.
          const SosBanner(),
          const AlarmBanner(),
          Expanded(
            child: Consumer<NavigationProvider>(
              builder: (context, navProvider, child) {
                if (_pageController.hasClients) {
                  final currentPage = _pageController.page?.round();
                  if (currentPage != navProvider.currentIndex) {
                    _pageController.animateToPage(
                      navProvider.currentIndex,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeInOutQuart,
                    );
                  }
                }

                return PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    if (navProvider.currentIndex != index) {
                      navProvider.changePage(index);
                    }
                  },
                  physics: const NeverScrollableScrollPhysics(),
                  children: const [
                    HomeScreen(),
                    MonitoringScreen(),
                    SettingsScreen(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: const BottomNavbar(),
    );
  }
}
