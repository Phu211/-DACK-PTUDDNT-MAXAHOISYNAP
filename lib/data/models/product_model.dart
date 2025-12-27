class ProductModel {
  final String id;
  final String sellerId;
  final String name;
  final String? description;
  final List<String> imageUrls;
  final double price;
  final String? currency;
  final String? category;
  final String? location;
  final bool isAvailable;
  final int viewsCount;
  final int likesCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProductModel({
    required this.id,
    required this.sellerId,
    required this.name,
    this.description,
    this.imageUrls = const [],
    required this.price,
    this.currency = 'VND',
    this.category,
    this.location,
    this.isAvailable = true,
    this.viewsCount = 0,
    this.likesCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'sellerId': sellerId,
      'name': name,
      'description': description,
      'imageUrls': imageUrls,
      'price': price,
      'currency': currency,
      'category': category,
      'location': location,
      'isAvailable': isAvailable,
      'viewsCount': viewsCount,
      'likesCount': likesCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ProductModel.fromMap(String id, Map<String, dynamic> map) {
    return ProductModel(
      id: id,
      sellerId: map['sellerId'] ?? '',
      name: map['name'] ?? '',
      description: map['description'],
      imageUrls: List<String>.from(map['imageUrls'] ?? []),
      price: (map['price'] ?? 0.0).toDouble(),
      currency: map['currency'] ?? 'VND',
      category: map['category'],
      location: map['location'],
      isAvailable: map['isAvailable'] ?? true,
      viewsCount: map['viewsCount'] ?? 0,
      likesCount: map['likesCount'] ?? 0,
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }
}


