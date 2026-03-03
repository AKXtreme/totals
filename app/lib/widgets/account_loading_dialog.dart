import 'package:flutter/material.dart';
import 'dart:async';

class AccountLoadingDialog extends StatefulWidget {
  final Future<void> Function(Function(String, double) onProgress) task;

  const AccountLoadingDialog({required this.task, super.key});

  @override
  State<AccountLoadingDialog> createState() => _AccountLoadingDialogState();
}

class _AccountLoadingDialogState extends State<AccountLoadingDialog>
    with SingleTickerProviderStateMixin {
  String _currentStage = "Initializing...";
  double _progress = 0.0;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _runTask();
  }

  Future<void> _runTask() async {
    try {
      await widget.task((stage, progress) {
        if (mounted) {
          setState(() {
            _currentStage = stage;
            _progress = progress;
          });
        }
      });

      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _getTimeEstimate() {
    if (_progress < 0.3) return "This may take a minute...";
    if (_progress < 0.6) return "Almost halfway there...";
    if (_progress < 0.9) return "Almost done!";
    return "Finishing up...";
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Prevent closing during operation
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated icon
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF294EC3).withOpacity(0.3),
                            const Color(0xFF294EC3),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 8,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    const Color(0xFF294EC3),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Current stage text
              Text(
                _currentStage,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF444750),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // Time estimate
              Text(
                _getTimeEstimate(),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // Progress percentage
              Text(
                "${(_progress * 100).toInt()}%",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF294EC3).withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
