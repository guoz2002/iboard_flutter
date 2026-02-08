import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/rthk_news_provider.dart';

class RthkNewsTickerWidget extends StatefulWidget {
  final double height;
  final double width;

  const RthkNewsTickerWidget({
    super.key,
    required this.height,
    required this.width,
  });

  @override
  RthkNewsTickerWidgetState createState() => RthkNewsTickerWidgetState();
}

class RthkNewsTickerWidgetState extends State<RthkNewsTickerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late ScrollController _scrollController;

  List<String> _newsTexts = [];
  List<String> _previousNewsTexts = [];

  bool _isPaused = false;
  final Logger logger = Logger();

  bool _isAnimating = false;

  // 固定滾動速度 (邏輯像素/秒) — 這是唯一控制速度的地方
  static const double _fixedScrollSpeed = 50.0;

  // 防抖 Timer，確保只有最後一次數據變化才觸發重啟滾動
  Timer? _debounceTimer;
  // 第二階段防抖 Timer（等待 layout 穩定）
  Timer? _layoutTimer;

  // 一組新聞的寬度（用於循環跳回）
  double _oneGroupExtent = 0.0;

  @override
  void initState() {
    super.initState();
    // 初始化 AnimationController，duration 會在 _startScrolling 中設置
    _animationController = AnimationController(
      vsync: this,
    );
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _layoutTimer?.cancel();
    _stopScrolling();
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  ///1, 啟動滾動（AnimationController 驅動，Duration 預計算）
  void _startScrolling() {
    if (!_scrollController.hasClients || _isAnimating) return;

    final maxScrollExtent = _scrollController.position.maxScrollExtent;

    // 等待 layout 完成
    if (maxScrollExtent <= 100) {
      logger.d('新聞跑馬燈 - maxScrollExtent 過小 '
          '($maxScrollExtent)，等待 layout...');
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && !_isAnimating && !_isPaused) {
          _startScrolling();
        }
      });
      return;
    }

    // 計算一組新聞的寬度（ListView itemCount = newsTexts * 3）
    _oneGroupExtent = maxScrollExtent / 3;

    // 預計算滾完一組所需的時長
    final durationSeconds = _oneGroupExtent / _fixedScrollSpeed;
    final duration = Duration(
      milliseconds: (durationSeconds * 1000).round(),
    );

    logger.d('新聞跑馬燈 [AnimationController] - '
        '速度: $_fixedScrollSpeed px/s, '
        '一組距離: ${_oneGroupExtent.toStringAsFixed(0)}px, '
        '預計耗時: ${durationSeconds.toStringAsFixed(1)}s, '
        '新聞: ${_newsTexts.length}條');

    // 重置到起點
    _scrollController.jumpTo(0);

    // 配置 AnimationController
    _animationController.duration = duration;
    _animationController.reset();

    _isAnimating = true;

    // 監聽動畫值變化，映射到 scrollController 的 offset
    _animationController.addListener(_onAnimationTick);

    // 監聽動畫狀態，完成後無縫循環
    _animationController.addStatusListener(_onAnimationStatus);

    // 開始線性動畫
    _animationController.forward();
  }

  ///1.1, 動畫值變化回調：將 animation.value 映射到滾動偏移
  void _onAnimationTick() {
    if (!_scrollController.hasClients || _isPaused) return;

    final offset = _animationController.value * _oneGroupExtent;
    final maxSE = _scrollController.position.maxScrollExtent;
    final safeOffset = offset.clamp(0.0, maxSE);
    _scrollController.jumpTo(safeOffset);
  }

  ///1.2, 動畫狀態回調：完成時跳回起點並重新播放（無縫循環）
  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      // 跳回起點，重新播放，實現無縫循環
      _scrollController.jumpTo(0);
      _animationController.reset();
      _animationController.forward();
    }
  }

  ///2, 停止滾動
  void _stopScrolling() {
    _isAnimating = false;
    _animationController.removeListener(_onAnimationTick);
    _animationController.removeStatusListener(_onAnimationStatus);
    _animationController.stop();
    _animationController.reset();
  }

  ///3, 更新新聞數據並重新啟動滾動（防抖版本）
  void _updateNews(List<String> newTexts) {
    if (newTexts.isEmpty) {
      _newsTexts = ['暫無新聞數據'];
    } else {
      _newsTexts = newTexts;
    }

    // 檢查內容是否真的發生了變化
    if (_newsTexts.length == _previousNewsTexts.length &&
        !_newsTexts
            .asMap()
            .entries
            .any((e) => e.value != _previousNewsTexts[e.key])) {
      return;
    }

    _previousNewsTexts = List.from(_newsTexts);

    // 取消之前的防抖 Timer
    _debounceTimer?.cancel();
    _layoutTimer?.cancel();

    // 第一層防抖：等待 300ms 讓數據穩定
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;

      setState(() {});

      // 等待 ListView 完成 layout 後再重啟滾動
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        // 停止現有動畫
        _stopScrolling();
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }

        // 第二層防抖：等待 500ms，確保 maxScrollExtent 穩定
        _layoutTimer?.cancel();
        _layoutTimer = Timer(const Duration(milliseconds: 500), () {
          if (mounted && !_isPaused) {
            _startScrolling();
          }
        });
      });
    });
  }

  ///5, 根據 Provider 狀態處理滾動控制
  void _handleProviderPauseState(bool isProviderPaused) {
    if (isProviderPaused && !_isPaused) {
      _pauseScrolling();
    } else if (!isProviderPaused && _isPaused) {
      _resumeScrolling();
    }
  }

  ///6, 暫停滾動
  void _pauseScrolling() {
    _isPaused = true;
    if (_isAnimating) {
      _animationController.stop();
    }
  }

  ///7, 恢復滾動
  void _resumeScrolling() {
    if (_isPaused && mounted) {
      _isPaused = false;
      if (_isAnimating) {
        // 從當前位置繼續播放
        _animationController.forward();
      } else {
        _startScrolling();
      }
    }
  }

  ///8, 智能確定顯示項目數量
  int _getItemCount() {
    if (_newsTexts.length == 1) {
      final textPainter = TextPainter(textDirection: TextDirection.ltr);
      textPainter.text = TextSpan(
        text: _newsTexts.first,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      );
      textPainter.layout();

      if (textPainter.width < widget.width - 160) {
        return 1;
      }
      return 3;
    }
    return _newsTexts.length * 3;
  }

  ///9, 構建漸變遮罩
  Widget _buildFadeMask(Widget child) => ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0.0, 0.08, 0.92, 1.0],
        ).createShader(bounds),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return Consumer<RthkNewsProvider>(
      builder: (context, newsProvider, child) {
        // 將副作用推遲到 build 完成後執行
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _handleProviderPauseState(newsProvider.isScrollingPaused);
          _updateNews(newsProvider.getAllNewsDisplayTexts());
        });

        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: Colors.blue.shade50.withOpacity(0.3),
            borderRadius: BorderRadius.circular(4),
          ),
          child: ClipRect(
            child: _buildFadeMask(
              ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _getItemCount(),
                itemBuilder: (context, index) {
                  final text = _newsTexts[index % _newsTexts.length];
                  return Container(
                    margin: const EdgeInsets.only(right: 80),
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
