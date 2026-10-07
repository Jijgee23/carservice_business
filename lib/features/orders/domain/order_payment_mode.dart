/// Payment-mode selector of the create-order form. Maps 1:1 onto the
/// `isPostpaid` / `isInternal` booleans the API still expects (server CHECK:
/// never both).
enum OrderPaymentMode {
  regular('Энгийн', 'Дуусгахад төлбөр бүрэн төлөгдсөн байх ёстой.'),
  postpaid('Дараа тооцоо', 'Тооцоог дараа нийлнэ.'),
  internal('Дотоод засвар', 'Төлбөргүй — дотоод зардалд бүртгэгдэнэ.');

  const OrderPaymentMode(this.label, this.helper);

  final String label;
  final String helper;

  bool get isPostpaid => this == postpaid;
  bool get isInternal => this == internal;

  static OrderPaymentMode fromFlags({
    required bool isPostpaid,
    required bool isInternal,
  }) {
    if (isInternal) return internal;
    return isPostpaid ? postpaid : regular;
  }

  /// Default for a (newly) selected vehicle.
  static OrderPaymentMode forVehicle(bool vehiclePostpaid) =>
      vehiclePostpaid ? postpaid : regular;

  /// Vehicle change re-defaults to the vehicle's value unless the user chose
  /// internal repair, which is kept.
  OrderPaymentMode afterVehicleChange(bool vehiclePostpaid) =>
      this == internal ? internal : forVehicle(vehiclePostpaid);
}
