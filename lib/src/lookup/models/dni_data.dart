/// Enriched person data resolved from a Peruvian DNI number.
///
/// All identity fields are nullable. A `null` value means "not selected
/// in [DniFields]" or "not returned by the lookup source" — consumers
/// must distinguish that from an empty string that may legitimately come
/// from a backend.
final class DniData {
  const DniData({
    required this.dni,
    this.nombres,
    this.apellidoPaterno,
    this.apellidoMaterno,
    this.nombreCompleto,
    this.ubigeo,
    this.departamento,
    this.provincia,
    this.distrito,
    this.rawSource,
    this.raw,
  });

  final String dni;
  final String? nombres;
  final String? apellidoPaterno;
  final String? apellidoMaterno;
  final String? nombreCompleto;
  final String? ubigeo;
  final String? departamento;
  final String? provincia;
  final String? distrito;
  final String? rawSource;
  final Map<String, dynamic>? raw;

  DniData copyWith({
    String? dni,
    String? nombres,
    String? apellidoPaterno,
    String? apellidoMaterno,
    String? nombreCompleto,
    String? ubigeo,
    String? departamento,
    String? provincia,
    String? distrito,
    String? rawSource,
    Map<String, dynamic>? raw,
  }) {
    return DniData(
      dni: dni ?? this.dni,
      nombres: nombres ?? this.nombres,
      apellidoPaterno: apellidoPaterno ?? this.apellidoPaterno,
      apellidoMaterno: apellidoMaterno ?? this.apellidoMaterno,
      nombreCompleto: nombreCompleto ?? this.nombreCompleto,
      ubigeo: ubigeo ?? this.ubigeo,
      departamento: departamento ?? this.departamento,
      provincia: provincia ?? this.provincia,
      distrito: distrito ?? this.distrito,
      rawSource: rawSource ?? this.rawSource,
      raw: raw ?? this.raw,
    );
  }
}
