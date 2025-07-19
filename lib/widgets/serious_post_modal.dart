import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dropdown_search/dropdown_search.dart';
import '../models/post_models.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/location_service.dart';
import '../constants/japan_municipalities.dart';
import 'login_modal.dart';
import 'map_picker_widget.dart';

class SeriousPostModal extends StatefulWidget {
  const SeriousPostModal({super.key});

  @override
  State<SeriousPostModal> createState() => _SeriousPostModalState();
}

class _SeriousPostModalState extends State<SeriousPostModal> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  bool _isPosting = false;
  
  String? _selectedMunicipality;
  LocationType _locationType = LocationType.municipality;
  LatLng? _selectedCoordinates;
  String? _detectedLocation;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(() => setState(() {}));
    _contentController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _showLoginModal() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const LoginModal(),
    );
    
    if (result == true) {
      _postSerious();
    }
  }

  Future<void> _postSerious() async {
    if (_titleController.text.trim().isEmpty || _contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('タイトルと内容を入力してください')),
      );
      return;
    }
    
    if (!AuthService.isLoggedIn) {
      _showLoginModal();
      return;
    }
    
    setState(() => _isPosting = true);
    try {
      await FirestoreService.createSeriousPost(
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        locationType: _locationType,
        municipality: _selectedMunicipality,
        latitude: _selectedCoordinates?.latitude,
        longitude: _selectedCoordinates?.longitude,
        detectedLocation: _detectedLocation,
      );
      
      _resetForm();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('投稿しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('投稿に失敗しました: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  void _resetForm() {
    _titleController.clear();
    _contentController.clear();
    setState(() {
      _selectedMunicipality = null;
      _selectedCoordinates = null;
      _detectedLocation = null;
      _locationType = LocationType.municipality;
    });
  }

  void _showMapPicker() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 600,
          height: 500,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('地図で位置を選択', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '地図をクリックして位置を選択してください',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: MapPickerWidget(
                      onLocationSelected: (lat, lng) async {
                        setState(() {
                          _selectedCoordinates = LatLng(lat, lng);
                          _detectedLocation = null;
                        });
                        Navigator.pop(context);
                        
                        // 住所を自動検出
                        try {
                          final location = await LocationService.getLocationFromCoordinates(lat, lng);
                          setState(() {
                            _detectedLocation = location;
                          });
                          print('検出された住所: $location');
                        } catch (e) {
                          print('住所検出エラー: $e');
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '真剣投稿',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: StreamBuilder(
                  stream: AuthService.authStateChanges,
                  builder: (context, snapshot) {
                    final isLoggedIn = snapshot.hasData;
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _titleController,
                          decoration: InputDecoration(
                            hintText: isLoggedIn ? 'タイトル（例：○○の仲間募集、△△の課題報告）' : 'ログインして投稿',
                            border: const OutlineInputBorder(),
                            labelText: 'タイトル',
                          ),
                          onTap: isLoggedIn ? null : _showLoginModal,
                          readOnly: !isLoggedIn,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _contentController,
                          maxLines: 5,
                          decoration: InputDecoration(
                            hintText: isLoggedIn ? '詳細な内容を記入してください' : 'ログインして投稿',
                            border: const OutlineInputBorder(),
                            labelText: '内容',
                          ),
                          onTap: isLoggedIn ? null : _showLoginModal,
                          readOnly: !isLoggedIn,
                        ),
                        const SizedBox(height: 16),
                        
                        // 位置情報選択
                        if (isLoggedIn) ...[
                          Text('位置情報', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: RadioListTile<LocationType>(
                                  title: const Text('市区町村'),
                                  value: LocationType.municipality,
                                  groupValue: _locationType,
                                  onChanged: (value) {
                                    setState(() {
                                      _locationType = value!;
                                      _selectedCoordinates = null;
                                    });
                                  },
                                ),
                              ),
                              Expanded(
                                child: RadioListTile<LocationType>(
                                  title: const Text('詳細位置'),
                                  value: LocationType.coordinates,
                                  groupValue: _locationType,
                                  onChanged: (value) {
                                    setState(() {
                                      _locationType = value!;
                                      _selectedMunicipality = null;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          
                          if (_locationType == LocationType.municipality)
                            DropdownSearch<String>(
                              items: japanMunicipalities,
                              selectedItem: _selectedMunicipality,
                              onChanged: (value) {
                                setState(() {
                                  _selectedMunicipality = value;
                                });
                              },
                              dropdownDecoratorProps: const DropDownDecoratorProps(
                                dropdownSearchDecoration: InputDecoration(
                                  labelText: '市区町村を選択',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              popupProps: PopupProps.menu(
                                showSearchBox: true,
                                searchFieldProps: const TextFieldProps(
                                  decoration: InputDecoration(
                                    hintText: '検索...',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            )
                          else
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _showMapPicker(),
                                  icon: const Icon(Icons.map),
                                  label: Text(_selectedCoordinates == null 
                                      ? '地図で位置を選択' 
                                      : '位置選択済み'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _selectedCoordinates == null 
                                        ? Colors.grey[400] 
                                        : Colors.green,
                                  ),
                                ),
                                if (_selectedCoordinates != null && _detectedLocation != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.blue[50],
                                        border: Border.all(color: Colors.blue[200]!),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.location_on, size: 16, color: Colors.blue[600]),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '特定された地域: $_detectedLocation',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.blue[800],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                        
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: (isLoggedIn && 
                                       _titleController.text.trim().isNotEmpty && 
                                       _contentController.text.trim().isNotEmpty && 
                                       !_isPosting) 
                                ? _postSerious 
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange[600],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: _isPosting
                                ? const CircularProgressIndicator(color: Colors.white)
                                : Text(isLoggedIn ? '真剣投稿' : 'ログインして投稿'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}