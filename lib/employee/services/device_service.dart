import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentity {
  const DeviceIdentity(this.id, this.model);

  final String id;
  final String model;
}

/// Stable per-install device identity used to bind an account to one phone.
///
/// Android no longer exposes a hardware ID to apps, so a random id is created
/// on first launch. Reinstalling or clearing app data creates a new id, which
/// the admin must approve by resetting the device binding.
class DeviceService {
  static const _key = 'device_install_id';

  Future<DeviceIdentity> identity() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_key, id);
    }
    final info = await DeviceInfoPlugin().androidInfo;
    return DeviceIdentity(id, '${info.manufacturer} ${info.model}');
  }
}
