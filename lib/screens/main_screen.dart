import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/screens/clients_screen.dart';
import 'package:luci_mobile/screens/dashboard_screen.dart';
import 'package:luci_mobile/screens/interfaces_screen.dart';
import 'package:luci_mobile/screens/more_screen.dart';
// 引入 Nikki 页面和状态
import 'package:luci_mobile/screens/nikki_screen.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/state/nikki_state.dart';
import 'package:luci_mobile/widgets/luci_navigation_enhancements.dart';

class MainScreen extends ConsumerStatefulWidget {
  final int? initialTab;
  final String? interfaceToScroll;

  const MainScreen({super.key, this.initialTab, this.interfaceToScroll});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _selectedIndex = 0;
  String? _currentInterfaceToScroll;

  @override
  void initState() {
    super.initState();
    if (widget.initialTab != null) {
      _selectedIndex = widget.initialTab!;
    }
    _currentInterfaceToScroll = widget.interfaceToScroll;
  }

  @override
  void didUpdateWidget(MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.interfaceToScroll != oldWidget.interfaceToScroll) {
      _currentInterfaceToScroll = widget.interfaceToScroll;
    }

    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != null) {
      _selectedIndex = widget.initialTab!;
    }
  }

  void _clearInterfaceToScroll() {
    if (_currentInterfaceToScroll != null) {
      setState(() {
        _currentInterfaceToScroll = null;
      });
    }
  }

  // 🔥 修改 1: 在列表中加入 NikkiScreen
  List<Widget> get _widgetOptions => [
        const DashboardScreen(),
        const ClientsScreen(),
        InterfacesScreen(
          scrollToInterface: _currentInterfaceToScroll,
          onScrollComplete: _clearInterfaceToScroll,
        ),
        const NikkiScreen(), // 新增在这里 (Index 3)
        const MoreScreen(), // More 变成了 Index 4
      ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    // 如果离开 Interfaces 页面 (Index 2)，清除滚动状态
    if (_selectedIndex != 2 && _currentInterfaceToScroll != null) {
      _clearInterfaceToScroll();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 修改 2: 监听路由器切换事件，自动同步 IP 给 Nikki
    ref.listen(appStateProvider.select((s) => s.selectedRouter), (previous, next) {
      if (next != null) {
        // 如果切换了路由器，通知 Nikki 更新目标 IP
        ref.read(nikkiConfigProvider.notifier).updateIp(next.ipAddress);
      }
    });

    final appState = ref.watch(appStateProvider);
    if (appState.requestedTab != null &&
        appState.requestedTab != _selectedIndex) {
      final requestedTab = appState.requestedTab!;
      final requestedInterface = appState.requestedInterfaceToScroll;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _selectedIndex = requestedTab;
          if (requestedInterface != null) {
            _currentInterfaceToScroll = requestedInterface;
          }
        });
        appState.requestedTab = null;
        appState.requestedInterfaceToScroll = null;
      });
    }

    return Scaffold(
      body: Center(
        child: LuciTabTransition(
          transitionKey: 'tab_$_selectedIndex',
          child: _widgetOptions.elementAt(_selectedIndex),
        ),
      ),
      bottomNavigationBar: Builder(
        builder: (context) {
          final isRebooting = ref.watch(
            appStateProvider.select((state) => state.isRebooting),
          );
          
          // 🔥 修改 3: 调整重启时的禁用逻辑 (因为 More 现在是 index 4)
          Color? getTabColor(int index) =>
              (isRebooting && index != 4) ? Colors.grey.withAlpha(128) : null;
          double getTabOpacity(int index) =>
              (isRebooting && index != 4) ? 0.5 : 1.0;
              
          return NavigationBar(
            onDestinationSelected: (index) {
              if (isRebooting && index != 4) return; // 重启时只允许点击 More
              _onItemTapped(index);
            },
            selectedIndex: _selectedIndex,
            // 🔥 修改 4: 添加 Nikki 的导航图标
            destinations: [
              NavigationDestination(
                selectedIcon: Opacity(
                  opacity: getTabOpacity(0),
                  child: Icon(Icons.dashboard, color: getTabColor(0)),
                ),
                icon: Opacity(
                  opacity: getTabOpacity(0),
                  child: Icon(Icons.dashboard_outlined, color: getTabColor(0)),
                ),
                label: '仪表板',
              ),
              NavigationDestination(
                selectedIcon: Opacity(
                  opacity: getTabOpacity(1),
                  child: Icon(Icons.people, color: getTabColor(1)),
                ),
                icon: Opacity(
                  opacity: getTabOpacity(1),
                  child: Icon(Icons.people_outline, color: getTabColor(1)),
                ),
                label: '客户端',
              ),
              NavigationDestination(
                selectedIcon: Opacity(
                  opacity: getTabOpacity(2),
                  child: Icon(Icons.lan, color: getTabColor(2)),
                ),
                icon: Opacity(
                  opacity: getTabOpacity(2),
                  child: Icon(Icons.lan_outlined, color: getTabColor(2)),
                ),
                label: '接口',
              ),
              // --- 新增 Nikki 导航项 ---
              NavigationDestination(
                selectedIcon: Opacity(
                  opacity: getTabOpacity(3),
                  child: Icon(Icons.electrical_services, color: getTabColor(3)),
                ),
                icon: Opacity(
                  opacity: getTabOpacity(3),
                  child: Icon(Icons.electrical_services_outlined, color: getTabColor(3)),
                ),
                label: 'Nikki',
              ),
              // ---------------------
              NavigationDestination(
                selectedIcon: Opacity(
                  opacity: getTabOpacity(4),
                  child: Icon(Icons.more_horiz),
                ),
                icon: Opacity(
                  opacity: getTabOpacity(4),
                  child: Icon(Icons.more_horiz_outlined),
                ),
                label: '更多',
              ),
            ],
          );
        },
      ),
    );
  }
}