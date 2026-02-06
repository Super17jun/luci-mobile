import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class NikkiScreen extends StatefulWidget {
  // 假设路由器IP是 192.168.1.1，如果你的不一样，请在调用时修改或在这里改
  final String routerIp;
  
  const NikkiScreen({super.key, this.routerIp = '192.168.2.1'});

  @override
  State<NikkiScreen> createState() => _NikkiScreenState();
}

class _NikkiScreenState extends State<NikkiScreen> {
  final String apiPort = '9090';
  final String apiSecret = '523897';
  
  bool _isLoading = true;
  String _errorMessage = '';
  
  // 存放解析后的策略组数据
  // 格式: [{"name": "节点选择", "now": "香港01", "all": ["香港01", "美国02"...]}]
  List<Map<String, dynamic>> _proxyGroups = [];

  @override
  void initState() {
    super.initState();
    _fetchProxies();
  }

  // 获取节点信息
  Future<void> _fetchProxies() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final url = Uri.parse('http://${widget.routerIp}:$apiPort/proxies');
    
    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $apiSecret', // 鉴权头
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes)); // 防止中文乱码
        final proxies = data['proxies'] as Map<String, dynamic>;
        
        List<Map<String, dynamic>> groups = [];
        
        // 筛选出类型为 "Selector" (策略组) 的项
        proxies.forEach((key, value) {
          if (value['type'] == 'Selector') {
            groups.add({
              'name': key,
              'now': value['now'], // 当前选中的节点
              'all': List<String>.from(value['all']), // 所有可选节点
            });
          }
        });

        // 简单的排序，让常用的排前面（可选）
        groups.sort((a, b) => a['name'].compareTo(b['name']));

        setState(() {
          _proxyGroups = groups;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = '连接失败: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '无法连接到 Nikki。\n请检查:\n1. 手机是否已连上WiFi\n2. Info.plist 是否允许了 HTTP 请求\n错误: $e';
        _isLoading = false;
      });
    }
  }

  // 切换节点
  Future<void> _selectProxy(String groupName, String nodeName) async {
    // 乐观更新 UI：不等服务器返回，先在界面上改过来，体验更流畅
    setState(() {
      final index = _proxyGroups.indexWhere((g) => g['name'] == groupName);
      if (index != -1) {
        _proxyGroups[index]['now'] = nodeName;
      }
    });

    // 发送请求给路由器
    // URL encoded 因为组名可能包含特殊字符
    final encodedGroup = Uri.encodeComponent(groupName);
    final url = Uri.parse('http://${widget.routerIp}:$apiPort/proxies/$encodedGroup');

    try {
      await http.put(
        url,
        headers: {
          'Authorization': 'Bearer $apiSecret',
          'Content-Type': 'application/json',
        },
        body: json.encode({'name': nodeName}),
      );
      // 成功后可以不提示，或者 SnackBar 提示
    } catch (e) {
      // 失败了再提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('切换失败: $e')),
      );
      // 最好这里重新刷新一下数据
      _fetchProxies();
    }
  }

  // 弹出选择节点的对话框
  void _showNodeSelectionDialog(Map<String, dynamic> group) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final allNodes = group['all'] as List<String>;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                '选择 ${group['name']} 的节点',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: allNodes.length,
                itemBuilder: (context, index) {
                  final node = allNodes[index];
                  final isSelected = node == group['now'];
                  return ListTile(
                    title: Text(node, style: TextStyle(
                      color: isSelected ? Colors.blue : null,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    )),
                    trailing: isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
                    onTap: () {
                      Navigator.pop(context); // 关闭弹窗
                      if (!isSelected) {
                        _selectProxy(group['name'], node);
                      }
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
        title: const Text('Nikki 节点控制'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchProxies,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(_errorMessage, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _fetchProxies, child: const Text('重试'))
                      ],
                    ),
                  ),
                )
              : ListView.builder(
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
                ),
    );
  }
}