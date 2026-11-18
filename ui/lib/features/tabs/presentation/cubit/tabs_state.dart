import '../../domain/entities/workbench_tab.dart';

class TabsState {
  const TabsState({this.tabs = const []});

  final List<WorkbenchTab> tabs;
}
