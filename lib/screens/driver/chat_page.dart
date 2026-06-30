import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/chat_service.dart';

class ChatPage extends StatefulWidget {
  final String rideId;
  final String otherName;

  const ChatPage({super.key, required this.rideId, required this.otherName});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final String currentUserId = Supabase.instance.client.auth.currentUser!.id;
  bool isReadOnly = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    try {
      final res = await Supabase.instance.client.from('rides').select('status, completed_at').eq('id', widget.rideId).single();
      if (res['status'] == 'completed' && res['completed_at'] != null) {
        final completedAt = DateTime.parse(res['completed_at']).toLocal();
        if (DateTime.now().difference(completedAt).inHours >= 24) {
          setState(() => isReadOnly = true);
        }
      }
    } catch (_) {}
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage([String? content]) async {
    final text = content ?? _messageController.text.trim();
    if (text.isEmpty) return;
    
    _messageController.clear();
    try {
      await ChatService.sendMessage(widget.rideId, text);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Klaida: $e')));
      }
    }
  }

  void _showQuickMessages() async {
    try {
      final messages = await ChatService.getQuickMessages(true);
      if (!mounted) return;
      
      showModalBottomSheet(
        context: context,
        builder: (context) => ListView.builder(
          shrinkWrap: true,
          itemCount: messages.length,
          itemBuilder: (context, index) => ListTile(
            title: Text(messages[index]),
            onTap: () {
              Navigator.pop(context);
              _sendMessage(messages[index]);
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('Quick messages error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.otherName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Text('Aktyvus pokalbis', style: TextStyle(fontSize: 11, color: Colors.green)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: ChatService.getMessagesStream(widget.rideId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Klaida užkraunant žinutes: ${snapshot.error}'));
                }
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                final messages = snapshot.data!;
                
                // Mark as read when new messages arrive
                if (messages.isNotEmpty) {
                  ChatService.markAsRead(widget.rideId);
                  WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                }

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text('Žinučių dar nėra', style: TextStyle(color: Colors.grey.shade500)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final bool isMe = msg['sender_id'] == currentUserId;
                    return _buildMessageBubble(msg, isMe);
                  },
                );
              },
            ),
          ),
          if (isReadOnly)
            Container(
              width: double.infinity,
              color: Colors.grey.shade100,
              padding: const EdgeInsets.all(12),
              child: const Text('Pokalbis pasibaigė. Galima tik peržiūra.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
            )
          else
            _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isMe) {
    String time = '';
    try {
      time = DateFormat('HH:mm').format(DateTime.parse(msg['created_at']).toLocal());
    } catch (_) {}

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            decoration: BoxDecoration(
              color: isMe ? Colors.black : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20).copyWith(
                bottomRight: isMe ? const Radius.circular(0) : null,
                bottomLeft: !isMe ? const Radius.circular(0) : null,
              ),
              border: isMe ? null : Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              msg['content'] ?? '',
              style: TextStyle(color: isMe ? Colors.white : Colors.black, fontSize: 15),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(time, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    msg['is_read'] == true ? Icons.done_all : Icons.done, 
                    size: 14, 
                    color: msg['is_read'] == true ? Colors.blue : Colors.grey.shade400
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      decoration: BoxDecoration(
        color: Colors.white, 
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, -5))]
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _showQuickMessages, 
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
              child: const Icon(Icons.flash_on, color: Colors.orange, size: 20)
            )
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Rašyti žinutę...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
              child: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
