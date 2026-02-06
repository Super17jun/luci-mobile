import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class NikkiScreen extends StatefulWidget {
  // 接收从外部传入的初始 IP（比如 App 当前连接的路由器 IP）
  final String? initialIp;
  
  const NikkiScreen({super.key, this.initialIp});

  @override
  State<NikkiScreen> createState() => _NikkiScreenState();
}

class _NikkiScreenState extends State<NikkiScreen> {
  // --- 配置状态 ---
  late TextEditingController _ipController;
  final TextEditingController _portController = TextEditingController(text: '9090');
  final TextEditingController _secretController = TextEditingController(text: '523897'); // 默认填你的密钥
  
  // --- 页面状态 ---
  // true: 显示配置/登录页; false: 显示节点管理页
  bool _isConfiguring = true; 
  bool _isLoading = false;
  String _errorMessage = '';
  
  // --- 数据 ---
  List<Map<String, dynamic>> _proxyGroups = [];

  @override
  void initState() {
    super.initState();
    // 如果传入了 IP，就填入输入框；否则留空或填默认
    _ipController = TextEditingController(text: widget.initialIp ?? '192.168.2.1');
    
    // 如果有传入 IP，可以尝试自动连接（可选，这里我设定为手动点击连接更安全）
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  // --- 核心逻辑：尝试连接并获取数据 ---
  Future<void> _connectAndFetch() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final ip = _ipController.text.trim();
    final port = _portController.text.trim();
    final secret = _secretController.text.trim();

    if (ip.isEmpty || port.isEmpty) {
      setState(() {
        _errorMessage = '请填写 IP 和端口';
        _isLoading = false;
      });
      return;
    }

    final url = Uri.parse('http://$ip:$port/proxies');
    
    try {
      // 1. 发起请求测试连接
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $secret',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 5)); // 5秒超时防止卡死

      // 2. 处理结果
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final proxies = data['proxies'] as Map<String, dynamic>;
        
        List<Map<String, dynamic>> groups = [];
        proxies.forEach((key, value) {
          if (value['type'] == 'Selector') {
            groups.add({
              'name': key,
              'now': value['now'],
              'all': List<String>.from(value['all']),
            });
          }
        });
        
        // 排序
        groups.sort((a, b) => a['name'].compareTo(b['name']));

        setState(() {
          _proxyGroups = groups;
          _isConfiguring = false; // 切换到管理界面
          _isLoading = false;
        });
      } else if (response.statusCode == 401) {
        setState(() {
          _errorMessage = '密钥错误 (401 Unauthorized)';
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = '连接失败: 代码 ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '无法连接到 Nikki。\n请检查 IP/端口是否正确，\n以及 Info.plist 是否允许 HTTP 请求。';
        _isLoading = false;
      });
    }
  }

  // --- 核心逻辑：切换节点 ---
  Future<void> _selectProxy(String groupName, String nodeName) async {
    // 乐观更新
    setState(() {
      final index = _proxyGroups.indexWhere((g) => g['name'] == groupName);
      if (index != -1) {
        _proxyGroups[index]['now'] = nodeName;
      }
    });

    final ip = _ipController.text.trim();
    final port = _portController.text.trim();
    final secret = _secretController.text.trim();
    
    final encodedGroup = Uri.encodeComponent(groupName);
    final url = Uri.parse('http://$ip:$port/proxies/$encodedGroup');

    try {
      await http.put(
        url,
        headers: {
          'Authorization': 'Bearer $secret',
          'Content-Type': 'application/json',
        },
        body: json.encode({'name': nodeName}),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('切换失败: $e')),
      );
      _connectAndFetch(); // 失败后刷新数据
    }
  }

  // --- 界面 1: 登录配置表单 ---
  Widget _buildConfigForm() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.electrical_services, size: 32, color: Colors.deepPurple),
                    SizedBox(width: 12),
                    Text('连接 Nikki', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: '管理地址 (IP)',
                    prefixIcon: Icon(Icons.router),
                    border: OutlineInputBorder(),
                    hintText: '例如 192.168.2.1',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _portController,
                  decoration: const InputDecoration(
                    labelText: 'API 端口',
                    prefixIcon: Icon(Icons.login),
                    border: OutlineInputBorder(),
                    hintText: '默认 9090',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _secretController,
                  decoration: const InputDecoration(
                    labelText: 'API 密钥 (Secret)',
                    prefixIcon: Icon(Icons.vpn_key),
                    border: OutlineInputBorder(),
                    hintText: '留空则无密码',
                  ),
                  obscureText: true, // 隐藏密码
                ),
                const SizedBox(height: 24),
                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _connectAndFetch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('连接', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- 界面 2: 节点列表 (复用你之前的逻辑) ---
  Widget _buildDashboard() {
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: _proxyGroups.length,
      itemBuilder: (context, index) {
        final group = _proxyGroups[index];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            leading: const Icon(Icons.dns_outlined, color: Colors.blueAccent),
            title: Text(group['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              '当前: ${group['now']}',
              style: const TextStyle(color: Colors.green),
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showNodeSelectionDialog(group),
          ),
        );
      },
    );
  }
  
  // 弹窗逻辑 (和之前一样)
  void _showNodeSelectionDialog(Map<String, dynamic> group) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        final allNodes = group['all'] as List<String>;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('选择 ${group['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: allNodes.length,
                itemBuilder: (context, index) {
                  final node = allNodes[index];
                  final isSelected = node == group['now'];
                  return ListTile(
                    title: Text(node, style: TextStyle(
                      color: isSelected ? Colors.deepPurple : null,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    )),
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_isConfiguring ? '配置连接' : 'Nikki 代理控制'),
        actions: [
          if (!_isConfiguring) // 如果在管理页，显示“设置”按钮切回配置
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: '修改连接配置',
              onPressed: () {
                setState(() {
                  _isConfiguring = true; // 切回配置页
                });
              },
            ),
          if (!_isConfiguring) // 刷新按钮
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _connectAndFetch,
            ),
        ],
      ),
      body: _isConfiguring ? _buildConfigForm() : _buildDashboard(),
    );
  }
}