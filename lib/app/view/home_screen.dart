import 'package:flutter/material.dart';

import '../../features/receiver/view/receiver_screen.dart';
import '../../features/sender/view/sender_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _openSender(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SenderScreen()));
  }

  void _openReceiver(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ReceiverScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('QR Send')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            final options = [
              _HomeActionCard(
                icon: Icons.upload_file,
                title: 'Send file',
                description:
                    'Pick a file, prepare QR frames, then open an immersive transfer screen.',
                onTap: () => _openSender(context),
              ),
              _HomeActionCard(
                icon: Icons.download,
                title: 'Receive file',
                description:
                    'Open the camera scanner, monitor progress, and complete the transfer.',
                onTap: () => _openReceiver(context),
              ),
            ];

            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose a mode',
                        style: theme.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Dedicated pages keep more screen space available for QR sending and receiving.',
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 24),
                      if (isWide)
                        Row(
                          children: [
                            Expanded(child: options[0]),
                            const SizedBox(width: 16),
                            Expanded(child: options[1]),
                          ],
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            options[0],
                            const SizedBox(height: 16),
                            options[1],
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final hasBoundedHeight = constraints.maxHeight.isFinite;

              return Column(
                mainAxisSize: hasBoundedHeight
                    ? MainAxisSize.max
                    : MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 44),
                  if (hasBoundedHeight)
                    const Spacer()
                  else
                    const SizedBox(height: 16),
                  Text(title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(description, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: onTap, child: Text(title)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
