import 'package:sembast_web/sembast_web.dart';

Future<Database> openAtletaDatabase() =>
    databaseFactoryWeb.openDatabase('atleta-v1', version: 1);
