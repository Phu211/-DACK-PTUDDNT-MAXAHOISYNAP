import 'package:flutter/material.dart';
import 'game_webview_screen.dart';

class GameModel {
  final String id;
  final String title;
  final String description;
  final String url;
  final IconData icon;
  final Color color;

  GameModel({
    required this.id,
    required this.title,
    required this.description,
    required this.url,
    required this.icon,
    required this.color,
  });
}

class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  static final List<GameModel> games = [
    GameModel(
      id: 'fireboy_watergirl',
      title: 'Trò chơi băng và lửa',
      description: 'Fireboy và Watergirl - Đền Rừng',
      url: 'https://nihogames.com/game/fireboy-va-watergirl-den-rung/',
      icon: Icons.local_fire_department,
      color: Colors.orange,
    ),
    GameModel(
      id: 'vortex9',
      title: 'Chiến trường kích thích',
      description: 'Vortex 9 - Game bắn súng',
      url: 'https://nihogames.com/game/vortex-9/',
      icon: Icons.sports_martial_arts,
      color: Colors.red,
    ),
    GameModel(
      id: 'minecraft_3d',
      title: 'Minecraft Xây Dựng 3D',
      description: 'Block Craft 3D - Xây dựng thế giới',
      url: 'https://nihogames.com/game/minecraft-xay-dung-3d/',
      icon: Icons.crop_square,
      color: Colors.green,
    ),
    GameModel(
      id: 'protect_dog',
      title: 'Bảo vệ chó của tôi',
      description: 'Protect My Dog - Game giải đố',
      url: 'https://nihogames.com/game/bao-ve-cho-cua-toi/',
      icon: Icons.pets,
      color: Colors.brown,
    ),
    GameModel(
      id: 'fruit_ninja',
      title: 'Ninja Trái Cây',
      description: 'Fruit Ninja - Cắt trái cây',
      url: 'https://nihogames.com/game/ninja-trai-cay/',
      icon: Icons.cut,
      color: Colors.purple,
    ),
    GameModel(
      id: 'solitaire',
      title: 'Bộ Sưu Tập Solitaire 15in1',
      description: 'Solitaire Collection - Game bài',
      url: 'https://nihogames.com/game/bo-suu-tap-solitaire-15in1/',
      icon: Icons.style,
      color: Colors.blue,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Game'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: games.length,
        itemBuilder: (context, index) {
          final game = games[index];
          return _buildGameCard(context, game);
        },
      ),
    );
  }

  Widget _buildGameCard(BuildContext context, GameModel game) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  GameWebViewScreen(title: game.title, url: game.url),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: game.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(game.icon, color: game.color, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      game.description,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
