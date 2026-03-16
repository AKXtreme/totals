class Transaction {
  final double amount; // required
  final String reference; // required
  final String? creditor;
  final String? receiver;
  final String? note;
  final String? time; // ISO string
  final String? status; // PENDING, CLEARED, SYNCED
  final String? currentBalance;
  final int? bankId;
  final String? type; // CREDIT or DEBIT
  final String? transactionLink;
  final String? accountNumber; // Last 4 digits
  final int? categoryId;
  final int? profileId;
  final double? serviceCharge;
  final double? vat;

  Transaction({
    required this.amount,
    required this.reference,
    this.creditor,
    this.receiver,
    this.note,
    this.time,
    this.status,
    this.currentBalance,
    this.bankId,
    this.type,
    this.transactionLink,
    this.accountNumber,
    this.categoryId,
    this.profileId,
    this.serviceCharge,
    this.vat,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      return 0.0;
    }

    return Transaction(
      amount: toDouble(json['amount']),
      reference: json['reference'] ?? '',
      creditor: json['creditor'],
      receiver: json['receiver'],
      note: json['note'],
      time: json['time'],
      status: json['status'],
      currentBalance: json['currentBalance']?.toString(),
      bankId: json['bankId'],
      type: json['type'],
      transactionLink: json['transactionLink'],
      accountNumber: json['accountNumber'],
      categoryId: json['categoryId'],
      profileId: json['profileId'] as int?,
      serviceCharge: toDouble(json['serviceCharge']),
      vat: toDouble(json['vat']),
    );
  }

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'reference': reference,
        'creditor': creditor,
        'receiver': receiver,
        'note': note,
        'time': time,
        'status': status,
        'currentBalance': currentBalance,
        'bankId': bankId,
        'type': type,
        'transactionLink': transactionLink,
        'accountNumber': accountNumber,
        'categoryId': categoryId,
        if (profileId != null) 'profileId': profileId,
        if (serviceCharge != null) 'serviceCharge': serviceCharge,
        if (vat != null) 'vat': vat,
      };

  Transaction copyWith({
    double? amount,
    String? reference,
    String? creditor,
    String? receiver,
    String? note,
    String? time,
    String? status,
    String? currentBalance,
    int? bankId,
    String? type,
    String? transactionLink,
    String? accountNumber,
    int? categoryId,
    int? profileId,
    double? serviceCharge,
    double? vat,
    bool clearCategoryId = false, // Flag to explicitly clear categoryId
    bool clearNote = false,
  }) {
    return Transaction(
      amount: amount ?? this.amount,
      reference: reference ?? this.reference,
      creditor: creditor ?? this.creditor,
      receiver: receiver ?? this.receiver,
      note: clearNote ? null : (note ?? this.note),
      time: time ?? this.time,
      status: status ?? this.status,
      currentBalance: currentBalance ?? this.currentBalance,
      bankId: bankId ?? this.bankId,
      type: type ?? this.type,
      transactionLink: transactionLink ?? this.transactionLink,
      accountNumber: accountNumber ?? this.accountNumber,
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      profileId: profileId ?? this.profileId,
      serviceCharge: serviceCharge ?? this.serviceCharge,
      vat: vat ?? this.vat,
    );
  }
}
