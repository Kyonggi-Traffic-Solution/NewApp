import 'package:flutter/material.dart';
import '../services/news_api.dart';
import 'package:url_launcher/url_launcher.dart';

class SafetyNewsScreen extends StatefulWidget {
  const SafetyNewsScreen({Key? key}) : super(key: key);

  @override
  _SafetyNewsScreenState createState() => _SafetyNewsScreenState();
}

class _SafetyNewsScreenState extends State<SafetyNewsScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isLoadingMore = false;
  List<NewsItem> _newsList = [];
  Set<String> _loadedNewsUrls = {}; // 완전 중복 방지용
  String _errorMessage = '';
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late ScrollController _scrollController;
  int _currentPage = 1;
  bool _hasMoreData = true;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _fetchNews();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
      if (!_isLoadingMore && _hasMoreData) {
        _loadMoreNews();
      }
    }
  }

  Future<void> _fetchNews() async {
    if (!mounted) return; // mounted 체크 추가
    
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _currentPage = 1;
      _hasMoreData = true;
      _newsList.clear(); // 기존 리스트 초기화
      _loadedNewsUrls.clear(); // 중복 체크용 Set 초기화
    });

    try {
      // 첫 번째 페이지 로드 (10개)
      final newsList = await NewsApiService.fetchNewsWithPagination('전기 킥보드', 1, 10);
      
      if (!mounted) return; // API 응답 후 mounted 재확인
      
      // 간단한 중복 제거 (URL+제목 기준)
      final uniqueNews = _removeDuplicates(newsList);
      
      setState(() {
        _newsList = uniqueNews;
        _isLoading = false;
        _hasMoreData = newsList.length >= 10; // 10개 가져왔으면 더 있을 가능성
      });
      
      print('첫 페이지 로드: ${uniqueNews.length}개 기사');
      
      _animationController.forward();
    } catch (e) {
      if (!mounted) return; // 에러 처리 전 mounted 확인
      
      setState(() {
        _isLoading = false;
        _errorMessage = '뉴스를 불러오는 데 실패했습니다: $e';
      });
    }
  }

  Future<void> _loadMoreNews() async {
    if (_isLoadingMore || !_hasMoreData || !mounted) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      // 다음 페이지 계산
      final nextPage = _currentPage + 1;
      
      print('다음 페이지 로딩: $nextPage');
      
      // 다음 10개 뉴스 가져오기 (날짜순으로 정렬됨)
      final moreNews = await NewsApiService.fetchNewsWithPagination('킥보드', nextPage, 10);
      
      if (!mounted) return; // API 응답 후 mounted 재확인
      
      if (moreNews.isNotEmpty) {
        // 간단한 중복 제거만 수행
        final uniqueNewNews = _removeDuplicates(moreNews);
        
        setState(() {
          _newsList.addAll(uniqueNewNews);
          
          // 전체 리스트를 다시 최신순으로 정렬
          _newsList.sort((a, b) {
            try {
              DateTime dateA = _parseNewsDate(a.date);
              DateTime dateB = _parseNewsDate(b.date);
              return dateB.compareTo(dateA); // 내림차순 (최신순)
            } catch (e) {
              return 0;
            }
          });
          
          _currentPage = nextPage;
          _hasMoreData = moreNews.length >= 10; // 10개 미만이면 마지막 페이지 가능성
          _isLoadingMore = false;
        });
        
        print('페이지 $nextPage 로드 완료: ${uniqueNewNews.length}개 추가 (총 ${_newsList.length}개, 최신순 정렬됨)');
      } else {
        setState(() {
          _hasMoreData = false;
          _isLoadingMore = false;
        });
        
        print('더 이상 가져올 뉴스가 없습니다.');
      }
    } catch (e) {
      if (!mounted) return; // 에러 처리 전 mounted 확인
      
      setState(() {
        _isLoadingMore = false;
      });
      
      print('추가 뉴스 로딩 오류: $e');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('추가 뉴스를 불러오는 데 실패했습니다: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  // 간단한 중복 제거 + 날짜순 정렬 함수
  List<NewsItem> _removeDuplicates(List<NewsItem> newsList) {
    List<NewsItem> uniqueNews = [];
    
    for (NewsItem news in newsList) {
      // URL과 제목으로 중복 체크
      String uniqueKey = '${news.newsUrl}_${news.title}';
      
      if (!_loadedNewsUrls.contains(uniqueKey)) {
        _loadedNewsUrls.add(uniqueKey);
        uniqueNews.add(news);
      }
    }
    
    // 클라이언트에서 날짜순으로 다시 정렬 (최신순)
    uniqueNews.sort((a, b) {
      try {
        DateTime dateA = _parseNewsDate(a.date);
        DateTime dateB = _parseNewsDate(b.date);
        return dateB.compareTo(dateA); // 내림차순 (최신순)
      } catch (e) {
        print('날짜 정렬 오류: ${a.date} vs ${b.date}');
        return 0;
      }
    });
    
    // 정렬 후 첫 번째와 마지막 뉴스 날짜 로그
    if (uniqueNews.isNotEmpty) {
      print('정렬 후 - 첫 번째: ${uniqueNews.first.date}, 마지막: ${uniqueNews.last.date}');
    }
    
    return uniqueNews;
  }

  // 뉴스 날짜 파싱 함수
  DateTime _parseNewsDate(String dateString) {
    try {
      if (dateString.contains(',')) {
        // RFC 2822 형식 (예: "Tue, 03 Jun 2025 18:30:00 +0900")
        return _parseRfc2822Date(dateString);
      } else if (dateString.contains('T')) {
        // ISO 8601 형식 (예: "2021-12-27T17:30:00+09:00")
        return DateTime.parse(dateString);
      } else if (dateString.contains('-') && dateString.length >= 10) {
        // "YYYY-MM-DD" 형식
        final datePart = dateString.substring(0, 10);
        return DateTime.parse(datePart);
      } else {
        // 파싱할 수 없는 형식은 현재 시간 반환
        return DateTime.now();
      }
    } catch (e) {
      print('날짜 파싱 오류: $dateString, 오류: $e');
      return DateTime.now();
    }
  }

  String _formatKoreanDate(String dateString) {
    try {
      DateTime date;
      
      // 디버깅 로그 제거 (불필요한 출력 방지)
      
      if (dateString.contains(',')) {
        // RFC 2822 형식 (예: "Tue, 03 Jun 2025 18:30:00 +0900")
        date = _parseRfc2822Date(dateString);
      } else if (dateString.contains('T')) {
        // ISO 8601 형식 (예: "2021-12-27T17:30:00+09:00")
        date = DateTime.parse(dateString);
      } else if (dateString.contains('-') && dateString.length >= 10) {
        // "YYYY-MM-DD" 형식
        final datePart = dateString.substring(0, 10);
        date = DateTime.parse(datePart);
      } else {
        // 파싱할 수 없는 형식
        return dateString;
      }
      
      // 한국 요일 배열
      const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
      final weekday = weekdays[date.weekday - 1];
      
      // 현재 시간과 비교하여 상대적 시간 표시
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inDays == 0) {
        return '오늘';
      } else if (difference.inDays == 1) {
        return '어제';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}일 전';
      } else if (difference.inDays < 30) {
        return '${(difference.inDays / 7).floor()}주 전';
      } else if (difference.inDays < 365) {
        return '${(difference.inDays / 30).floor()}개월 전';
      } else {
        return '${date.year}년 ${date.month}월 ${date.day}일 ($weekday)';
      }
    } catch (e) {
      print('한국 날짜 변환 오류: $dateString, 오류: $e');
      return dateString; // 파싱 실패 시 원본 반환
    }
  }

  // RFC 2822 날짜 수동 파싱 (예: "Tue, 03 Jun 2025 18:30:00 +0900")
  DateTime _parseRfc2822Date(String dateString) {
    try {
      // "Tue, 03 Jun 2025 18:30:00 +0900" 형식 파싱
      final parts = dateString.split(' ');
      
      if (parts.length >= 4) {
        final day = int.parse(parts[1]);
        final monthStr = parts[2];
        final year = int.parse(parts[3]);
        
        // 월 이름을 숫자로 변환
        final months = {
          'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4,
          'May': 5, 'Jun': 6, 'Jul': 7, 'Aug': 8,
          'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12
        };
        
        final month = months[monthStr] ?? 1;
        
        // 시간 파싱 (선택적)
        int hour = 0, minute = 0, second = 0;
        if (parts.length >= 5 && parts[4].contains(':')) {
          final timeParts = parts[4].split(':');
          hour = int.parse(timeParts[0]);
          minute = int.parse(timeParts[1]);
          if (timeParts.length > 2) {
            second = int.parse(timeParts[2]);
          }
        }
        
        return DateTime(year, month, day, hour, minute, second);
      }
    } catch (e) {
      print('RFC 2822 파싱 오류: $dateString, 오류: $e');
    }
    
    // 파싱 실패 시 현재 날짜 반환
    return DateTime.now();
  }

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('URL을 열 수 없습니다: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Widget _buildHeaderSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue[50]!,
            Colors.green[50]!,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.blue.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.newspaper,
              color: Colors.blue[600],
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '킥보드 안전 뉴스',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '최신 안전 정보와 관련 뉴스를 확인하세요',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewsCard(NewsItem news, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 50)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final clampedValue = value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 20 * (1 - clampedValue)),
          child: Opacity(
            opacity: clampedValue,
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _launchUrl(news.newsUrl),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 상단 메타데이터
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          news.source,
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.schedule,
                        size: 14,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatKoreanDate(news.date),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // 제목
                  Text(
                    news.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // 하단 읽기 버튼
                  Row(
                    children: [
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.green.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '읽기',
                              style: TextStyle(
                                color: Colors.green[700],
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 10,
                              color: Colors.green[700],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      height: 20,
                      width: 60,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      height: 12,
                      width: 80,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 18,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 18,
                  width: double.infinity * 0.7,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Spacer(),
                    Container(
                      height: 24,
                      width: 50,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadMoreIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.blue[600],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '더 많은 뉴스를 불러오는 중...',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEndOfListIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            color: Colors.grey[500],
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            '모든 뉴스를 불러왔습니다',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return RefreshIndicator(
      onRefresh: _fetchNews,
      color: Colors.blue,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Container(
          height: MediaQuery.of(context).size.height - 200,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red[400],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '뉴스를 불러올 수 없습니다',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchNews,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 시도'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: _fetchNews,
      color: Colors.blue,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Container(
          height: MediaQuery.of(context).size.height - 200,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.inbox_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '뉴스가 없습니다',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '아래로 당겨서 새로고침하세요',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNewsList() {
    return RefreshIndicator(
      onRefresh: () async {
        _animationController.reset();
        await _fetchNews();
      },
      color: Colors.blue,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: _newsList.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildHeaderSection();
            }
            
            if (index == _newsList.length + 1) {
              if (_isLoadingMore) {
                return _buildLoadMoreIndicator();
              } else if (!_hasMoreData) {
                return _buildEndOfListIndicator();
              } else {
                return const SizedBox(height: 20);
              }
            }
            
            final newsIndex = index - 1;
            final news = _newsList[newsIndex];
            return _buildNewsCard(news, newsIndex);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          '관련 뉴스',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.refresh,
                color: Colors.blue[600],
                size: 20,
              ),
            ),
            onPressed: () {
              _animationController.reset();
              _fetchNews();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? _buildLoadingShimmer()
          : _errorMessage.isNotEmpty
              ? _buildErrorState()
              : _newsList.isEmpty
                  ? _buildEmptyState()
                  : _buildNewsList(),
    );
  }
}