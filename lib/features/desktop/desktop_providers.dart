import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ctrl+F: each bump asks the Contacts screen to focus its search box.
class FocusSearchTick extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final focusSearchProvider = NotifierProvider<FocusSearchTick, int>(FocusSearchTick.new);

/// The contact shown in the right-hand pane of the two-pane layout.
class SelectedContact extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String? id) => state = id;
}

final selectedContactProvider = NotifierProvider<SelectedContact, String?>(SelectedContact.new);

/// Ctrl+S: each bump asks the open contact form to save.
class SaveRequestTick extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final saveRequestProvider = NotifierProvider<SaveRequestTick, int>(SaveRequestTick.new);
