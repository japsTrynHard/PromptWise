class NewsItem {
  final String id;
  final String title;
  final String summary;
  final String date;
  final String? sourceUrl;
  final DateTime? reviewDate;

  const NewsItem({
    this.id = '',
    required this.title,
    required this.summary,
    required this.date,
    this.sourceUrl,
    this.reviewDate,
  });
}
