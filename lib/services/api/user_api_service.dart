import 'package:trainhub/core/network/api_service.dart';
import 'package:trainhub/models/user_model.dart';

/// Example feature API service.
///
/// Pattern for every future API service:
/// inject [ApiService] and call only get/post/put/patch/delete.
class UserApiService {
  /// Creates a [UserApiService] that talks through [ApiService].
  UserApiService(this._api);

  final ApiService _api;

  /// Fetches the authenticated user profile.
  Future<UserModel> getProfile() async {
    final response = await _api.get<Map<String, dynamic>>('/users/me');
    return UserModel.fromJson(response.data ?? <String, dynamic>{});
  }

  /// Partially updates the authenticated user profile.
  Future<UserModel> updateProfile(Map<String, dynamic> body) async {
    final response = await _api.patch<Map<String, dynamic>>(
      '/users/me',
      data: body,
    );
    return UserModel.fromJson(response.data ?? <String, dynamic>{});
  }
}
