class AppUser {
  AppUser.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        phone = j['phone'] as String?,
        name = j['name'] as String?,
        businessName = j['business_name'] as String?,
        role = j['role'] as String,
        languageCode = j['language_code'] as String,
        cityId = (j['city'] as Map?)?['id'] as int?,
        cityName = (j['city'] as Map?)?['name'] as String?,
        countryId = (j['city'] as Map?)?['country_id'] as int?,
        needsSetup = j['needs_setup'] as bool;

  final int id;
  final String? phone, name, businessName, cityName;
  final String role, languageCode;
  final int? cityId, countryId;
  final bool needsSetup;

  bool get isCourier => role == 'courier';
}

class Named {
  const Named(this.id, this.name);

  final int id;
  final String name;
}

class Country extends Named {
  Country.fromJson(Map<String, dynamic> j)
      : code = j['code'] as String,
        dialCode = j['dial_code'] as String,
        cities = (j['cities'] as List).map((c) => Named(c['id'] as int, c['name'] as String)).toList(),
        super(j['id'] as int, j['name'] as String);

  final String code, dialCode;
  final List<Named> cities;

  /// Le drapeau se déduit du code ISO, sans image à embarquer.
  String get flag => String.fromCharCodes(code.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 0x41));
}

class Language {
  Language.fromJson(Map<String, dynamic> j)
      : code = j['code'] as String,
        name = j['name'] as String;

  final String code, name;
}

class OrderItem {
  OrderItem.fromJson(Map<String, dynamic> j)
      : name = j['name'] as String,
        unitPrice = j['unit_price'] as int,
        quantity = j['quantity'] as int;

  final String name;
  final int unitPrice, quantity;

  int get subtotal => unitPrice * quantity;
}

class OrderEvent {
  OrderEvent.fromJson(Map<String, dynamic> j)
      : status = j['status'] as String,
        at = DateTime.parse(j['at'] as String).toLocal();

  final String status;
  final DateTime at;
}

class Order {
  Order.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        reference = j['reference'] as String,
        requestText = j['request_text'] as String,
        channel = j['channel'] as String? ?? 'text',
        hasVoice = j['has_voice'] as bool,
        landmark = (j['delivery'] as Map)['landmark'] as String,
        recipientPhone = (j['delivery'] as Map)['recipient_phone'] as String?,
        lat = ((j['delivery'] as Map)['lat'] as num?)?.toDouble(),
        lng = ((j['delivery'] as Map)['lng'] as num?)?.toDouble(),
        status = j['status'] as String,
        statusLabel = j['status_label'] as String,
        price = j['price'] as int?,
        goodsTotal = j['goods_total'] as int?,
        deliveryFee = j['delivery_fee'] as int?,
        shopName = (j['shop'] as Map?)?['name'] as String?,
        shopPhone = (j['shop'] as Map?)?['phone'] as String?,
        shopLandmark = (j['shop'] as Map?)?['landmark'] as String?,
        items = ((j['items'] as List?) ?? const []).map((i) => OrderItem.fromJson(i as Map<String, dynamic>)).toList(),
        paymentMode = j['payment_mode'] as String?,
        isPaid = j['is_paid'] as bool,
        cancelReason = j['cancel_reason'] as String?,
        createdAt = DateTime.parse(j['created_at'] as String).toLocal(),
        events = ((j['events'] as List?) ?? const [])
            .map((e) => OrderEvent.fromJson(e as Map<String, dynamic>))
            .toList();

  final int id;
  final String reference, requestText, channel, landmark, status, statusLabel;
  final bool hasVoice, isPaid;
  final int? price, goodsTotal, deliveryFee;
  final String? paymentMode, cancelReason, recipientPhone, shopName, shopPhone, shopLandmark;
  final List<OrderItem> items;
  final double? lat, lng;
  final DateTime createdAt;
  final List<OrderEvent> events;

  bool get awaitsPrice => status == 'price_pending';
  bool get awaitsMobilePayment => status == 'confirmed' && paymentMode == 'mobile_money' && !isPaid;
  bool get isCancelled => status == 'cancelled';
  bool get canCancel => status == 'received' || status == 'price_pending';
  bool get isShopOrder => channel == 'shop';
}

class Ad {
  Ad.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        categoryLabel = j['category_label'] as String,
        title = j['title'] as String,
        description = j['description'] as String?,
        status = j['status'] as String,
        statusLabel = j['status_label'] as String,
        rejectionReason = j['rejection_reason'] as String?;

  final int id;
  final String categoryLabel, title, status, statusLabel;
  final String? description, rejectionReason;

  String get imagePath => '/ads/$id/image';
}

class Shop {
  Shop.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        name = j['name'] as String,
        category = j['category'] as String?,
        description = j['description'] as String?,
        phone = j['phone'] as String?,
        landmark = j['landmark'] as String?,
        lat = (j['lat'] as num?)?.toDouble(),
        lng = (j['lng'] as num?)?.toDouble(),
        hasImage = j['has_image'] as bool,
        isMine = j['is_mine'] as bool? ?? false,
        status = j['status'] as String,
        statusLabel = j['status_label'] as String,
        rejectionReason = j['rejection_reason'] as String?;

  final int id;
  final String name, status, statusLabel;
  final String? category, description, phone, landmark, rejectionReason;
  final double? lat, lng;
  final bool hasImage, isMine;

  String get imagePath => '/shops/$id/image';
}

class Product {
  Product.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        name = j['name'] as String,
        description = j['description'] as String?,
        price = j['price'] as int,
        stock = j['stock'] as int?,
        isActive = j['is_active'] as bool;

  final int id, price;
  final String name;
  final String? description;
  final int? stock;
  final bool isActive;

  String get imagePath => '/products/$id/image';
  bool get isSoldOut => stock == 0;
}

class SellerOrder {
  SellerOrder.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        reference = j['reference'] as String,
        statusLabel = j['status_label'] as String,
        goodsTotal = j['goods_total'] as int,
        createdAt = DateTime.parse(j['created_at'] as String).toLocal(),
        items = (j['items'] as List).map((i) => OrderItem.fromJson(i as Map<String, dynamic>)).toList();

  final int id, goodsTotal;
  final String reference, statusLabel;
  final DateTime createdAt;
  final List<OrderItem> items;
}

class Payout {
  Payout.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        orderReference = j['order_reference'] as String?,
        commission = j['commission'] as int,
        amount = j['amount'] as int,
        statusLabel = j['status_label'] as String;

  final int id, commission, amount;
  final String statusLabel;
  final String? orderReference;
}

class Payment {
  Payment.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        orderId = j['order_id'] as int,
        orderReference = j['order_reference'] as String?,
        amount = j['amount'] as int,
        methodLabel = j['method_label'] as String,
        status = j['status'] as String,
        statusLabel = j['status_label'] as String,
        failureReason = j['failure_reason'] as String?,
        createdAt = DateTime.parse(j['created_at'] as String).toLocal();

  final int id, orderId, amount;
  final String? orderReference, failureReason;
  final String methodLabel, status, statusLabel;
  final DateTime createdAt;

  bool get isPending => status == 'pending';
  bool get hasReceipt => status == 'succeeded' || status == 'refunded';
}
