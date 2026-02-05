import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl =
      "https://hopehomeo-tokens-backend.onrender.com/api/tokens";

  // 1. Generate New Token
  static Future<int?> generateToken() async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/generate'));
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['token']['tokenNumber'];
      }
    } catch (e) {
      debugPrint("API Error (Generate): $e");
    }
    return null;
  }

  // 2. Get Current & Upcoming (For Serving Status)
  static Future<Map<String, dynamic>?> getCurrentStatus() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/current'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint("API Error (Current): $e");
    }
    return null;
  }

  // 3. Complete Current Token (Next Patient)
  static Future<Map<String, dynamic>?> completeToken() async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/complete'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['activeToken']; // Returns the NEW active token
      }
    } catch (e) {
      debugPrint("API Error (Complete): $e");
    }
    return null;
  }

  // 4. Get Last Generated Token (For Printer State)
  static Future<int?> getLastGeneratedToken() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/last-generated'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Handle case where no tokens exist yet
        if (data['lastGeneratedToken'] == null) return 0;
        return data['lastGeneratedToken']['tokenNumber'];
      }
    } catch (e) {
      debugPrint("API Error (Last Generated): $e");
    }
    return null;
  }

  // 5. Reset All Tokens
  static Future<bool> resetTokens() async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/reset'));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("API Error (Reset): $e");
      return false;
    }
  }
}
