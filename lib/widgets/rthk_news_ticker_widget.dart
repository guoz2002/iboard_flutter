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
  late AnimationController _controller;
  late ScrollController _scrollController;

  List<String> _newsTexts = [];
  List<String> _previousNewsTexts = [];

  bool _isPaused = false;
  double _totalContentWidth = 0;
  final Logger logger = Logger();
  
  // 监听器变量，确保正确移除
  VoidCallback? _animationListener;
  void Function(AnimationStatus)? _animationStatusListener;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    );
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _stopScrolling();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  ///1, 计算所有新闻文本的总宽度
  double _calculateTotalWidth(List<String> texts) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    double totalWidth = 0;

    for (final text in texts) {
      textPainter.text = TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      );
      textPainter.layout();
      // 为每条新闻添加足够的间距，确保完整显示
      totalWidth += textPainter.width + 80; // 增加间距从56到80
    }

    // 确保总宽度至少是容器宽度的2倍，保证滚动效果
    final minWidth = widget.width * 2;
    return totalWidth > minWidth ? totalWidth : minWidth;
  }

  ///2, 啟動滾動動畫
  void _startScrolling() {
    if (!_scrollController.hasClients || _isAnimating) return;

    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    
    // 🔧 修復：確保 maxScrollExtent 有效
    // 當 API 返回新數據後，ListView 可能還沒完成 layout
    // 此時 maxScrollExtent 會是 0 或很小的值，導致速度計算錯誤
    if (maxScrollExtent <= 100) {
      // 如果內容寬度太小，說明 layout 還沒完成，延遲重試
      logger.d('新聞跑馬燈 - maxScrollExtent 過小 ($maxScrollExtent)，等待 layout 完成...');
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && !_isAnimating && !_isPaused) {
          _startScrolling();
        }
      });
      return;
    }

    // 🔧 修復：使用固定的「螢幕寬度滾動時間」來計算速度
    // 這樣無論螢幕大小或內容多少，視覺速度感受都一致
    // 基準：內容滾過一個螢幕寬度需要 12 秒
    const double secondsPerScreenWidth = 12.0;
    
    final double containerWidth = widget.width > 0 ? widget.width : 1920.0;
    
    // 計算總滾動內容相當於多少個螢幕寬度
    final double totalScrollDistance = maxScrollExtent;
    final double screenWidths = totalScrollDistance / containerWidth;
    
    // 計算總動畫時間（至少要讓內容完整滾過一遍）
    final int durationSeconds = (screenWidths * secondsPerScreenWidth).ceil();
    
    // 設置合理的時長範圍 (15-300秒)
    final clampedDuration = durationSeconds.clamp(15, 300);
    _controller.duration = Duration(seconds: clampedDuration);

    // 計算實際像素速度（用於日誌）
    final double actualSpeed = maxScrollExtent / clampedDuration;

    // 添加調試信息
    logger.d('新聞跑馬燈 - 容器寬度: ${containerWidth.toStringAsFixed(0)}px, '
        '內容寬度: ${maxScrollExtent.toStringAsFixed(0)}px, '
        '螢幕數: ${screenWidths.toStringAsFixed(1)}, '
        '實際速度: ${actualSpeed.toStringAsFixed(1)}px/s, '
        '動畫時長: ${clampedDuration}s');

    // 先移除已有監聽器
    _removeListeners();

    // 定义新的监听器
    _animationListener = () {
      if (!_isPaused && _scrollController.hasClients) {
        final offset = _controller.value * maxScrollExtent;
        if (offset <= maxScrollExtent) {
          _scrollController.jumpTo(offset);
        }
      }
    };

    _animationStatusListener = (AnimationStatus status) {
      if (status == AnimationStatus.completed && mounted) {
        _controller.reset();
        if (!_isPaused) {
          _controller.forward();
        }
      }
    };

    // 添加新監聽器
    _controller.addListener(_animationListener!);
    _controller.addStatusListener(_animationStatusListener!);
    
    _isAnimating = true;
    _controller.forward();
  }

  ///3, 移除动画监听器
  void _removeListeners() {
    if (_animationListener != null) {
      _controller.removeListener(_animationListener!);
      _animationListener = null;
    }
    if (_animationStatusListener != null) {
      _controller.removeStatusListener(_animationStatusListener!);
      _animationStatusListener = null;
    }
  }

  ///4, 停止滚动动画
  void _stopScrolling() {
    _isAnimating = false;
    _controller.stop();
    _removeListeners();
  }

  ///5, 更新新聞數據並重新啟動滾動
  void _updateNews(List<String> newTexts) {
    if (newTexts.isEmpty) {
      _newsTexts = ['暫無新聞數據'];
    } else {
      _newsTexts = newTexts;
    }

    // 检查内容是否真的发生了变化
    if (_newsTexts.length == _previousNewsTexts.length &&
        !_newsTexts
            .asMap()
            .entries
            .any((e) => e.value != _previousNewsTexts[e.key])) {
      return;
    }

    _previousNewsTexts = List.from(_newsTexts);

    // 🔧 修復：增加防抖延遲，避免 API 返回時頻繁重置動畫
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;

      _totalContentWidth = _calculateTotalWidth(_newsTexts);
      
      setState(() {});

      // 🔧 修復：增加足夠的延遲確保 ListView 完成 layout
      // 這是解決「API 返回後速度變快」的關鍵
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        
        // 先停止現有動畫
        _stopScrolling();
        _controller.reset();
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
        
        // 🔧 額外延遲 500ms，確保 ListView 的 maxScrollExtent 已正確計算
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && !_isPaused) {
            _startScrolling();
          }
        });
      });
    });
  }

  ///6, 根据Provider状态处理滚动控制
  void _handleProviderPauseState(bool isProviderPaused) {
    if (isProviderPaused && !_isPaused) {
      _pauseScrolling();
    } else if (!isProviderPaused && _isPaused) {
      _resumeScrolling();
    }
  }

  ///7, 暂停滚动
  void _pauseScrolling() {
    _isPaused = true;
    _controller.stop();
  }

  ///8, 恢復滾動
  void _resumeScrolling() {
    if (_isPaused && mounted) {
      _isPaused = false;
      if (_isAnimating) {
        _controller.forward();
      } else {
        _startScrolling();
      }
    }
  }

  ///9, 智能确定显示项目数量
  int _getItemCount() {
    // 如果只有一条新闻（通常是网络错误提示），检查是否需要滚动
    if (_newsTexts.length == 1) {
      // 计算單条新闻的宽度
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

      // 如果單条新闻宽度小于容器宽度，不需要滚动，只显示一次
      if (textPainter.width < widget.width - 160) {
        // 减去左右边距
        return 1;
      }
      // 如果單条新闻很长，需要重复显示来实现滚动
      return 2;
    }
    // 如果有多条新闻，重复显示两次确保无缝循环
    return _newsTexts.length * 2;
  }

  ///10, 构建渐变遮罩，避免文字在边缘处突然出现或消失
  Widget _buildFadeMask(Widget child) => ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent
          ],
          stops: [0.0, 0.08, 0.92, 1.0], // 调整渐变范围，让文字显示更清晰
        ).createShader(bounds),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return Consumer<RthkNewsProvider>(
      builder: (context, newsProvider, child) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleProviderPauseState(newsProvider.isScrollingPaused);
        });

        _updateNews(newsProvider.getAllNewsDisplayTexts());

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
                itemCount: _getItemCount(), // 根據新聞數量智能決定顯示次數
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
