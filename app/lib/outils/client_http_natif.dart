import 'package:cupertino_http/cupertino_http.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// iOS: Apple's URL Loading System, like Firebase and Safari. dart:io's own DNS lookup failed on a real iPhone
/// where these reach the backend.
http.Client clientHttp() =>
    defaultTargetPlatform == TargetPlatform.iOS ? CupertinoClient.defaultSessionConfiguration() : http.Client();
