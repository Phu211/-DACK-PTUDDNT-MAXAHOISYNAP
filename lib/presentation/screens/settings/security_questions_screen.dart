import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../data/services/security_questions_service.dart';

/// Màn hình quản lý Security Questions
class SecurityQuestionsScreen extends StatefulWidget {
  const SecurityQuestionsScreen({super.key});

  @override
  State<SecurityQuestionsScreen> createState() =>
      _SecurityQuestionsScreenState();
}

class _SecurityQuestionsScreenState extends State<SecurityQuestionsScreen> {
  final SecurityQuestionsService _securityQuestionsService =
      SecurityQuestionsService();
  bool _isLoading = false;
  bool _isSetup = false;
  List<String> _questionIds = [];
  Map<String, String> _selectedQuestions = {};
  Map<String, TextEditingController> _answerControllers = {};

  @override
  void initState() {
    super.initState();
    _checkSetupStatus();
  }

  @override
  void dispose() {
    for (final controller in _answerControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _checkSetupStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final isSetup = await _securityQuestionsService.isSecurityQuestionsSetup(
        user.uid,
      );
      final questionIds = await _securityQuestionsService
          .getUserSecurityQuestionIds(user.uid);

      if (mounted) {
        setState(() {
          _isSetup = isSetup;
          _questionIds = questionIds;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _setupSecurityQuestions() async {
    if (_selectedQuestions.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn ít nhất 2 câu hỏi'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Kiểm tra tất cả câu trả lời đã được nhập
    for (final questionId in _selectedQuestions.keys) {
      final controller = _answerControllers[questionId];
      if (controller == null || controller.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vui lòng nhập đầy đủ câu trả lời'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final questions = <String, String>{};
      for (final entry in _selectedQuestions.entries) {
        final controller = _answerControllers[entry.key];
        if (controller != null) {
          questions[entry.key] = controller.text.trim();
        }
      }

      await _securityQuestionsService.setupSecurityQuestions(
        user.uid,
        questions,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _checkSetupStatus();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã thiết lập Security Questions thành công'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi thiết lập: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showQuestionSelector() async {
    final availableQuestions = SecurityQuestionsService.defaultQuestions;
    final selected = Map<String, String>.from(_selectedQuestions);

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chọn câu hỏi bảo mật'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: availableQuestions.length,
            itemBuilder: (context, index) {
              final question = availableQuestions[index];
              final questionId = 'q${index + 1}';
              final isSelected = selected.containsKey(questionId);

              return CheckboxListTile(
                title: Text(question),
                value: isSelected,
                onChanged: (value) {
                  if (value == true) {
                    selected[questionId] = question;
                  } else {
                    selected.remove(questionId);
                  }
                  setState(() {
                    _selectedQuestions = selected;
                  });
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx, selected);
              setState(() {
                _selectedQuestions = selected;
                // Tạo controllers cho các câu hỏi mới
                for (final questionId in selected.keys) {
                  if (!_answerControllers.containsKey(questionId)) {
                    _answerControllers[questionId] = TextEditingController();
                  }
                }
                // Xóa controllers cho các câu hỏi đã bỏ chọn
                final toRemove = <String>[];
                for (final questionId in _answerControllers.keys) {
                  if (!selected.containsKey(questionId)) {
                    toRemove.add(questionId);
                  }
                }
                for (final questionId in toRemove) {
                  _answerControllers[questionId]?.dispose();
                  _answerControllers.remove(questionId);
                }
              });
            },
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        _selectedQuestions = result;
      });
    }
  }

  Future<void> _deleteSecurityQuestions() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa Security Questions'),
        content: const Text(
          'Bạn có chắc chắn muốn xóa Security Questions? '
          'Bạn sẽ không thể sử dụng chúng để khôi phục tài khoản.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _securityQuestionsService.deleteSecurityQuestions(user.uid);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSetup = false;
          _selectedQuestions.clear();
          for (final controller in _answerControllers.values) {
            controller.dispose();
          }
          _answerControllers.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã xóa Security Questions'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xóa: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security Questions')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _isSetup
                                  ? Icons.check_circle
                                  : Icons.help_outline,
                              color: _isSetup ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isSetup
                                  ? 'Đã thiết lập Security Questions'
                                  : 'Chưa thiết lập',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _isSetup ? Colors.green : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isSetup
                              ? 'Bạn đã thiết lập Security Questions để khôi phục tài khoản.'
                              : 'Thiết lập Security Questions để có thể khôi phục tài khoản khi quên mật khẩu.',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!_isSetup) ...[
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _showQuestionSelector,
                    icon: const Icon(Icons.add),
                    label: const Text('Chọn câu hỏi bảo mật'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  if (_selectedQuestions.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Câu hỏi đã chọn',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._selectedQuestions.entries.map((entry) {
                      final questionId = entry.key;
                      final question = entry.value;
                      final controller =
                          _answerControllers[questionId] ??
                          TextEditingController();
                      if (!_answerControllers.containsKey(questionId)) {
                        _answerControllers[questionId] = controller;
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                question,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: controller,
                                decoration: const InputDecoration(
                                  hintText: 'Nhập câu trả lời',
                                  border: OutlineInputBorder(),
                                  labelText: 'Câu trả lời',
                                ),
                                obscureText: true,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    ElevatedButton(
                      onPressed: _setupSecurityQuestions,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Lưu Security Questions'),
                    ),
                  ],
                ] else ...[
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Câu hỏi đã thiết lập',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ..._questionIds.asMap().entries.map((entry) {
                            final index = entry.key;
                            final questionId = entry.value;
                            final questionIndex = int.tryParse(
                              questionId.replaceAll('q', ''),
                            ) ?? 0;
                            final question = (questionIndex >= 0 &&
                                    questionIndex <
                                        SecurityQuestionsService
                                            .defaultQuestions.length)
                                ? SecurityQuestionsService
                                    .defaultQuestions[questionIndex]
                                : 'Câu hỏi không xác định';

                            return ListTile(
                              leading: CircleAvatar(
                                child: Text('${index + 1}'),
                              ),
                              title: Text(question),
                              subtitle: const Text('••••••••'),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _deleteSecurityQuestions,
                    icon: const Icon(Icons.delete),
                    label: const Text('Xóa Security Questions'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lưu ý',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• Chọn ít nhất 2 câu hỏi bảo mật\n'
                          '• Câu trả lời phải chính xác để khôi phục tài khoản\n'
                          '• Không chia sẻ câu trả lời với ai\n'
                          '• Chọn câu hỏi mà chỉ bạn biết câu trả lời',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
