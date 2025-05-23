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

  // 사용자의 신고 내역 가져오기
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

      // Firestore에서 사용자의 신고 내역 가져오기
      final reportsQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('reports')
          .orderBy('createdAt', descending: true)
          .get();

      final reports = reportsQuery.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id; // 문서 ID 추가
        return data;
      }).toList();

      setState(() {
        _reports = List<Map<String, dynamic>>.from(reports);
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
  Color _getStatusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green.withOpacity(0.2);
      case 'rejected':
        return Colors.red.withOpacity(0.2);
      case 'submitted':
      default:
        return Colors.grey.withOpacity(0.1);
    }
  }

  // 신고 상태 한글 텍스트 반환
  String _getStatusText(String status) {
    switch (status) {
      case 'approved':
        return '승인됨';
      case 'rejected':
        return '반려됨';
      case 'submitted':
      default:
        return '검토중';
    }
  }

  // 신고 상태 아이콘 반환
  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'approved':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      case 'submitted':
      default:
        return Icons.pending;
    }
  }

  // 신고 상태 아이콘 색상 반환
  Color _getStatusIconColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'submitted':
      default:
        return Colors.grey;
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
              ? Center(child: Text(_errorMessage))
              : _reports.isEmpty
                  ? const Center(child: Text('신고 내역이 없습니다'))
                  : RefreshIndicator(
                      onRefresh: _fetchReports,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16.0),
                        itemCount: _reports.length,
                        itemBuilder: (context, index) {
                          final report = _reports[index];
                          final status = report['status'] as String? ?? 'submitted';
                          final createdAt = report['createdAt'] as Timestamp?;
                          final date = createdAt != null
                              ? DateFormat('yyyy년 MM월 dd일 HH:mm').format(createdAt.toDate())
                              : report['date'] as String? ?? '날짜 정보 없음';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 16.0),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: _getStatusColor(status),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 이미지가 있다면 표시
                                  if (report['imageUrl'] != null)
                                    ClipRRect(
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(12),
                                      ),
                                      child: Image.network(
                                        report['imageUrl'] as String,
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
                                                date,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ),
                                            // 상태 표시 칩
                                            Chip(
                                              label: Text(
                                                _getStatusText(status),
                                                style: TextStyle(
                                                  color: _getStatusIconColor(status),
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              avatar: Icon(
                                                _getStatusIcon(status),
                                                color: _getStatusIconColor(status),
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
                                        
                                        // 장소 정보
                                        // Row(
                                        //   children: [
                                        //     const Icon(Icons.location_on, 
                                        //       color: Colors.orange, 
                                        //       size: 18,
                                        //     ),
                                        //     const SizedBox(width: 8),
                                        //     Expanded(
                                        //       child: Text(
                                        //         report['location'] as String? ?? '위치 정보 없음',
                                        //         style: const TextStyle(
                                        //           fontWeight: FontWeight.bold,
                                        //         ),
                                        //       ),
                                        //     ),
                                        //   ],
                                        // ),
                                        // const SizedBox(height: 8),
                                        
                                        // 위반 사항 정보
                                        Text(
                                          report['violation'] as String? ?? '위반 사항 정보 없음',
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                        
                                        // 반려된 경우 반려 사유 표시
                                        if (status == 'rejected' && report['rejectionReason'] != null)
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
                                                    report['rejectionReason'] as String,
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
                          );
                        },
                      ),
                    ),
    );
  }
}