import 'package:file_picker/file_picker.dart';
import 'package:file_picker_web/file_picker_web.dart';

/// On a phone the page gets its focus back before the browser hands the file over (copied from Drive or
/// Downloads). By default file_picker takes that focus as a cancel after 500 ms and drops the file: the user
/// picks a PDF and nothing happens. Wait for the input's own `change` or `cancel` event instead.
const WebOptions optionsSelection = FilePickerWebOptions(cancelUploadOnWindowBlur: false);
