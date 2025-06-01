import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import '../utils/ui_helper.dart';
import 'package:native_exif/native_exif.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

class ReportViolationScreen extends StatefulWidget {
  const ReportViolationScreen({Key? key}) : super(key: key);

  @override
  _ReportViolationScreenState createState() => _ReportViolationScreenState();
}

class _ReportViolationScreenState extends State<ReportViolationScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _violationController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  bool _isLoading = false;
  bool _hasGpsData = false;
  String _gpsInfo = '';
  DateTime? _imageDateTime; // EXIF에서 추출한 촬영 날짜/시간
  String _imageDateTimeDisplay = ''; // 화면에 표시할 날짜/시간 문자열
  late AnimationController _animationController;
  late Animation<double> _fadeInAnimation;
  
  final List<String> _violationTypes = [
    '안전모 미착용',
    '2인 탑승',
    '기타',
  ];
  
  String? _selectedViolationType;
  
  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    _fadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );
    _animationController.forward();
  }
  
  @override
  void dispose() {
    _violationController.dispose();
    _animationController.dispose();
    super.dispose();
  }
  
  Future<bool> _requestPermissions() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Android 버전에 따른 권한 처리
      if (Platform.isAndroid) {
        // 필요한 권한 목록
        List<Permission> permissions = [
          Permission.storage,
          Permission.photos,
          Permission.location,
          Permission.locationWhenInUse,
        ];
        
        // Android 10 이상에서만 필요한 ACCESS_MEDIA_LOCATION 권한 추가
        try {
          permissions.add(Permission.accessMediaLocation);
        } catch (e) {
          print("ACCESS_MEDIA_LOCATION 권한은 이 Android 버전에서 사용할 수 없습니다: $e");
        }

        // 권한 요청 및 확인
        bool allGranted = true;
        
        // 스토리지 권한 요청
        PermissionStatus storageStatus = await Permission.storage.request();
        if (!storageStatus.isGranted) {
          print("스토리지 권한 거부됨: $storageStatus");
          allGranted = false;
        }
        
        // 사진 권한 요청
        PermissionStatus photosStatus = await Permission.photos.request();
        if (!photosStatus.isGranted) {
          print("사진 권한 거부됨: $photosStatus");
          allGranted = false;
        }
        
        // 위치 권한 요청
        PermissionStatus locationStatus = await Permission.location.request();
        if (!locationStatus.isGranted) {
          print("위치 권한 거부됨: $locationStatus");
          allGranted = false;
        }
        
        // ACCESS_MEDIA_LOCATION 권한 요청 (Android 10 이상)
        try {
          PermissionStatus mediaLocationStatus = await Permission.accessMediaLocation.request();
          if (!mediaLocationStatus.isGranted) {
            print("미디어 위치 권한 거부됨: $mediaLocationStatus");
            print("경고: ACCESS_MEDIA_LOCATION 권한이 없으면 Android 10 이상에서 GPS 정보가 제한될 수 있습니다.");
          }
        } catch (e) {
          print("ACCESS_MEDIA_LOCATION 권한 요청 오류: $e");
        }

        return allGranted;
      } else if (Platform.isIOS) {
        // iOS 권한 처리
        PermissionStatus photosStatus = await Permission.photos.request();
        PermissionStatus locationStatus = await Permission.location.request();
        return photosStatus.isGranted && locationStatus.isGranted;
      }
      
      return false;
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 현재 위치 가져오기
  Future<Position?> _getCurrentLocation() async {
    try {
      // 위치 서비스 활성화 확인
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        UIHelper.showWarningSnackBar(
          context,
          message: '위치 서비스가 비활성화되어 있습니다. 설정에서 위치 서비스를 켜주세요.',
        );
        return null;
      }

      // 위치 권한 확인
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          UIHelper.showWarningSnackBar(
            context,
            message: '위치 권한이 거부되었습니다.',
          );
          return null;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        UIHelper.showErrorSnackBar(
          context,
          message: '위치 권한이 영구적으로 거부되었습니다. 설정에서 권한을 허용해주세요.',
        );
        return null;
      }

      // 현재 위치 가져오기
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      print('위치 가져오기 오류: $e');
      return null;
    }
  }

  // EXIF 데이터에서 GPS 정보와 촬영 날짜/시간 추출
  Future<bool> _extractExifData(File imageFile) async {
    try {
      // Exif 인스턴스 생성
      final exif = await Exif.fromPath(imageFile.path);
      
      // GPS 좌표 가져오기
      final coordinates = await exif.getLatLong();
      
      // 촬영 날짜/시간 가져오기
      final attributes = await exif.getAttributes();
      DateTime? dateTime;
      
      // DateTime 태그들을 순서대로 확인
      if (attributes != null) {
        // DateTime 관련 태그들 확인
        List<String> dateTimeTags = [
          'DateTime',
          'DateTimeOriginal', 
          'DateTimeDigitized',
          'GPS DateStamp'
        ];
        
        for (String tag in dateTimeTags) {
          if (attributes.containsKey(tag) && attributes[tag] != null) {
            try {
              String dateTimeStr = attributes[tag].toString();
              // EXIF 날짜 형식: "YYYY:MM:DD HH:MM:SS"
              dateTime = DateFormat('yyyy:MM:dd HH:mm:ss').parse(dateTimeStr);
              print('EXIF에서 추출한 날짜: $dateTimeStr -> $dateTime');
              break;
            } catch (e) {
              print('날짜 파싱 오류 ($tag): $e');
              continue;
            }
          }
        }
      }
      
      // GPS 정보 저장
      bool hasValidGps = false;
      if (coordinates != null) {
        _gpsInfo = '위도: ${coordinates.latitude.toStringAsFixed(6)}, 경도: ${coordinates.longitude.toStringAsFixed(6)}';
        
        // 경도/위도가 실제 존재하고 유효한지 확인
        hasValidGps = coordinates.latitude != 0 && coordinates.longitude != 0;
      } else {
        // GPS 정보가 없는 경우 상세 정보 저장
        if (attributes != null) {
          bool hasGpsData = attributes.keys.any((key) => key.contains('GPS'));
          if (hasGpsData) {
            _gpsInfo = '이미지에 GPS 태그가 있지만 유효한 좌표를 추출할 수 없습니다.';
          } else {
            _gpsInfo = '이미지에 GPS 정보가 없습니다';
          }
        } else {
          _gpsInfo = '이미지에 EXIF 데이터가 없거나 추출할 수 없습니다';
        }
      }
      
      // 촬영 날짜/시간 저장
      setState(() {
        _imageDateTime = dateTime;
        if (dateTime != null) {
          _imageDateTimeDisplay = DateFormat('yyyy년 MM월 dd일 HH:mm:ss').format(dateTime);
        } else {
          _imageDateTimeDisplay = '촬영 날짜 정보를 찾을 수 없습니다';
        }
      });
      
      // Exif 인터페이스 닫기
      await exif.close();
      
      return hasValidGps;
    } catch (e) {
      _gpsInfo = 'EXIF 데이터 읽기 오류: $e';
      setState(() {
        _imageDateTime = null;
        _imageDateTimeDisplay = 'EXIF 데이터 읽기 오류: $e';
      });
      return false;
    }
  }
  
  // 이미지 선택 메서드
  Future<void> _pickImage(ImageSource source) async {
    try {
      // 권한 요청
      bool permissionsGranted = await _requestPermissions();
      
      if (!permissionsGranted) {
        UIHelper.showWarningSnackBar(
          context,
          message: '일부 권한이 거부되었습니다. 설정에서 권한을 허용해주세요.',
        );
        // 권한이 일부 없어도 계속 진행 (일부 기기에서는 작동할 수 있음)
      }
      
      // 카메라로 촬영하는 경우 현재 위치 먼저 가져오기
      Position? currentPosition;
      if (source == ImageSource.camera) {
        setState(() {
          _isLoading = true;
        });
        
        currentPosition = await _getCurrentLocation();
        
        setState(() {
          _isLoading = false;
        });
      }
      
      // 이미지 선택기 호출
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1800,
        maxHeight: 1800,
        requestFullMetadata: true, // Android 10 이상에서는 이 옵션이 중요
      );
      
      if (pickedFile != null) {
        final imageFile = File(pickedFile.path);
        
        // 로딩 상태 업데이트
        setState(() {
          _isLoading = true;
        });
        
        // EXIF 데이터에서 GPS 정보와 촬영 날짜/시간 추출
        bool hasGpsData = await _extractExifData(imageFile);
        
        // 카메라로 촬영한 경우이고 EXIF에 GPS 정보가 없으면 현재 위치 사용
        if (source == ImageSource.camera && !hasGpsData && currentPosition != null) {
          hasGpsData = true;
          _gpsInfo = '위도: ${currentPosition.latitude.toStringAsFixed(6)}, 경도: ${currentPosition.longitude.toStringAsFixed(6)}';
        }
        
        // 촬영 날짜/시간이 없는 경우 현재 시간 사용 (카메라로 촬영한 경우)
        if (source == ImageSource.camera && _imageDateTime == null) {
          setState(() {
            _imageDateTime = DateTime.now();
            _imageDateTimeDisplay = DateFormat('yyyy년 MM월 dd일 HH:mm:ss').format(_imageDateTime!);
          });
        }
        
        setState(() {
          _imageFile = imageFile;
          _hasGpsData = hasGpsData;
          _isLoading = false;
        });
        
        // GPS 정보가 없으면 경고 메시지 표시
        if (!hasGpsData) {
          UIHelper.showWarningSnackBar(
            context,
            message: 'GPS 정보가 없는 이미지입니다. GPS 정보가 포함된 이미지를 사용해주세요.',
          );
        } else {
          UIHelper.showSuccessSnackBar(
            context, 
            message: 'GPS 정보가 확인되었습니다: $_gpsInfo',
          );
        }
        
        // 촬영 날짜/시간 정보 표시
        if (_imageDateTime != null) {
          UIHelper.showSuccessSnackBar(
            context,
            message: '촬영 날짜: $_imageDateTimeDisplay',
          );
        } else {
          UIHelper.showWarningSnackBar(
            context,
            message: '촬영 날짜 정보를 찾을 수 없습니다. 현재 시간으로 대체됩니다.',
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      UIHelper.showErrorSnackBar(
        context,
        message: '이미지 선택 중 오류가 발생했습니다: $e',
      );
    }
  }
  
  // 위치 정보 문자열에서 좌표 추출
  GeoPoint? _extractCoordinates(String locationText) {
    try {
      // "위도: 37.123456, 경도: 127.123456" 형식에서 숫자만 추출
      RegExp latRegex = RegExp(r'위도:\s*([-+]?\d*\.\d+)');
      RegExp lngRegex = RegExp(r'경도:\s*([-+]?\d*\.\d+)');
      
      Match? latMatch = latRegex.firstMatch(locationText);
      Match? lngMatch = lngRegex.firstMatch(locationText);
      
      if (latMatch != null && lngMatch != null) {
        double latitude = double.parse(latMatch.group(1)!);
        double longitude = double.parse(lngMatch.group(1)!);
        return GeoPoint(latitude, longitude);
      }
      
      return null;
    } catch (e) {
      print('좌표 추출 오류: $e');
      return null;
    }
  }
  
  // 카메라 설정 가이드 대화상자
  void _showCameraSettingsGuide() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('카메라 GPS 설정 방법'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '카메라로 찍은 사진에 GPS 정보가 포함되지 않는 경우:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildGuideStep('1', '기기의 기본 카메라 앱을 엽니다.'),
                _buildGuideStep('2', '카메라 설정 메뉴로 이동합니다 (일반적으로 화면의 상단이나 설정 아이콘을 탭하세요).'),
                _buildGuideStep('3', '"위치 태그" 또는 "위치 정보 저장" 옵션을 찾아 활성화합니다.'),
                _buildGuideStep('4', '기기 설정에서 위치 서비스가 켜져 있는지 확인하세요.'),
                const SizedBox(height: 12),
                const Text(
                  '주요 제조사별 설정 방법:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildManufacturerGuide('삼성', '카메라 앱 → 설정 → 위치 태그'),
                _buildManufacturerGuide('LG', '카메라 앱 → 설정 → 위치 정보 저장'),
                _buildManufacturerGuide('픽셀/구글', '카메라 앱 → 설정 → 위치 저장'),
                _buildManufacturerGuide('아이폰', '설정 → 개인 정보 보호 → 위치 서비스 → 카메라 → "앱을 사용하는 동안"으로 설정'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '실내에서는 GPS 신호가 약해 위치 정보가 저장되지 않을 수 있습니다. 가능하면 실외에서 촬영하세요.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }
  
  // 가이드 단계 위젯
  Widget _buildGuideStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
  
  // 제조사별 가이드 위젯
  Widget _buildManufacturerGuide(String manufacturer, String instruction) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              manufacturer,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(instruction)),
        ],
      ),
    );
  }
  
  // 앱 설정으로 이동하는 함수
  void _openAppSettings() {
    openAppSettings();
  }
  
  // 신고 제출 메서드
  Future<void> _submitReport() async {
    if (_formKey.currentState!.validate()) {
      // 폼 검증 성공
      if (_imageFile == null) {
        UIHelper.showWarningSnackBar(
          context,
          message: '이미지를 첨부해주세요',
        );
        return;
      }
      
      // GPS 정보 확인
      if (!_hasGpsData) {
        UIHelper.showErrorSnackBar(
          context,
          message: 'GPS 정보가 없는 이미지입니다. GPS 정보가 포함된 이미지를 사용해주세요.',
        );
        return;
      }
      
      setState(() {
        _isLoading = true;
      });
      
      try {
        // 현재 사용자 가져오기
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          UIHelper.showErrorSnackBar(
            context,
            message: '로그인이 필요합니다',
          );
          setState(() {
            _isLoading = false;
          });
          return;
        }
        
        String? imageUrl;
        
        // 이미지 업로드
        if (_imageFile != null) {
          // 파일 이름 생성 (타임스탬프 사용)
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final imageName = 'violation_reports/${user.uid}_$timestamp.jpg';
          
          // Firebase Storage에 이미지 업로드
          final storageRef = FirebaseStorage.instance.ref().child(imageName);
          final uploadTask = storageRef.putFile(_imageFile!);
          
          // 업로드 진행 상황을 사용자에게 보여줄 수 있음
          uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
            final progress = snapshot.bytesTransferred / snapshot.totalBytes;
            print('Upload progress: $progress');
            // 여기서 진행 막대를 업데이트할 수 있음
          });
          
          final snapshot = await uploadTask;
          
          // 업로드된 이미지의 URL 가져오기
          imageUrl = await snapshot.ref.getDownloadURL();
        }
        
        // 위반 사항 텍스트 준비
        final violationText = _selectedViolationType == '기타' 
            ? _violationController.text.trim() 
            : _selectedViolationType ?? _violationController.text.trim();
        
        // 유저별 컬렉션에 데이터 저장
        // 먼저 users 컬렉션 아래에 유저 ID로 문서 생성 (없으면)
        final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
        
        // 촬영 날짜/시간이 없으면 현재 시간 사용
        DateTime finalDateTime = _imageDateTime ?? DateTime.now();
        
        // 리포트 데이터 생성
        final reportData = {
          'userId': user.uid,
          'userEmail': user.email,
          'date': Timestamp.fromDate(finalDateTime), // EXIF에서 추출한 촬영 날짜/시간을 타임스탬프로 저장
          'violation': violationText,
          'imageUrl': imageUrl,
          'hasGpsData': _hasGpsData, // GPS 정보 유무 저장
          'gpsInfo': _gpsInfo,       // 구체적인 GPS 정보 저장
          'status': 'submitted',     // 처리 상태
          'createdAt': FieldValue.serverTimestamp(), // 신고 생성 시간
        };
        
        // 유저 문서 내의 reports 하위 컬렉션에 리포트 추가
        await userDocRef.collection('reports').add(reportData);
        
        // 전체 리포트 컬렉션에도 동일한 데이터 저장 (검색 및 관리 목적)
        await FirebaseFirestore.instance.collection('all_reports').add(reportData);
        
        // 성공 메시지 표시
        if (mounted) {
          UIHelper.showSuccessSnackBar(
            context,
            message: '신고가 성공적으로 제출되었습니다',
          );
          
          // 폼 초기화 및 이미지 리셋 (성공 애니메이션과 함께)
          _resetForm();
        }
      } catch (e) {
        // 오류 처리
        if (mounted) {
          UIHelper.showErrorSnackBar(
            context,
            message: '신고 제출 중 오류가 발생했습니다: $e',
          );
        }
      } finally {
        // 로딩 상태 해제
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }
  
  // 폼 초기화 메서드
  void _resetForm() {
    _violationController.clear();
    setState(() {
      _selectedViolationType = null;
      _imageFile = null;
      _hasGpsData = false;
      _gpsInfo = '';
      _imageDateTime = null;
      _imageDateTimeDisplay = '';
    });
    
    // 애니메이션 효과 재생
    _animationController.reset();
    _animationController.forward();
  }

  // 미리보기 대화상자 표시
  void _showPreviewDialog() {
    if (_formKey.currentState!.validate() && _imageFile != null) {
      // GPS 정보 확인
      if (!_hasGpsData) {
        UIHelper.showErrorSnackBar(
          context,
          message: 'GPS 정보가 없는 이미지입니다. GPS 정보가 포함된 이미지를 사용해주세요.',
        );
        return;
      }
      
      final violationText = _selectedViolationType == '기타' 
          ? _violationController.text.trim() 
          : _selectedViolationType ?? _violationController.text.trim();
      
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: _imageFile != null
                      ? Image.file(
                          _imageFile!,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: double.infinity,
                          height: 200,
                          color: Colors.grey[300],
                          child: const Icon(Icons.image, size: 50, color: Colors.grey),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '신고 내용 확인',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildPreviewItem('촬영 날짜', _imageDateTimeDisplay.isNotEmpty ? _imageDateTimeDisplay : '촬영 날짜 정보 없음'),
                      _buildPreviewItem('위반 사항', violationText),
                      _buildPreviewItem('GPS 정보', _hasGpsData ? _gpsInfo : '없음'),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: const Text('취소'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _submitReport();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('신고하기'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    } else {
      UIHelper.showWarningSnackBar(
        context,
        message: '모든 필드를 입력하고 이미지를 첨부해주세요',
      );
    }
  }
  
  // 미리보기 항목 위젯
  Widget _buildPreviewItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('위반 사항 신고하기', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.black),
            onPressed: () {
              _showHelpDialog();
            },
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeInAnimation,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 촬영 날짜/시간 정보 표시 (EXIF에서 추출)
                  if (_imageFile != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: _imageDateTime != null 
                            ? Colors.green.withOpacity(0.1) 
                            : Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _imageDateTime != null 
                              ? Colors.green 
                              : Colors.orange,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _imageDateTime != null 
                                    ? Icons.schedule 
                                    : Icons.warning_amber,
                                color: _imageDateTime != null 
                                    ? Colors.green 
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '촬영 날짜/시간',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _imageDateTime != null 
                                      ? Colors.green 
                                      : Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _imageDateTimeDisplay.isNotEmpty 
                                ? _imageDateTimeDisplay 
                                : '이미지를 선택하면 촬영 날짜가 표시됩니다',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  
                  Row(
                    children: [
                      const Text('이미지 첨부', style: TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      _imageFile != null ? 
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _hasGpsData ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _hasGpsData ? Colors.green : Colors.red,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _hasGpsData ? Icons.check_circle : Icons.error,
                              size: 16,
                              color: _hasGpsData ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _hasGpsData ? 'GPS 정보 포함' : 'GPS 정보 없음',
                              style: TextStyle(
                                fontSize: 12,
                                color: _hasGpsData ? Colors.green : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ) : const SizedBox(),
                      const SizedBox(width: 8),
                      if (!_hasGpsData && _imageFile != null)
                        TextButton.icon(
                          onPressed: _openAppSettings,
                          icon: const Icon(Icons.settings, size: 16),
                          label: const Text('권한 설정'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.blue,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (context) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 16),
                              const Text(
                                '이미지 선택',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.camera_alt, color: Colors.blue),
                                ),
                                title: const Text('카메라로 촬영'),
                                subtitle: const Text('GPS 정보와 촬영 날짜가 자동으로 기록됩니다'),
                                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                                onTap: () {
                                  Navigator.pop(context);
                                  _pickImage(ImageSource.camera);
                                },
                              ),
                              ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.photo_library, color: Colors.green),
                                ),
                                title: const Text('갤러리에서 선택'),
                                subtitle: const Text('GPS 정보와 촬영 날짜가 포함된 이미지를 선택해 주세요'),
                                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                                onTap: () {
                                  Navigator.pop(context);
                                  _pickImage(ImageSource.gallery);
                                },
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, size: 14, color: Colors.grey[700]),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '* 위치 정보 권한을 허용해야 정확한 GPS 정보를 얻을 수 있습니다.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[700],
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                                child: TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _showCameraSettingsGuide();
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.deepOrange,
                                    padding: EdgeInsets.zero,
                                    alignment: Alignment.centerLeft,
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    '카메라 GPS 설정 방법 알아보기 >',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 200,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _imageFile != null 
                              ? (_hasGpsData ? Colors.green : Colors.red)
                              : Colors.grey,
                          width: _imageFile != null ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: _imageFile != null
                            ? [
                                BoxShadow(
                                  color: _hasGpsData 
                                      ? Colors.green.withOpacity(0.2)
                                      : Colors.red.withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: _imageFile != null
                          ? Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(11),
                                  child: Image.file(
                                    _imageFile!,
                                    width: double.infinity,
                                    height: 200,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  right: 8,
                                  top: 8,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _imageFile = null;
                                        _hasGpsData = false;
                                        _imageDateTime = null;
                                        _imageDateTimeDisplay = '';
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.7),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.red,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                                if (!_hasGpsData)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.8),
                                      ),
                                      child: const Text(
                                        'GPS 정보가 없습니다. 다른 이미지를 선택해주세요.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            )
                          : const Center(
                         child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.camera_alt, size: 50, color: Colors.grey),
                                  SizedBox(height: 8),
                                  Text(
                                    'GPS 정보와 촬영 날짜가 포함된 이미지를 선택해주세요',
                                    style: TextStyle(color: Colors.grey),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    '카메라 앱의 위치 정보 저장 기능을 켜고 촬영하세요',
                                    style: TextStyle(color: Colors.grey, fontSize: 12),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('위반 사항', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  
                  // 위반 사항 선택 드롭다운
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.grey,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                      color: Colors.white,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButtonFormField<String>(
                        value: _selectedViolationType,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        hint: const Text('위반 사항 유형 선택'),
                        items: _violationTypes.map((String type) {
                          return DropdownMenuItem<String>(
                            value: type,
                            child: Text(type),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedViolationType = newValue;
                          });
                        },
                        validator: (value) {
                          if (value == null && _violationController.text.isEmpty) {
                            return '위반 사항을 선택하거나 입력해주세요';
                          }
                          return null;
                        },
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 기타 위반 사항일 경우 상세 설명 필드 표시
                  if (_selectedViolationType == '기타' || _selectedViolationType == null)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextFormField(
                        controller: _violationController,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.orange, width: 2),
                          ),
                          hintText: _selectedViolationType == '기타' 
                              ? '위반사항을 상세히 입력해주세요' 
                              : '위반사항을 입력해주세요',
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        maxLines: 3,
                        validator: (value) {
                          if (_selectedViolationType == '기타' && (value == null || value.isEmpty)) {
                            return '위반 사항을 입력해주세요';
                          }
                          if (_selectedViolationType == null && (value == null || value.isEmpty)) {
                            return '위반 사항을 선택하거나 입력해주세요';
                          }
                          return null;
                        },
                      ),
                    ),
                  
                  const SizedBox(height: 24),
                  
                  // GPS 정보 관련 안내 메시지
                  if (_imageFile != null && !_hasGpsData)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.red),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'GPS 정보가 포함된 이미지가 필요합니다.',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '다음을 확인해보세요:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          const Text('• 카메라 앱에서 위치 정보 저장 기능이 켜져 있는지 확인하세요.'),
                          const Text('• 앱 설정에서 위치 접근 권한이 허용되어 있는지 확인하세요.'),
                          const Text('• 직접 촬영한 사진을 사용하면 GPS 정보가 더 정확합니다.'),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: _openAppSettings,
                                icon: const Icon(Icons.settings, size: 16),
                                label: const Text('권한 설정'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  
                  // 신고하기 전 미리보기 버튼
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeInOut,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Opacity(
                          opacity: value,
                          child: child,
                        ),
                      );
                    },
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (_isLoading || (_imageFile != null && !_hasGpsData)) 
                            ? null 
                            : _showPreviewDialog,
                        icon: const Icon(Icons.preview),
                        label: const Text('미리보기 및 신고하기'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 3,
                          // 버튼 비활성화 스타일
                          disabledBackgroundColor: Colors.grey,
                          disabledForegroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  // 도움말 대화상자
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '신고 방법 안내',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '1. 이미지 첨부: 위반 사항을 확인할 수 있는 사진을 첨부하세요. GPS 정보와 촬영 날짜가 포함된 이미지만 사용 가능합니다.',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '   * 카메라로 촬영 시: 기기의 카메라 앱 설정에서 "위치 태그" 또는 "위치 정보 저장" 기능이 켜져 있어야 합니다.',
                          style: TextStyle(fontSize: 12, color: Colors.deepOrange),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '   * 갤러리에서 선택 시: 촬영 당시 위치 정보와 날짜가 저장된 사진을 선택하세요.',
                          style: TextStyle(fontSize: 12, color: Colors.deepOrange),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '2. 위반 사항 선택: 위반 사항의 유형을 선택하거나, \'기타\'를 선택한 경우 상세 내용을 입력하세요.',
                          style: TextStyle(fontSize: 14),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '3. 미리보기 및 신고: 입력한 내용을 미리보기로 확인한 후 신고하세요.',
                          style: TextStyle(fontSize: 14),
                        ),
                        SizedBox(height: 16),
                        Text(
                          '※ 촬영 날짜와 시간은 이미지의 EXIF 데이터에서 자동으로 추출됩니다.',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '※ GPS 정보가 없는 이미지는 신고가 불가능합니다. 꼭 GPS 정보가 포함된 이미지를 사용해 주세요.',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '※ 허위 신고나 악의적인 신고는 법적 책임이 따를 수 있습니다.',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('확인'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}