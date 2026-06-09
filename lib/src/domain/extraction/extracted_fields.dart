class ExtractedFields {
  ExtractedFields({
    this.documentNumber,
    this.firstName,
    this.lastName,
    this.secondLastName,
    this.dateOfBirth,
    this.expirationDate,
    this.emissionDate,
    this.inscriptionDate,
    this.sex,
    this.nationality,
    this.address,
    this.department,
    this.province,
    this.district,
    this.stateCivil,
    this.cardNumber,
    this.organDonor,
    this.votingGroup,
    this.birthUbigeoCode,
  });

  String? documentNumber;
  String? firstName;
  String? lastName;
  String? secondLastName;
  String? dateOfBirth;
  String? expirationDate;
  String? emissionDate;
  String? inscriptionDate;
  String? sex;
  String? nationality;
  String? address;
  String? department;
  String? province;
  String? district;
  String? stateCivil;
  String? cardNumber;
  String? organDonor;
  String? votingGroup;
  String? birthUbigeoCode;

  bool get isEmpty =>
      documentNumber == null &&
      firstName == null &&
      lastName == null &&
      secondLastName == null &&
      dateOfBirth == null &&
      expirationDate == null &&
      emissionDate == null &&
      inscriptionDate == null &&
      sex == null &&
      nationality == null &&
      address == null &&
      department == null &&
      province == null &&
      district == null &&
      stateCivil == null &&
      cardNumber == null &&
      organDonor == null &&
      votingGroup == null &&
      birthUbigeoCode == null;

  void merge(ExtractedFields other) {
    documentNumber ??= other.documentNumber;
    firstName ??= other.firstName;
    lastName ??= other.lastName;
    secondLastName ??= other.secondLastName;
    dateOfBirth ??= other.dateOfBirth;
    expirationDate ??= other.expirationDate;
    emissionDate ??= other.emissionDate;
    inscriptionDate ??= other.inscriptionDate;
    sex ??= other.sex;
    nationality ??= other.nationality;
    address ??= other.address;
    department ??= other.department;
    province ??= other.province;
    district ??= other.district;
    stateCivil ??= other.stateCivil;
    cardNumber ??= other.cardNumber;
    organDonor ??= other.organDonor;
    votingGroup ??= other.votingGroup;
    birthUbigeoCode ??= other.birthUbigeoCode;
  }
}
