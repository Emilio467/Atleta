import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

Future<Database> openAtletaDatabase() async {
  final directory = await getApplicationSupportDirectory();
  return databaseFactoryIo.openDatabase(
    '${directory.path}/atleta-v1.db',
    version: 1,
  );
}
