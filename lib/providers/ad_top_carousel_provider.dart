import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/widgets/carousel_widget.dart' as custom_carousel;
import 'package:iboard_app/widgets/mainscreen/top_ad_widget.dart';
import 'package:logger/logger.dart';

class TopAdCarouselProvider extends ChangeNotifier {
  final Logger _logger = Logger();
  bool _mounted = true;

  // 轮播控制器
  late custom_carousel.CarouselController _topCarouselController;

  // 定时器
  Timer? _topTimer;
  Timer? _debugTimer;

  // 广告数据
  List<AdModel> _topAds = [];

  // Widget缓存机制
  final Map<String, Widget> _widgetCache = {};
  final Map<String, FileManager> _fileManagerCache = {};
  bool _pendingWidgetUpdate = false;

  // 状态管理
  bool _isTopCarouselPaused = false;

  // 时间记录相关 - 用于全屏广告暂停恢复
  DateTime? _currentTopAdStartTime; // 当前顶部广告开始时间
  DateTime? _currentTopAdPauseTime; // 当前顶部广告暂停时间
  Duration _topAdElapsedTime = Duration.zero; // 顶部广告已播放时间
  Duration _topAdDuration = const Duration(seconds: 15); // 顶部广告总时长
  int _currentTopAdIndex = 0; // 当前顶部广告索引

  // Getters
  custom_carousel.CarouselController get topCarouselController =>
      _topCarouselController;
  List<AdModel> get topAds => _topAds;
  bool get isTopCarouselPaused => _isTopCarouselPaused;
  Duration get topAdDuration => _topAdDuration;
  int get currentTopAdIndex => _currentTopAdIndex;
  DateTime? get currentTopAdStartTime => _currentTopAdStartTime;
  Duration get topAdElapsedTime => _topAdElapsedTime;

  TopAdCarouselProvider() {
    _topCarouselController = custom_carousel.CarouselController();
    _logger.i('🔍 TopAdCarouselProvider 初始化完成，轮播顺序由后台管理');
  }

  ///1，更新轮播广告列表（由AdvertisementProvider调用）
  void updateCarouselList(List<AdModel> newTopAds) {
    // 检查数据是否真的发生了变化
    if (_areAdsListsEqual(_topAds, newTopAds)) {
      _logger.d('顶部广告数据无变化，跳过更新');
      return;
    }

    _topAds = List<AdModel>.from(newTopAds);
    _logger.i('🔄 更新顶部广告轮播列表: ${newTopAds.length} 個廣告');

    // 智能更新：如果正在播放，延迟更新Widget
    if (!_isTopCarouselPaused && _topTimer != null && _topTimer!.isActive) {
      _pendingWidgetUpdate = true;
      _logger.i('🎬 檢測到正在播放頂部廣告，延遲更新Widget直到下次切換');
    } else {
      // 不在播放状态，可以安全更新
      _smartUpdateWidgets();
    }
    notifyListeners();
  }

  ///13，檢查緩存狀態並驗證數據完整性
  bool validateCacheData() {
    if (_topAds.isEmpty) {
      _logger.w('⚠️ 頂部廣告數據為空');
      return false;
    }

    // 檢查每個廣告的文件是否有效
    for (final ad in _topAds) {
      if (ad.file.url.isEmpty) {
        _logger.w('⚠️ 發現無效的廣告文件: ${ad.title}');
        return false;
      }
    }

    _logger.i('✅ 緩存數據驗證通過: ${_topAds.length} 個廣告');
    return true;
  }

  ///1a，检查两个广告列表是否相等
  bool _areAdsListsEqual(List<AdModel> list1, List<AdModel> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i].id != list2[i].id) return false;
    }
    return true;
  }

  ///2，清空轮播广告列表
  void clearCarouselList() {
    _topAds.clear();

    notifyListeners();
  }

  ///3，初始化顶部轮播
  void initializeTopWidgets(List<AdModel> topAds) {
    if (topAds.isEmpty) {
      _logger.w('No top advertisements available');
      return;
    }

    // 使用自定义顺序更新方法
    updateCarouselList(topAds);

    // 使用智能更新方法创建Widget
    _smartUpdateWidgets();

    if (this.topAds.length > 1) {
      startTopAdTimer(0); // Start timer for the first ad
    }
  }

  ///3a，智能更新Widget（避免重建正在播放的Widget）
  void _smartUpdateWidgets() {
    if (topAds.isEmpty) {
      return;
    }

    final Map<String, Widget> widgetMap = {};
    final List<String> orderedKeys = [];
    final Set<String> usedKeys = {};
    final currentIndex = _topCarouselController.currentIndex;

    for (int i = 0; i < topAds.length; i++) {
      final ad = topAds[i];
      final key = 'top_ad_${ad.id}';
      usedKeys.add(key);
      orderedKeys.add(key);

      // 如果是當前播放的廣告且Widget已存在，保持不變
      if (i == currentIndex && _widgetCache.containsKey(key)) {
        widgetMap[key] = _widgetCache[key]!;
        _logger.d('🔄 保持當前播放廣告Widget: ${ad.title}');
      } else if (_widgetCache.containsKey(key)) {
        // 其他已緩存的Widget也保持不變
        widgetMap[key] = _widgetCache[key]!;
      } else {
        // 只為新廣告創建Widget
        final widget = _createCachedAdWidget(ad);
        _widgetCache[key] = widget;
        widgetMap[key] = widget;
        _logger.d('🆕 創建新廣告Widget: ${ad.title}');
      }
    }

    // 清理不再使用的緩存
    _widgetCache.removeWhere((key, value) => !usedKeys.contains(key));
    _fileManagerCache.removeWhere((key, value) => !usedKeys.contains(key));

    _topCarouselController.smartUpdateCarousel(widgetMap, orderedKeys);
  }

  ///3b，创建缓存的广告Widget
  Widget _createCachedAdWidget(AdModel ad) {
    final key = 'top_ad_${ad.id}';

    // 重用或创建FileManager
    if (!_fileManagerCache.containsKey(key)) {
      _fileManagerCache[key] = FileManager();
    }
    final fileManager = _fileManagerCache[key]!;
    fileManager.getFile(ad.file);

    return SizedBox.expand(
      child: TopAdWidget(
        key: ValueKey(key),
        ad: ad,
        fileManager: fileManager,
      ),
    );
  }

  ///7，启动顶部广告计时器
  void startTopAdTimer(int currentIndex) {
    _topTimer?.cancel();
    if (topAds.length <= 1 ||
        currentIndex < 0 ||
        currentIndex >= topAds.length ||
        _isTopCarouselPaused) {
      return;
    }

    final ad = topAds[currentIndex];
    _currentTopAdStartTime = DateTime.now();
    _topAdDuration = ad.durationObject;
    _currentTopAdIndex = currentIndex;
    _topAdElapsedTime = Duration.zero;

    _topTimer = Timer(ad.durationObject, () {
      if (_topCarouselController.widgetCount > 1 && !_isTopCarouselPaused) {
        // 在播放下一個廣告之前檢查是否有待處理的更新（參考全屏廣告邏輯）
        if (_pendingWidgetUpdate) {
          _logger.i('🔄 執行延遲的Widget更新');
          _smartUpdateWidgets();
          _pendingWidgetUpdate = false;
        }

        _topCarouselController.playNext();
        // onPageChanged will then call startTopAdTimer for the new page
      }
    });
  }

  /// 暂停顶部轮播
  void pauseTopCarousel() {
    // _logger.i('🛑 暂停顶部轮播 - 进入全屏广告状态');

    // 记录当前播放时间
    _currentTopAdPauseTime = DateTime.now();

    // 计算已播放时间
    if (_currentTopAdStartTime != null) {
      final rawElapsed =
          _currentTopAdPauseTime!.difference(_currentTopAdStartTime!);
      // 加上之前的已播放时间（如果有的话）
      final totalElapsed = rawElapsed + _topAdElapsedTime;

      // 确保已播放时间不超过广告总时长
      if (totalElapsed >= _topAdDuration) {
        // 广告已经播放完成，应该准备切换到下一个
        _topAdElapsedTime = _topAdDuration;
        // _logger.i(
        //     '📊 [暂停] 顶部广告 - 已播放: ${_topAdElapsedTime.inSeconds}s/${_topAdDuration.inSeconds}s (广告已完成)');
      } else {
        // 广告还在播放中
        _topAdElapsedTime = totalElapsed;
        // _logger.i(
        //     '📊 [暂停] 顶部广告 - 已播放: ${_topAdElapsedTime.inSeconds}s/${_topAdDuration.inSeconds}s');
      }
    }

    // 设置顶部轮播为暂停状态
    _isTopCarouselPaused = true;

    // 暂停定时器
    _topTimer?.cancel();

    // 暂停轮播中的媒体内容
    _topCarouselController.pauseAllMedia();

    notifyListeners();
  }

  /// 恢复顶部轮播
  void resumeTopCarousel() {
    _topTimer?.cancel(); // 显式取消旧的定时器，避免重复计时或意外行为
    // _logger.i('▶️ 恢复顶部轮播 - 退出全屏广告状态');

    // 设置顶部轮播为运行状态
    _isTopCarouselPaused = false;

    // 恢复轮播中的媒体内容
    _topCarouselController.resumeAllMedia();

    // 计算剩余播放时间并恢复定时器
    if (topAds.isNotEmpty) {
      // 优先使用已记录的暂停恢复逻辑，确保从暂停位置继续
      if (_currentTopAdStartTime != null && _topAdElapsedTime.inSeconds > 0) {
        // 有暂停记录，从暂停位置继续播放
        final remainingTopTime = _topAdDuration - _topAdElapsedTime;
        // _logger.i(
        //     '🔄 [恢复] 顶部广告 - 从暂停位置继续：剩余${remainingTopTime.inSeconds}s (已播放: ${_topAdElapsedTime.inSeconds}s)');

        if (remainingTopTime.inSeconds > 0) {
          // 更新当前广告开始时间，使其能正确计算剩余时间
          _currentTopAdStartTime = DateTime.now();
          // 保持 _topAdElapsedTime 不变，这样调试定时器能正确显示从暂停位置继续的时间

          // 继续播放剩余时间
          _topTimer = Timer(remainingTopTime, () {
            if (!_isTopCarouselPaused) {
              // _logger.i('⏰ [定时] 顶部广告时间到，切换到下一个');
              _topCarouselController.playNext();
              // Note: onPageChanged will handle calling startTopAdTimer for the new page
            }
          });

          // _logger.i('✅ 顶部广告轮播已恢复：继续播放剩余时间 ${remainingTopTime.inSeconds}s');
        } else {
          // 时间已到，直接切换到下一个
          // _logger.i('⚡ [跳过] 顶部广告剩余时间为0，直接切换到下一个');
          _topCarouselController.playNext();
          // Note: onPageChanged will handle calling startTopAdTimer for the new page
        }
      } else {
        // 没有暂停记录或首次初始化，重新开始当前广告
        final currentIndex = _topCarouselController.currentIndex;
        if (currentIndex < topAds.length) {
          _currentTopAdStartTime = DateTime.now();
          _topAdDuration = topAds[currentIndex].durationObject;
          _currentTopAdIndex = currentIndex;
          _topAdElapsedTime = Duration.zero;

          // 启动新的定时器
          _topTimer = Timer(_topAdDuration, () {
            if (!_isTopCarouselPaused) {
              // _logger.i('⏰ [定时] 顶部广告时间到，切换到下一个');
              _topCarouselController.playNext();
              // Note: onPageChanged will handle calling startTopAdTimer for the new page
            }
          });

          // _logger.i('✅ 顶部广告轮播已恢复：重新初始化定时器，当前索引: $currentIndex');
        }
      }
    }

    notifyListeners();
  }

  /// 更新轮播暂停状态
  void updateCarouselPauseState(bool isPaused) {
    _isTopCarouselPaused = isPaused;
    // _logger.i('🎛️ 顶部轮播状态更新: ${!_isTopCarouselPaused ? "运行" : "暂停"}');
    notifyListeners();
  }

  ///8，检查并恢复轮播状态（监控定时器使用）
  void checkAndRestoreTopCarousel() {
    // _logger.i(
    //     '🔍 检查顶部广告恢复条件: ads=${this.topAds.length}, paused=$_isTopCarouselPaused');
    if (topAds.isNotEmpty && !_isTopCarouselPaused) {
      // 检查当前定时器是否活跃
      if (_topTimer == null || !_topTimer!.isActive) {
        // _logger.w('🔧 检测到顶部广告轮播中断，尝试恢复...');
        final currentIndex = _topCarouselController.currentIndex;
        // _logger.i('🔄 恢复顶部广告轮播，当前索引: $currentIndex');

        // 恢复视频播放
        _topCarouselController.resumeAllMedia();

        // 恢复定时器
        startTopAdTimer(currentIndex);

        // _logger.i('✅ 顶部广告轮播已恢复：视频播放 + 定时器');
      }
    } else {
      // _logger.w(
      //     '❌ 不满足恢复条件: ads=${this.topAds.length}, paused=$_isTopCarouselPaused');
    }
  }

  /// 启动调试定时器 - 每秒输出顶部广告的实时状态（已禁用）
  void startDebugTimer() {
    _debugTimer?.cancel();
    // 禁用顶部广告调试定时器以减少日志输出
    return;

    // _debugTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
    //   // 计算顶部广告剩余时间
    //   int topAdRemaining = 0;
    //   if (_currentTopAdStartTime != null) {
    //     if (_isTopCarouselPaused) {
    //       // 暂停状态：使用暂停时的剩余时间
    //       final remaining = _topAdDuration - _topAdElapsedTime;
    //       topAdRemaining = remaining.isNegative ? 0 : remaining.inSeconds;
    //     } else {
    //       // 运行状态：计算当前剩余时间
    //       final currentElapsed =
    //           DateTime.now().difference(_currentTopAdStartTime!);

    //       // 如果有已播放时间记录（说明经历了暂停恢复），需要加上之前的播放时间
    //       final totalElapsed = currentElapsed + _topAdElapsedTime;

    //       final remaining = _topAdDuration - totalElapsed;
    //       topAdRemaining = remaining.isNegative ? 0 : remaining.inSeconds;
    //     }
    //   }

    //   // 输出调试信息
    //   String statusInfo = '';
    //   if (_isTopCarouselPaused) {
    //     statusInfo = ' [暂停状态]';
    //   }

    //   _logger.i(
    //       '🕐 [调试] 顶部广告: ${topAdRemaining}s/${_topAdDuration.inSeconds}s$statusInfo');
    // });
  }

  /// 停止调试定时器
  void stopDebugTimer() {
    _debugTimer?.cancel();
  }

  ///9，处理页面变化事件
  void onPageChanged(int index) {
    if (!_isTopCarouselPaused && topAds.isNotEmpty) {
      startTopAdTimer(index);
    }
  }

  /// 暂停所有计时器（用于设置页面）
  void pauseAllTimersForSettings() {
    // _logger.i('⚙️ 顶部广告 - 暂停所有计时器（设置页面）');
    _topTimer?.cancel();
    _debugTimer?.cancel();
    _topCarouselController.pauseAllMedia();
    _isTopCarouselPaused = true;
    notifyListeners();
  }

  /// 从设置页面恢复所有计时器
  void resumeAllTimersFromSettings() {
    // _logger.i('↩️ 顶部广告 - 从设置页面恢复所有计时器');
    _isTopCarouselPaused = false;
    _topCarouselController.resumeAllMedia();

    // 恢复顶部广告轮播
    if (topAds.isNotEmpty) {
      int currentIndex = _topCarouselController.currentIndex;
      startTopAdTimer(currentIndex);
    }

    // 重新启动调试定时器
    startDebugTimer();

    notifyListeners();
  }

  bool get mounted => _mounted;

  @override
  void dispose() {
    _mounted = false;
    _topTimer?.cancel();
    _topTimer = null;
    _debugTimer?.cancel();
    _debugTimer = null;
    _widgetCache.clear();
    _fileManagerCache.clear();
    super.dispose();
  }
}
