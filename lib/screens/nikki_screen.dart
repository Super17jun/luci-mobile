import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:luci_mobile/state/nikki_state.dart'; // 引入刚才建的状态文件

class NikkiScreen extends ConsumerStatefulWidget {
  const NikkiScreen({super.key});

  @override
  ConsumerState<NikkiScreen> createState() => _NikkiScreenState();
}

class _NikkiScreenState extends ConsumerState<NikkiScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // 控制器
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _secretController = TextEditingController();

  // 数据状态
  List<Map<String, dynamic>> _proxyGroups = [];
  List<dynamic> _connections = [];
  List<dynamic> _rules = [];
  
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this); // 3个标签页
  }
  
  // 页面加载完成后，检查是否自动登录
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final config = ref.read(nikkiConfigProvider);
    
    // 初始化输入框
    if (_ipController.text.isEmpty) _ipController.text = config.ip;
    if (_portController.text.isEmpty) _portController.text = config.port;
    if (_secretController.text.isEmpty) _secretController.text = config.secret;

    // 如果已经配置过，自动刷新数据
    if (config.isConfigured) {
      _fetchAllData();
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

  // --- API 请求部分 ---

  String get _baseUrl {
    final config = ref.read(nikkiConfigProvider);
    return 'http://${config.ip}:${config.port}';
  }
  
  Map<String, String> get _headers {
    final config = ref.read(nikkiConfigProvider);
    return {
      'Authorization': 'Bearer ${config.secret}',
      'Content-Type': 'application/json',
    };
  }

  // 获取所有数据 (代理、连接、规则)
  Future<void> _fetchAllData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // 保存配置到状态管理
      ref.read(nikkiConfigProvider.notifier).setConfig(
        _ipController.text, 
        _portController.text, 
        _secretController.text
      );

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
        _errorMessage = '连接失败: $e';
      });
    }
  }

  Future<void> _fetchProxies() async {
    final response = await http.get(Uri.parse('$_baseUrl/proxies'), headers: _headers);
    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes));
      final proxies = data['proxies'] as Map<String, dynamic>;
      List<Map<String, dynamic>> groups = [];
      proxies.forEach((key, value) {
        if (value['type'] == 'Selector') {
          groups.add({'name': key, 'now': value['now'], 'all': List<String>.from(value['all'])});
        }
      });
      // 排序: 确保 Proxy 在前
      groups.sort((a, b) => a['name'].contains('Proxy') ? -1 : 1);
      setState(() => _proxyGroups = groups);
    }
  }

  Future<void> _fetchConnections() async {
    // Nikki 的 snapshot API
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
      _fetchAllData(); // 失败回滚
    }
  }

  // --- 界面部分 ---

  // 1. 登录配置页 (当没连接时显示)
  Widget _buildLoginForm() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.electrical_services, size: 64, color: Colors.deepPurple),
            const SizedBox(height: 24),
            TextField(controller: _ipController, decoration: const InputDecoration(labelText: 'IP 地址', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _portController, decoration: const InputDecoration(labelText: '端口 (9090)', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _secretController, obscureText: true, decoration: const InputDecoration(labelText: '密钥 (Secret)', border: OutlineInputBorder())),
            const SizedBox(height: 24),
            if (_errorMessage.isNotEmpty) Text(_errorMessage, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _fetchAllData,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('连接 Nikki'),
            ),
          ],
        ),
      ),
    );
  }

  // 2. 代理组列表
  Widget _buildProxyList() {
    return RefreshIndicator(
      onRefresh: _fetchProxies,
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

  // 3. 连接监控列表
  Widget _buildConnectionList() {
    return RefreshIndicator(
      onRefresh: _fetchConnections,
      child: _connections.isEmpty 
        ? const Center(child: Text('暂无活跃连接'))
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
                    child: Text(metadata['networkType'].toString().substring(0,1), style: const TextStyle(fontSize: 12)),
                  ),
                  title: Text(host, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text("${conn['chains'].last} • ${metadata['processPath'] ?? 'Unknown'}"),
                  trailing: Text("${conn['upload']}/${conn['download']}", style: const TextStyle(fontSize: 10)),
                ),
              );
            },
          ),
    );
  }

  // 4. 规则列表
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

  @override
  Widget build(BuildContext context) {
    // 监听 Provider，看是否已配置
    final config = ref.watch(nikkiConfigProvider);

    if (!config.isConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nikki 登录')),
        body: _buildLoginForm(),
      );
    }

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
               // 退出时重置状态
               ref.read(nikkiConfigProvider.notifier).reset();
            },
          )
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProxyList(),
          _buildConnectionList(),
          _buildRuleList(),
        ],
      ),
    );
  }
}