import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({Key? key}) : super(key: key);

  @override
  _MyReportsScreenState createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _reports = [];
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  // 사용자의 신고 내역 가져오기 - Report와 Conclusion 컬렉션에서 모두 가져오기
  Future<void> _fetchReports() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // 현재 사용자 가져오기
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = '로그인이 필요합니다';
        });
        return;
      }

      // 1. Report 컬렉션에서 처리되지 않은 신고들 가져오기 (최근 신고들)
      final reportQuery = await FirebaseFirestore.instance
          .collection('Report')
          .where('userId', isEqualTo: user.uid)
          .get();

      // 2. Conclusion 컬렉션에서 처리된 신고들 가져오기
      final conclusionQuery = await FirebaseFirestore.instance
          .collection('Conclusion')
          .where('userId', isEqualTo: user.uid)
          .get();

      List<Map<String, dynamic>> allReports = [];

      // Report 컬렉션의 데이터 처리 (아직 처리되지 않은 신고들)
      for (var doc in reportQuery.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        data['source'] = 'Report'; // 어느 컬렉션에서 온 데이터인지 표시
        data['result'] = null; // 아직 처리되지 않음
        allReports.add(data);
      }

      // Conclusion 컬렉션의 데이터 처리 (처리 완료된 신고들)
      for (var doc in conclusionQuery.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        data['source'] = 'Conclusion'; // 어느 컬렉션에서 온 데이터인지 표시
        allReports.add(data);
      }

      // 중복 제거: Conclusion에 있는 것과 같은 신고는 Report에서 제거
      // (같은 이미지 URL이나 같은 시간대의 신고로 판단)
      List<Map<String, dynamic>> uniqueReports = [];
      Set<String> processedImageUrls = {};

      // 먼저 Conclusion 데이터를 추가 (처리된 것들이 우선)
      for (var report in allReports) {
        if (report['source'] == 'Conclusion') {
          uniqueReports.add(report);
          if (report['reportImgUrl'] != null) {
            processedImageUrls.add(report['reportImgUrl'] as String);
          }
        }
      }

      // 그 다음 Report 데이터 중 중복되지 않는 것들만 추가
      for (var report in allReports) {
        if (report['source'] == 'Report') {
          String? imageUrl = report['imageUrl'] as String?;
          if (imageUrl == null || !processedImageUrls.contains(imageUrl)) {
            uniqueReports.add(report);
            if (imageUrl != null) {
              processedImageUrls.add(imageUrl);
            }
          }
        }
      }

      // 클라이언트에서 날짜순으로 정렬 (최신순)
      uniqueReports.sort((a, b) {
        try {
          dynamic dateA = a['date'] ?? a['createdAt'];
          dynamic dateB = b['date'] ?? b['createdAt'];
          
          DateTime parsedDateA;
          DateTime parsedDateB;
          
          if (dateA is Timestamp) {
            parsedDateA = dateA.toDate();
          } else if (dateA is String) {
            parsedDateA = DateTime.parse(dateA);
          } else {
            parsedDateA = DateTime(1970); // 기본값
          }
          
          if (dateB is Timestamp) {
            parsedDateB = dateB.toDate();
          } else if (dateB is String) {
            parsedDateB = DateTime.parse(dateB);
          } else {
            parsedDateB = DateTime(1970); // 기본값
          }
          
          return parsedDateB.compareTo(parsedDateA); // 내림차순 (최신순)
        } catch (e) {
          print('날짜 정렬 오류: $e');
          return 0;
        }
      });

      setState(() {
        _reports = uniqueReports;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '신고 내역을 불러오는 데 실패했습니다: $e';
      });
      print('Error fetching reports: $e');
    }
  }

  // 신고 상태에 따른 배경색 반환
  Color _getStatusColor(String? result) {
    if (result == null) return Colors.grey.withOpacity(0.1);
    
    switch (result) {
      case '승인':
        return Colors.green.withOpacity(0.2);
      case '반려':
        return Colors.red.withOpacity(0.2);
      default:
        return Colors.grey.withOpacity(0.1);
    }
  }

  // 신고 상태 한글 텍스트 반환
  String _getStatusText(String? result) {
    if (result == null) return '검토중';
    
    switch (result) {
      case '승인':
        return '승인됨';
      case '반려':
        return '반려됨';
      default:
        return '검토중';
    }
  }

  // 신고 상태 아이콘 반환
  IconData _getStatusIcon(String? result) {
    if (result == null) return Icons.pending;
    
    switch (result) {
      case '승인':
        return Icons.check_circle;
      case '반려':
        return Icons.cancel;
      default:
        return Icons.pending;
    }
  }

  // 신고 상태 아이콘 색상 반환
  Color _getStatusIconColor(String? result) {
    if (result == null) return Colors.grey;
    
    switch (result) {
      case '승인':
        return Colors.green;
      case '반려':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // 날짜 포맷팅 함수
  String _formatDate(dynamic dateField, Map<String, dynamic> report) {
    try {
      // Report 컬렉션에서 온 경우 createdAt 필드도 확인
      dynamic targetDate = dateField ?? report['createdAt'];
      
      if (targetDate is Timestamp) {
        return DateFormat('yyyy년 MM월 dd일 HH:mm').format(targetDate.toDate());
      } else if (targetDate is String) {
        // 문자열인 경우 그대로 반환하거나 파싱 시도
        try {
          final parsedDate = DateTime.parse(targetDate);
          return DateFormat('yyyy년 MM월 dd일 HH:mm').format(parsedDate);
        } catch (e) {
          return targetDate; // 파싱 실패시 원본 문자열 반환
        }
      } else {
        return '날짜 정보 없음';
      }
    } catch (e) {
      print('날짜 포맷팅 오류: $e');
      return '날짜 정보 없음';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('나의 신고 내역', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black),
            onPressed: _fetchReports,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_errorMessage),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchReports,
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                )
              : _reports.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            '신고 내역이 없습니다',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '첫 번째 신고를 작성해보세요!',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchReports,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16.0),
                        itemCount: _reports.length,
                        itemBuilder: (context, index) {
                          final report = _reports[index];
                          final result = report['result'] as String?;
                          final dateField = report['date'];
                          final formattedDate = _formatDate(dateField, report);
                          final isFromReport = report['source'] == 'Report';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 16.0),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: InkWell(
                              onTap: () => _showReportDetailModal(report, isFromReport),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: _getStatusColor(result),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 이미지가 있다면 표시
                                  if ((isFromReport && report['imageUrl'] != null) || 
                                      (!isFromReport && report['reportImgUrl'] != null))
                                    ClipRRect(
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(12),
                                      ),
                                      child: Image.network(
                                        isFromReport 
                                            ? report['imageUrl'] as String
                                            : report['reportImgUrl'] as String,
                                        width: double.infinity,
                                        height: 200,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            width: double.infinity,
                                            height: 200,
                                            color: Colors.grey[300],
                                            child: const Icon(
                                              Icons.broken_image,
                                              size: 50,
                                              color: Colors.grey,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // 상태 표시 행
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            // 날짜 표시
                                            Expanded(
                                              child: Text(
                                                formattedDate,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ),
                                            // 상태 표시 칩
                                            Chip(
                                              label: Text(
                                                isFromReport ? '검토 대기중' : _getStatusText(result),
                                                style: TextStyle(
                                                  color: isFromReport ? Colors.orange : _getStatusIconColor(result),
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              avatar: Icon(
                                                isFromReport ? Icons.hourglass_empty : _getStatusIcon(result),
                                                color: isFromReport ? Colors.orange : _getStatusIconColor(result),
                                                size: 18,
                                              ),
                                              backgroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 0,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        
                                        // GPS 정보 표시 (gpsInfo 필드에서)
                                        if (report['gpsInfo'] != null)
                                          Row(
                                            children: [
                                              const Icon(Icons.location_on, 
                                                color: Colors.orange, 
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  report['gpsInfo'] as String,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        if (report['gpsInfo'] != null)
                                          const SizedBox(height: 8),
                                        
                                        // 위반 사항 정보
                                        Text(
                                          report['violation'] as String? ?? '위반 사항 정보 없음',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        
                                        // Report 컬렉션에서 온 경우 대기 메시지 표시
                                        if (isFromReport)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 8),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Colors.orange.withOpacity(0.3),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.schedule,
                                                    size: 16,
                                                    color: Colors.orange[700],
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '관리자가 검토 중입니다',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.orange[700],
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        
                                        // 신뢰도 정보 표시 (Conclusion 컬렉션에서만)
                                        // if (!isFromReport && report['confidence'] != null)
                                        //   Padding(
                                        //     padding: const EdgeInsets.only(top: 8),
                                        //     child: Container(
                                        //       padding: const EdgeInsets.symmetric(
                                        //         horizontal: 8,
                                        //         vertical: 4,
                                        //       ),
                                        //       decoration: BoxDecoration(
                                        //         color: Colors.blue.withOpacity(0.1),
                                        //         borderRadius: BorderRadius.circular(8),
                                        //         border: Border.all(
                                        //           color: Colors.blue.withOpacity(0.3),
                                        //         ),
                                        //       ),
                                        //       child: Text(
                                        //         '신뢰도: ${report['confidence']}',
                                        //         style: const TextStyle(
                                        //           fontSize: 12,
                                        //           color: Colors.blue,
                                        //         ),
                                        //       ),
                                        //     ),
                                        //   ),
                                        
                                        // 반려된 경우 반려 사유 표시 (reason 필드)
                                        if (result == '반려' && report['reason'] != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 12),
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Colors.red.withOpacity(0.05),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Colors.red.withOpacity(0.3),
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    '반려 사유:',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    report['reason'] as String,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: Colors.red[700],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  // 신고 상세 정보 모달 표시
  void _showReportDetailModal(Map<String, dynamic> report, bool isFromReport) {
    final result = report['result'] as String?;
    final formattedDate = _formatDate(report['date'], report);
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(10),
          child: Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height * 0.9,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                // 헤더
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _getStatusColor(result),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '신고 상세 정보',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        color: Colors.black54,
                      ),
                    ],
                  ),
                ),
                
                // 내용
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 상태 칩
                        Center(
                          child: Chip(
                            label: Text(
                              isFromReport ? '검토 대기중' : _getStatusText(result),
                              style: TextStyle(
                                color: isFromReport ? Colors.orange : _getStatusIconColor(result),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            avatar: Icon(
                              isFromReport ? Icons.hourglass_empty : _getStatusIcon(result),
                              color: isFromReport ? Colors.orange : _getStatusIconColor(result),
                              size: 20,
                            ),
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // 이미지 (전체 크기)
                        if ((isFromReport && report['imageUrl'] != null) || 
                            (!isFromReport && report['reportImgUrl'] != null))
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: GestureDetector(
                                onTap: () => _showFullScreenImage(
                                  isFromReport 
                                      ? report['imageUrl'] as String
                                      : report['reportImgUrl'] as String
                                ),
                                child: Image.network(
                                  isFromReport 
                                      ? report['imageUrl'] as String
                                      : report['reportImgUrl'] as String,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      width: double.infinity,
                                      height: 200,
                                      color: Colors.grey[300],
                                      child: const Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.broken_image,
                                            size: 50,
                                            color: Colors.grey,
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            '이미지를 불러올 수 없습니다',
                                            style: TextStyle(color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        
                        const SizedBox(height: 24),
                        
                        // 정보 카드들
                        _buildInfoCard('날짜', formattedDate, Icons.schedule),
                        
                        _buildInfoCard(
                          '위반 사항', 
                          report['violation'] as String? ?? '위반 사항 정보 없음',
                          Icons.report_problem,
                        ),
                        
                        // GPS 정보
                        if (report['gpsInfo'] != null)
                          _buildInfoCard(
                            'GPS 정보',
                            report['gpsInfo'] as String,
                            Icons.location_on,
                          ),
                        
                        // 신뢰도 (Conclusion에서만)
                        // if (!isFromReport && report['confidence'] != null)
                        //   _buildInfoCard(
                        //     '신뢰도',
                        //     '${report['confidence']}',
                        //     Icons.verified,
                        //   ),
                        
                        // 대기 중 메시지 (Report에서만)
                        if (isFromReport)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.orange.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.schedule,
                                  color: Colors.orange[700],
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '검토 중',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange[700],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '관리자가 신고 내용을 검토하고 있습니다. 검토가 완료되면 결과를 알려드립니다.',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.orange[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        
                        // 반려 사유 (Conclusion에서 반려된 경우)
                        if (!isFromReport && result == '반려' && report['reason'] != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.red.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.cancel,
                                  color: Colors.red[700],
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '반려 사유',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red[700],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        report['reason'] as String,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.red[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 정보 카드 위젯
  Widget _buildInfoCard(String title, String content, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey[200]!,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: Colors.grey[600],
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 전체 화면 이미지 보기
  void _showFullScreenImage(String imageUrl) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: double.infinity,
              height: double.infinity,
              child: Stack(
                children: [
                  Center(
                    child: InteractiveViewer(
                      panEnabled: true,
                      boundaryMargin: const EdgeInsets.all(20),
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            padding: const EdgeInsets.all(20),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.broken_image,
                                  size: 100,
                                  color: Colors.white54,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  '이미지를 불러올 수 없습니다',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Positioned(
                    top: 40,
                    right: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}