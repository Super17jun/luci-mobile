// lib/state/nikki_state.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 定义一个模型来保存 Nikki 的配置
class NikkiConfig {
  final String ip;
  final String port;
  final String secret;
  final bool isConfigured; // 是否已经配置过并成功登录

  NikkiConfig({
    this.ip = '',
    this.port = '9090',
    this.secret = '523897', // 默认密码
    this.isConfigured = false,
  });

  NikkiConfig copyWith({
    String? ip,
    String? port,
    String? secret,
    bool? isConfigured,
  }) {
    return NikkiConfig(
      ip: ip ?? this.ip,
      port: port ?? this.port,
      secret: secret ?? this.secret,
      isConfigured: isConfigured ?? this.isConfigured,
    );
  }
}

// 创建一个 Provider 来管理这个状态
// autoDispose: 当不再使用时自动销毁，但这里我们希望它常驻，所以不用 autoDispose
final nikkiConfigProvider = StateNotifierProvider<NikkiConfigNotifier, NikkiConfig>((ref) {
  return NikkiConfigNotifier();
});

class NikkiConfigNotifier extends StateNotifier<NikkiConfig> {
  NikkiConfigNotifier() : super(NikkiConfig());

  // 设置配置并标记为已配置
  void setConfig(String ip, String port, String secret) {
    state = state.copyWith(
      ip: ip,
      port: port,
      secret: secret,
      isConfigured: true,
    );
  }

  // 重置配置 (比如切换路由器时调用)
  void reset() {
    state = NikkiConfig();
  }
  
  // 更新 IP (当路由器切换时自动同步)
  void updateIp(String newIp) {
    if (state.ip != newIp) {
      state = state.copyWith(ip: newIp, isConfigured: false); // IP 变了需要重新验证
    }
  }
}