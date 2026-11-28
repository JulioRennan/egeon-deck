import '../../../../core/adapters/egeon_socket_client.dart';
import '../../../../core/adapters/organization_feed.dart';
import '../errors/home_error.dart';
import 'menu_repository.dart';

class SocketMenuRepository implements MenuRepository {
  const SocketMenuRepository(this._feed);

  final OrganizationFeed _feed;

  @override
  Future<String> dispatchTargets() async {
    final reply = await _feed
        .command('copy_targets')
        .failingAs(refused: HomeRefused.new, offline: HomeOffline.new);
    return reply['text'] as String? ?? '';
  }
}
