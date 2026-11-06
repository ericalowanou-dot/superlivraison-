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
        hasVoice = j['has_voice'] as bool,
        landmark = (j['delivery'] as Map)['landmark'] as String,
        status = j['status'] as String,
        statusLabel = j['status_label'] as String,
        price = j['price'] as int?,
        paymentMode = j['payment_mode'] as String?,
        isPaid = j['is_paid'] as bool,
        cancelReason = j['cancel_reason'] as String?,
        createdAt = DateTime.parse(j['created_at'] as String).toLocal(),
        events = ((j['events'] as List?) ?? const [])
            .map((e) => OrderEvent.fromJson(e as Map<String, dynamic>))
            .toList();

  final int id;
  final String reference, requestText, landmark, status, statusLabel;
  final bool hasVoice, isPaid;
  final int? price;
  final String? paymentMode, cancelReason;
  final DateTime createdAt;
  final List<OrderEvent> events;

  bool get awaitsPrice => status == 'price_pending';
  bool get awaitsMobilePayment => status == 'confirmed' && paymentMode == 'mobile_money' && !isPaid;
  bool get isCancelled => status == 'cancelled';
  bool get canCancel => status == 'received' || status == 'price_pending';
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
