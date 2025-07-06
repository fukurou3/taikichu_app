import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/countdown.dart';
import '../services/countdown_service.dart';

class CreateCountdownScreen extends StatefulWidget {
  final String? preFilledEventName;
  final String? preFilledCategory;
  final DateTime? preFilledEventDate;

  const CreateCountdownScreen({
    super.key,
    this.preFilledEventName,
    this.preFilledCategory,
    this.preFilledEventDate,
  });

  @override
  State<CreateCountdownScreen> createState() => _CreateCountdownScreenState();
}

class _CreateCountdownScreenState extends State<CreateCountdownScreen> {
  final _formKey = GlobalKey<FormState>();
  final _eventNameController = TextEditingController();
  DateTime? _selectedDate;
  String? _selectedCategory;
  final List<String> _categories = [
    'ゲーム',
    '音楽',
    'アニメ',
    'ライブ',
    '推し活',
    'その他'
  ];

  @override
  void initState() {
    super.initState();
    // 事前入力データがあれば設定
    if (widget.preFilledEventName != null) {
      _eventNameController.text = widget.preFilledEventName!;
    }
    if (widget.preFilledCategory != null) {
      _selectedCategory = widget.preFilledCategory;
    }
    if (widget.preFilledEventDate != null) {
      _selectedDate = widget.preFilledEventDate;
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _createCountdown() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('イベント日時を選択してください。')),
        );
        return;
      }
      if (_selectedCategory == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('カテゴリを選択してください。')),
        );
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('カウントダウンを作成するにはログインが必要です。')),
        );
        return;
      }

      try {
        final newCountdown = Countdown(
          id: '',
          eventName: _eventNameController.text,
          eventDate: _selectedDate!,
          category: _selectedCategory!,
          creatorId: user.uid,
          participantsCount: 1,
        );

        await CountdownService.addCountdown(newCountdown);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('カウントダウンが作成されました！')),
        );
        Navigator.pop(context);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('カウントダウン作成に失敗しました: $e')),
        );
        print(e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新しいカウントダウンを作成'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                controller: _eventNameController,
                decoration: const InputDecoration(
                  labelText: 'イベント名',
                  hintText: '例: 〇〇発売日、〇〇誕生日ライブ',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'イベント名を入力してください';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              ListTile(
                title: Text(
                  _selectedDate == null
                      ? 'イベント日時を選択'
                      : 'イベント日時: ${_selectedDate!.toLocal().toString().split(' ')[0]}',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () => _selectDate(context),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                hint: const Text('カテゴリを選択'),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'カテゴリ',
                ),
                items: _categories.map((String category) {
                  return DropdownMenuItem<String>(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedCategory = newValue;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'カテゴリを選択してください';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _createCountdown,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'カウントダウンを作成',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}