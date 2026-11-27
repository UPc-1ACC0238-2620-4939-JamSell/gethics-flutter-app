/// Estados del animal en el backend. El listado muestra por defecto solo [active]; el resto sale por el filtro.
enum AnimalStatus {
  active('ACTIVE'),
  sold('SOLD'),
  deceased('DECEASED'),
  inactive('INACTIVE');

  const AnimalStatus(this.apiName);

  final String apiName;

  /// Null si el dato falta o no se reconoce: no se inventa un estado.
  static AnimalStatus? fromApi(String? name) {
    for (final status in AnimalStatus.values) {
      if (status.apiName == name) return status;
    }
    return null;
  }
}

/// Animal tal como lo devuelve el backend (AnimalResource).
class Animal {
  const Animal({
    required this.id,
    required this.tag,
    required this.breed,
    this.farmId,
    this.qrCode,
    this.name,
    this.sex,
    this.birthDate,
    this.weightKg,
    this.status,
  });

  final String id;
  final String tag;
  final String breed;
  final String? farmId;
  final String? qrCode;
  final String? name;

  /// MALE | FEMALE; null si el backend no lo envia.
  final String? sex;
  final DateTime? birthDate;
  final double? weightKg;
  final AnimalStatus? status;

  factory Animal.fromJson(Map<String, dynamic> json) => Animal(
        id: json['id'] as String,
        tag: json['tag'] as String? ?? '',
        breed: json['breed'] as String? ?? '',
        farmId: json['farmId'] as String?,
        qrCode: json['qrCode'] as String?,
        name: json['name'] as String?,
        sex: json['sex'] as String?,
        birthDate: DateTime.tryParse(json['birthDate'] as String? ?? ''),
        weightKg: (json['initialWeightKg'] as num?)?.toDouble(),
        status: AnimalStatus.fromApi(json['status'] as String?),
      );
}
