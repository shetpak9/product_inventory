class UserId {
  final String uid;
  const UserId({required this.uid});
}

enum UserRole {
  customer,
  seller;

  static UserRole fromString(String? value) {
    return UserRole.values.firstWhere(
      (UserRole role) => role.name == value,
      orElse: () => UserRole.customer,
    );
  }
}

class UserData {
  const UserData({
    required this.uid,
    required this.firstName,
    required this.lastName,
    this.role = UserRole.customer,
    this.phone,
  });

  final String uid;
  final String firstName;
  final String lastName;
  final UserRole role;
  final String? phone;

  String get fullName => '$firstName $lastName'.trim();

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'firstName': firstName,
      'lastName': lastName,
      'role': role.name,
      if (phone != null && phone!.isNotEmpty) 'phone': phone,
    };
  }

  /// Accounts created before roles existed have no `role`; they are customers.
  factory UserData.fromMap(Map<dynamic, dynamic> map, String uid) {
    return UserData(
      uid: uid,
      firstName: (map['firstName'] ?? map['f_name'] ?? '').toString(),
      lastName: (map['lastName'] ?? map['l_name'] ?? '').toString(),
      role: UserRole.fromString(map['role']?.toString()),
      phone: map['phone']?.toString(),
    );
  }
}
