import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class NewsItem {
  final String title;
  final String imageUrl;
  final String newsUrl;
  final String date;
  final String source;

  NewsItem({
    required this.title,
    required this.imageUrl,
    required this.newsUrl,
    required this.date,
    required this.source,
  });

  factory NewsItem.fromJson(Map<String, dynamic> json) {
    return NewsItem(
      title: _decodeHtmlEntities(_removeHtmlTags(json['title'] ?? '')),
      imageUrl: json['imageUrl'] ?? 'https://via.placeholder.com/150',
      newsUrl: json['link'] ?? '',
      date: _formatDate(json['pubDate'] ?? ''),
      source: json['source'] ?? '네이버 뉴스',
    );
  }

  // HTML 태그 제거 헬퍼 함수
  static String _removeHtmlTags(String htmlText) {
    RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
    return htmlText.replaceAll(exp, '');
  }
  
  static String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&apos;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&#x2F;', '/')
        .replaceAll('&#39;', "'")
        .replaceAll('&#47;', '/');
  }

  // 날짜 형식 변환 헬퍼 함수
  static String _formatDate(String apiDate) {
    try {
      DateTime date;
      
      if (apiDate.contains(',')) {
        // RFC 2822 형식 처리 (예: "Tue, 03 Jun 2025 18:30:00 +0900")
        // intl 패키지 없이 수동 파싱
        date = _parseRfc2822Date(apiDate);
      } else if (apiDate.contains('T')) {
        // ISO 8601 형식 처리
        date = DateTime.parse(apiDate);
      } else if (apiDate.contains('-') && apiDate.length >= 10) {
        // "YYYY-MM-DD" 형식 처리
        date = DateTime.parse(apiDate.substring(0, 10));
      } else {
        // 파싱 실패 시 현재 날짜로 대체
        print('날짜 파싱 실패: $apiDate');
        date = DateTime.now();
      }
      
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      print('날짜 변환 오류: $apiDate, 오류: $e');
      // 오류 발생 시 현재 날짜 반환
      final now = DateTime.now();
      return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    }
  }

  // RFC 2822 날짜 수동 파싱 (예: "Tue, 03 Jun 2025 18:30:00 +0900")
  static DateTime _parseRfc2822Date(String dateString) {
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
}

class NewsApiService {
  // 첫 번째 페이지 로드 (10개)
  static Future<List<NewsItem>> fetchNews(String keyword) async {
    return fetchNewsWithPagination(keyword, 1, 10);
  }

  // 페이지네이션을 지원하는 뉴스 가져오기
  static Future<List<NewsItem>> fetchNewsWithPagination(
    String keyword, 
    int page, 
    int display
  ) async {
    try {
      // .env 파일에서 API 키를 가져옵니다
      final clientId = dotenv.env['NAVER_CLIENT_ID'];
      final clientSecret = dotenv.env['NAVER_CLIENT_SECRET'];
      
      // API 키가 없으면 빈 리스트 반환
      if (clientId == null || clientSecret == null) {
        print('API 키가 설정되지 않았습니다.');
        return [];
      }
      
      // 시작 위치 계산 (네이버 API는 1부터 시작)
      final start = ((page - 1) * display) + 1;
      
      // 네이버 API는 최대 1000개까지만 조회 가능
      if (start > 1000) {
        print('네이버 API 한계에 도달했습니다. (최대 1000개)');
        return [];
      }
      
      final url = Uri.parse(
        'https://openapi.naver.com/v1/search/news.json?'
        'query=${Uri.encodeComponent(keyword)}&'
        'display=$display&'
        'start=$start&'
        'sort=date' // 항상 날짜순 정렬로 고정
      );
      
      print('API 호출: 페이지 $page, 시작위치 $start, 개수 $display (날짜순 정렬)');
      
      final response = await http.get(
        url,
        headers: {
          'X-Naver-Client-Id': clientId,
          'X-Naver-Client-Secret': clientSecret,
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<dynamic> items = data['items'] ?? [];
        final int total = data['total'] ?? 0;
        
        print('API 응답: 총 ${total}개 중 ${items.length}개 가져옴 (페이지: $page)');
        
        if (items.isEmpty) {
          print('더 이상 가져올 뉴스가 없습니다.');
          return [];
        }
        
        final newsItems = items.map((item) => NewsItem.fromJson(item)).toList();
        
        // 첫 번째와 마지막 뉴스 날짜 로그 (날짜 순서 확인용)
        if (newsItems.isNotEmpty) {
          print('첫 번째 뉴스 날짜: ${newsItems.first.date}');
          if (newsItems.length > 1) {
            print('마지막 뉴스 날짜: ${newsItems.last.date}');
          }
        }
        
        return newsItems;
      } else {
        print('API 응답 오류: ${response.statusCode}');
        print('응답 내용: ${response.body}');
        return [];
      }
    } catch (e) {
      print('네트워크 오류: $e');
      return [];
    }
  }
}