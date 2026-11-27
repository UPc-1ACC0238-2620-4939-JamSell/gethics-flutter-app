/// Granja asignada a un animal (FarmResource del backend).
class Farm {
  const Farm({required this.id, required this.name, this.location});

  final String id;
  final String name;
  final String? location;

  factory Farm.fromJson(Map<String, dynamic> json) => Farm(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        location: json['location'] as String?,
      );
}
