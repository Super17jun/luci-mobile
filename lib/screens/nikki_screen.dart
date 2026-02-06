import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:luci_mobile/state/nikki_state.dart';

class NikkiScreen extends ConsumerStatefulWidget {
  // 接收从 MoreScreen 传来的路由器 IP
  final String? initialIp;
  const NikkiScreen({super.key, this.initialIp});

  @override
  ConsumerState<NikkiScreen> createState() => _NikkiScreenState();
}

class _NikkiScreenState extends ConsumerState<NikkiScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // 控制器
  late TextEditingController _ipController;
  final TextEditingController _portController = TextEditingController(text: '9090');
  final TextEditingController _secretController = TextEditingController(); // 修复：不再预设密码

  // 数据状态
  List<Map<String, dynamic>> _proxyGroups = [];
  List<dynamic> _connections = [];
  List<dynamic> _rules = [];
  
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // 优先使用传入的 IP，如果没有则留空
    _ipController = TextEditingController(text: widget.initialIp ?? '');
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 检查状态管理里是否已经有保存的配置
    final config = ref.read(nikkiConfigProvider);

    // 如果已经登录过 (isConfigured 为 true)，则把保存的信息回填到输入框，并刷新数据
    if (config.isConfigured) {
      if (_ipController.text.isEmpty) _ipController.text = config.ip;
      if (_portController.text.isEmpty) _portController.text = config.port;
      if (_secretController.text.isEmpty) _secretController.text = config.secret;
      
      // 自动刷新数据
      _fetchAllData();
    } else {
      // 如果还没登录，且传入了路由器 IP，自动填入 IP 方便用户
      if (widget.initialIp != null && _ipController.text.isEmpty) {
        _ipController.text = widget.initialIp!;
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  // --- 核心修复：登录验证逻辑 ---
  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final ip = _ipController.text.trim();
    final port = _portController.text.trim();
    final secret = _secretController.text.trim();

    if (ip.isEmpty || port.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = '请填写 IP 和端口';
      });
      return;
    }

    final url = Uri.parse('http://$ip:$port/proxies');
    
    try {
      // 1. 发送测试请求 (此时还未保存状态)
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $secret',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));

      // 2. 根据状态码判断
      if (response.statusCode == 200) {
        // ✅ 验证通过！保存配置到全局状态
        ref.read(nikkiConfigProvider.notifier).setConfig(ip, port, secret);
        
        // 解析数据并显示
        _parseProxies(response.bodyBytes);
        
        // 顺便获取连接和规则
        await Future.wait([_fetchConnections(), _fetchRules()]);

        setState(() {
          _isLoading = false;
        });
      } else if (response.statusCode == 401) {
        // ❌ 验证失败：密钥错误
        setState(() {
          _isLoading = false;
          _errorMessage = '验证失败：密钥 (Secret) 错误';
        });
      } else {
        // ❌ 其他错误
        setState(() {
          _isLoading = false;
          _errorMessage = '连接失败 (状态码 ${response.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '无法连接到服务器。\n请检查 IP/端口是否正确，\n以及 Info.plist 是否允许 HTTP 请求。';
      });
    }
  }

  // --- API 请求部分 (用于登录后的刷新) ---

  String get _baseUrl {
    final config = ref.read(nikkiConfigProvider);
    // 如果还没配置，使用输入框的值 (防止 null 错误)
    if (!config.isConfigured) return 'http://${_ipController.text}:${_portController.text}';
    return 'http://${config.ip}:${config.port}';
  }
  
  Map<String, String> get _headers {
    final config = ref.read(nikkiConfigProvider);
    final secret = config.isConfigured ? config.secret : _secretController.text;
    return {
      'Authorization': 'Bearer $secret',
      'Content-Type': 'application/json',
    };
  }

  Future<void> _fetchAllData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      await Future.wait([
        _fetchProxies(),
        _fetchConnections(),
        _fetchRules(),
      ]);
      setState(() {
        _isLoading = false;
        _errorMessage = '';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        // 如果是刷新时出错，不一定是配置错，可能是网络波动
        // 但如果是 401，说明密钥过期了
        if (e.toString().contains('401')) {
           _errorMessage = '密钥已过期，请重新登录';
           ref.read(nikkiConfigProvider.notifier).reset(); // 踢出登录
        }
      });
    }
  }

  Future<void> _fetchProxies() async {
    final response = await http.get(Uri.parse('$_baseUrl/proxies'), headers: _headers);
    if (response.statusCode == 200) {
      _parseProxies(response.bodyBytes);
    } else if (response.statusCode == 401) {
      throw Exception('401 Unauthorized');
    }
  }

  void _parseProxies(List<int> bodyBytes) {
    final data = json.decode(utf8.decode(bodyBytes));
    final proxies = data['proxies'] as Map<String, dynamic>;
    List<Map<String, dynamic>> groups = [];
    proxies.forEach((key, value) {
      if (value['type'] == 'Selector') {
        groups.add({'name': key, 'now': value['now'], 'all': List<String>.from(value['all'])});
      }
    });
    groups.sort((a, b) => a['name'].contains('Proxy') ? -1 : 1);
    setState(() => _proxyGroups = groups);
  }

  Future<void> _fetchConnections() async {
    final response = await http.get(Uri.parse('$_baseUrl/connections'), headers: _headers);
    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes));
      setState(() => _connections = data['connections'] ?? []);
    }
  }
  
  Future<void> _fetchRules() async {
    final response = await http.get(Uri.parse('$_baseUrl/rules'), headers: _headers);
    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes));
      setState(() => _rules = data['rules'] ?? []);
    }
  }

  // 切换节点
  Future<void> _selectProxy(String groupName, String nodeName) async {
    setState(() {
      final index = _proxyGroups.indexWhere((g) => g['name'] == groupName);
      if (index != -1) _proxyGroups[index]['now'] = nodeName;
    });
    
    final encodedGroup = Uri.encodeComponent(groupName);
    try {
      await http.put(
        Uri.parse('$_baseUrl/proxies/$encodedGroup'),
        headers: _headers,
        body: json.encode({'name': nodeName}),
      );
    } catch (e) {
      _fetchProxies(); // 失败回滚
    }
  }

  // --- 界面部分 ---

  Widget _buildLoginForm() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.electrical_services, size: 64, color: Colors.deepPurple),
            const SizedBox(height: 24),
            TextField(controller: _ipController, decoration: const InputDecoration(labelText: 'IP 地址', border: OutlineInputBorder(), prefixIcon: Icon(Icons.router))),
            const SizedBox(height: 16),
            TextField(controller: _portController, decoration: const InputDecoration(labelText: '端口 (9090)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.login))),
            const SizedBox(height: 16),
            TextField(controller: _secretController, obscureText: true, decoration: const InputDecoration(labelText: '密钥 (Secret)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.vpn_key))),
            const SizedBox(height: 24),
            if (_errorMessage.isNotEmpty) 
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(_errorMessage, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              ),
            ElevatedButton(
              onPressed: _isLoading ? null : _login, // 🔥 修复：点击按钮调用 _login 而不是 _fetchAllData
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('验证并连接', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ... (下面的 _buildProxyList, _buildConnectionList, _buildRuleList, _showNodeSelectionDialog 和 build 方法保持原样或直接使用下面的完整 build) ...
  
  // 为确保完整性，这里提供完整的 build 方法
  @override
  Widget build(BuildContext context) {
    // 监听 Provider，看是否已配置
    final config = ref.watch(nikkiConfigProvider);

    // 如果没配置，显示登录页
    if (!config.isConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nikki 登录')),
        body: _buildLoginForm(),
      );
    }

    // 如果已配置，显示 Dashboard
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nikki 控制台'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.deepPurple,
          indicatorColor: Colors.deepPurple,
          tabs: const [
            Tab(text: '代理', icon: Icon(Icons.dns)),
            Tab(text: '连接', icon: Icon(Icons.swap_vert)),
            Tab(text: '规则', icon: Icon(Icons.list_alt)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '注销连接',
            onPressed: () {
               ref.read(nikkiConfigProvider.notifier).reset();
            },
          )
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProxyList(), // 复用之前的代码
          _buildConnectionList(), // 复用之前的代码
          _buildRuleList(), // 复用之前的代码
        ],
      ),
    );
  }

  // 补全缺失的 UI 构建方法 (复用之前的，但确保 context 正确)
  Widget _buildProxyList() {
    return RefreshIndicator(
      onRefresh: _fetchAllData,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _proxyGroups.length,
        itemBuilder: (context, index) {
          final group = _proxyGroups[index];
          return Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(group['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(group['now'], style: const TextStyle(color: Colors.deepPurple)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: () => _showNodeSelectionDialog(group),
            ),
          );
        },
      ),
    );
  }

  Widget _buildConnectionList() {
    return RefreshIndicator(
      onRefresh: _fetchConnections,
      child: _connections.isEmpty 
        ? const Center(child: Text('暂无活跃连接', style: TextStyle(color: Colors.grey)))
        : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _connections.length,
            itemBuilder: (context, index) {
              final conn = _connections[index];
              final metadata = conn['metadata'];
              final host = metadata['host'] == '' ? metadata['destinationIP'] : metadata['host'];
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: Colors.deepPurple.withOpacity(0.1),
                    child: Text(metadata['networkType'].toString().substring(0,1), style: const TextStyle(fontSize: 12, color: Colors.deepPurple)),
                  ),
                  title: Text(host, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text("${conn['chains'].last} • ${metadata['processPath'] ?? 'Unknown'}"),
                  trailing: Text("${_formatBytes(conn['upload'])} / ${_formatBytes(conn['download'])}", style: const TextStyle(fontSize: 10)),
                ),
              );
            },
          ),
    );
  }

  Widget _buildRuleList() {
    return RefreshIndicator(
      onRefresh: _fetchRules,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _rules.length,
        itemBuilder: (context, index) {
          final rule = _rules[index];
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.1))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(rule['type'], style: const TextStyle(fontSize: 10, color: Colors.blue)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(rule['payload'], style: const TextStyle(fontSize: 13))),
                Text(rule['proxy'], style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
          );
        },
      ),
    );
  }
  
  // 简单的字节格式化辅助函数
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showNodeSelectionDialog(Map<String, dynamic> group) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final allNodes = group['all'] as List<String>;
        return Column(
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(group['name'], style: const TextStyle(fontWeight: FontWeight.bold))),
            Expanded(
              child: ListView.builder(
                itemCount: allNodes.length,
                itemBuilder: (context, index) {
                  final node = allNodes[index];
                  final isSelected = node == group['now'];
                  return ListTile(
                    title: Text(node, style: TextStyle(color: isSelected ? Colors.deepPurple : null)),
                    trailing: isSelected ? const Icon(Icons.check, color: Colors.deepPurple) : null,
                    onTap: () {
                      Navigator.pop(context);
                      if (!isSelected) _selectProxy(group['name'], node);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}