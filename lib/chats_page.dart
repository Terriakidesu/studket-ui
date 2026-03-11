import 'package:flutter/material.dart';

import 'components/studket_app_bar.dart';

class ChatsPage extends StatelessWidget {
  const ChatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: StudketAppBar(title: 'Chats'),
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'No public conversations or messages endpoint is available for normal user accounts in the current backend.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class ChatThreadPage extends StatelessWidget {
  const ChatThreadPage({
    super.key,
    required this.sellerName,
    required this.lastMessage,
    required this.sellerAvatarUrl,
    this.inquiryProduct,
  });

  final String sellerName;
  final String lastMessage;
  final String sellerAvatarUrl;
  final InquiryProductData? inquiryProduct;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: StudketAppBar(title: sellerName),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Chat threads are unavailable because the backend does not expose public user messaging endpoints.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class InquiryProductData {
  const InquiryProductData({
    required this.name,
    required this.location,
    required this.imageUrl,
  });

  final String name;
  final String location;
  final String imageUrl;
}
