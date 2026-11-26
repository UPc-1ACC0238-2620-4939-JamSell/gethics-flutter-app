import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'core/di/app_dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = await AppDependencies.create();
  runApp(GethicsApp(dependencies: dependencies));
}
