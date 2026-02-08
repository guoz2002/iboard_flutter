import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:iboard_app/models/settings_model.dart';
import 'package:iboard_app/providers/announcement_carousel_provider.dart';
import 'package:iboard_app/providers/ad_top_carousel_provider.dart';
import 'package:iboard_app/providers/ad_full_carousel_provider.dart';
import 'package:iboard_app/providers/rthk_news_provider.dart';

/// 播放狀態枚舉
enum PlaybackState {
  auto, // 自動播放
  paused, // 暫停播放
  manual, // 手動操作
}

/// 全局應用狀態枚舉
enum AppState {
  defaultState, // 默認播放狀態
  fullscreenAd, // 全屏廣告狀態
  manualOperation, // 手動操作狀態
}

/// 區域類型枚舉
enum AreaType {
  topAd, // 頂部廣告
  middleNotice, // 中間通告
  bottomArea, // 底部區域
  fullscreenAd, // 全屏廣告
}

/// 抽象狀態類，定義四個區域的狀態
abstract class CarouselState {
  PlaybackState get topAdState;
  PlaybackState get middleNoticeState;
  PlaybackState get bottomAreaState;
  PlaybackState get fullscreenAdState;

  AppState get currentAppState;

  /// 狀態轉換方法
  CarouselState toFullscreenAd();
  CarouselState toManualOperation();
  CarouselState toDefaultState();

  /// 檢查是否可以進行狀態轉換
  bool canTransitionTo(AppState targetState);

  /// 獲取指定區域的狀態
  PlaybackState getAreaState(AreaType area) {
    switch (area) {
      case AreaType.topAd:
        return topAdState;
      case AreaType.middleNotice:
        return middleNoticeState;
      case AreaType.bottomArea:
        return bottomAreaState;
      case AreaType.fullscreenAd:
        return fullscreenAdState;
    }
  }
}

///1， 默認播放狀態
class DefaultCarouselState extends CarouselState {
  @override
  PlaybackState get topAdState => PlaybackState.auto;

  @override
  PlaybackState get middleNoticeState => PlaybackState.auto;

  @override
  PlaybackState get bottomAreaState => PlaybackState.auto;

  @override
  PlaybackState get fullscreenAdState => PlaybackState.paused;

  @override
  AppState get currentAppState => AppState.defaultState;

  @override
  CarouselState toFullscreenAd() => FullscreenAdCarouselState();

  @override
  CarouselState toManualOperation() => ManualOperationCarouselState();

  @override
  CarouselState toDefaultState() => this;

  @override
  bool canTransitionTo(AppState targetState) {
    return targetState == AppState.fullscreenAd ||
        targetState == AppState.manualOperation ||
        targetState == AppState.defaultState;
  }
}

///2， 全屏廣告狀態
class FullscreenAdCarouselState extends CarouselState {
  @override
  PlaybackState get topAdState => PlaybackState.paused;

  @override
  PlaybackState get middleNoticeState => PlaybackState.paused;

  @override
  PlaybackState get bottomAreaState => PlaybackState.paused;

  @override
  PlaybackState get fullscreenAdState => PlaybackState.auto;

  @override
  AppState get currentAppState => AppState.fullscreenAd;

  @override
  CarouselState toFullscreenAd() => this;

  @override
  CarouselState toManualOperation() => ManualOperationCarouselState();

  @override
  CarouselState toDefaultState() => DefaultCarouselState();

  @override
  bool canTransitionTo(AppState targetState) {
    return targetState == AppState.manualOperation ||
        targetState == AppState.defaultState ||
        targetState == AppState.fullscreenAd;
  }
}

///3， 手動操作狀態
class ManualOperationCarouselState extends CarouselState {
  @override
  PlaybackState get topAdState => PlaybackState.auto;

  @override
  PlaybackState get middleNoticeState => PlaybackState.manual;

  @override
  PlaybackState get bottomAreaState => PlaybackState.auto;

  @override
  PlaybackState get fullscreenAdState => PlaybackState.paused;

  @override
  AppState get currentAppState => AppState.manualOperation;

  @override
  CarouselState toFullscreenAd() => FullscreenAdCarouselState();

  @override
  CarouselState toManualOperation() => this;

  @override
  CarouselState toDefaultState() {
    // 手動狀態不能直接轉換到默認狀態
    throw StateError(
        'Cannot transition from manual operation to default state directly');
  }

  @override
  bool canTransitionTo(AppState targetState) {
    return targetState == AppState.fullscreenAd ||
        targetState == AppState.manualOperation;
  }
}

/// 狀態提供者類
class CarouselStateProvider extends ChangeNotifier {
  CarouselState _currentState = DefaultCarouselState();

  // 计时器相關
  Timer? _fullscreenAdTimer; // 全屏廣告計時器
  Timer? _manualOperationTimer; // 手動操作計時器
  Timer? _defaultStateTimer; // 默認狀態計時器

  // 通告轮播定时器相关
  Timer? _noticeCarouselTimer; // 通告轮播定时器
  Timer? _noticeLogTimer; // 通告log输出定时器
  bool _isNoticeCarouselActive = false; // 通告轮播是否激活
  bool _isNoticeCarouselPaused = false; // 通告轮播是否暂停
  DateTime? _noticeTimerStartTime; // 通告定时器开始时间
  Duration _noticeElapsedTime = Duration.zero; // 通告已经过时间
  VoidCallback? _onNoticeCarouselNext; // 通告轮播下一个回调

  // 時間記錄
  DateTime? _lastUserInteractionTime; // 最後用戶操作時間
  DateTime? _lastTimerResetTime; // 最後定時器重置時間（用於節流）

  // 状态切换控制
  bool _isStateTransitioning = false; // 状态是否正在切换中

  // 回調函數
  VoidCallback? _onShowFullscreenAd; // 顯示全屏廣告的回調
  VoidCallback? _onCloseFullscreenAd; // 關閉全屏廣告的回調

  // Provider引用
  AnnouncementCarouselProvider? _announcementCarouselProvider; // 通告轮播Provider引用
  TopAdCarouselProvider? _topCarouselProvider; // 顶部广告轮播Provider引用
  FullscreenAdProvider? _fullscreenAdProvider; // 全屏广告轮播Provider引用
  RthkNewsProvider? _rthkNewsProvider; // RTHK新闻Provider引用

  // 媒體控制狀態 - 按區域分別控制
  bool _isTopMediaPaused = false; // 頂部廣告媒體暫停狀態
  bool _isMiddleMediaPaused = false; // 中部通告媒體暫停狀態
  bool _isBottomMediaPaused = false; // 底部區域媒體暫停狀態（包括天气和二维码轮播）

  // 時間配置（從服務器獲取，帶默認值）
  Settings? _settings;

  /// 更新時間配置
  void updateSettings(Settings? settings) {
    _settings = settings;
  }

  /// 獲取全屏廣告状态总时间（秒）
  int get fullscreenAdDuration {
    final duration = _settings?.advertisementPlayDuration;
    return duration != null && duration > 0 ? duration : 30;
  }

  /// 獲取手動操作超時時間（秒） - 使用normalToAnnouncementCarouselDuration
  int get manualOperationTimeout {
    final duration = _settings?.normalToAnnouncementCarouselDuration;
    return duration != null && duration > 0 ? duration : 10;
  }

  // /// 獲取無操作進入全屏廣告時間（秒） - normalToAnnouncementCarouselDuration
  // int get noActivityTimeout {
  //   final duration = _settings?.normalToAnnouncementCarouselDuration;
  //   return duration != null && duration > 0
  //       ? duration
  //       : _defaultNoActivityTimeout;
  // }

  /// 獲取每個公告停留時間（秒） - 每一個公告在輪播模式停留的時間
  int get noticeStayDuration {
    final duration = _settings?.noticeStayDuration;
    return duration != null && duration > 0 ? duration : 5;
  }

  /// 獲取通告輪播到全屏廣告輪播轉換時間（秒）
  int get announcementCarouselToFullAdsCarouselDuration {
    final duration = _settings?.announcementCarouselToFullAdsCarouselDuration;
    return duration != null && duration > 0 ? duration : 40;
  }

  /// 獲取正常到通告輪播轉換時間（秒）
  int get normalToAnnouncementCarouselDuration {
    final duration = _settings?.normalToAnnouncementCarouselDuration;
    return duration != null && duration > 0 ? duration : 10;
  }

  /// 設置全屏廣告顯示回調
  void setFullscreenAdCallback(VoidCallback? callback) {
    _onShowFullscreenAd = callback;
  }

  /// 設置全屏廣告關閉回調
  void setCloseFullscreenAdCallback(VoidCallback? callback) {
    _onCloseFullscreenAd = callback;
  }

  /// 設置通告轮播下一个回调
  void setNoticeCarouselNextCallback(VoidCallback? callback) {
    _onNoticeCarouselNext = callback;
  }

  /// 設置通告轮播Provider引用
  void setAnnouncementCarouselProvider(AnnouncementCarouselProvider? provider) {
    _announcementCarouselProvider = provider;
  }

  /// 设置顶部广告轮播Provider引用
  void setTopCarouselProvider(TopAdCarouselProvider? provider) {
    _topCarouselProvider = provider;
  }

  /// 设置全屏广告轮播Provider引用
  void setFullscreenAdProvider(FullscreenAdProvider? provider) {
    _fullscreenAdProvider = provider;
  }

  /// 设置RTHK新闻Provider引用
  void setRthkNewsProvider(RthkNewsProvider? provider) {
    _rthkNewsProvider = provider;
  }

  /// 獲取當前狀態
  CarouselState get currentState => _currentState;

  /// 獲取當前應用狀態
  AppState get currentAppState => _currentState.currentAppState;

  /// 獲取指定區域的播放狀態
  PlaybackState getAreaState(AreaType area) {
    return _currentState.getAreaState(area);
  }

  /// 獲取通告轮播是否激活
  bool get isNoticeCarouselActive => _isNoticeCarouselActive;

  /// 獲取通告轮播是否暂停
  bool get isNoticeCarouselPaused => _isNoticeCarouselPaused;

  /// 獲取媒體暫停狀態 - 按區域
  bool isMediaPausedForArea(AreaType area) {
    switch (area) {
      case AreaType.topAd:
        return _isTopMediaPaused;
      case AreaType.middleNotice:
        return _isMiddleMediaPaused;
      case AreaType.bottomArea:
        return _isBottomMediaPaused;
      case AreaType.fullscreenAd:
        return false; // 全屏廣告自己控制
    }
  }

  ///1， 更新媒體狀態基於當前應用狀態
  void _updateMediaStateBasedOnCurrentState() {
    switch (_currentState.currentAppState) {
      case AppState.defaultState:
        _isTopMediaPaused = false;
        _isMiddleMediaPaused = false;
        _isBottomMediaPaused = false;
        break;
      case AppState.fullscreenAd:
        _isTopMediaPaused = true;
        _isMiddleMediaPaused = true;
        _isBottomMediaPaused = true;
        break;
      case AppState.manualOperation:
        _isTopMediaPaused = false;
        _isMiddleMediaPaused = true;
        _isBottomMediaPaused = false;
        break;
    }
  }

  ///2， 暫停所有媒體 (向後兼容)
  void pauseAllMedia() {
    _isTopMediaPaused = true;
    _isMiddleMediaPaused = true;
    _isBottomMediaPaused = true;
    notifyListeners();
  }

  ///3， 恢復所有媒體 (向後兼容)
  void resumeAllMedia() {
    _updateMediaStateBasedOnCurrentState();
    notifyListeners();
  }

  // 🔧 調試開關：禁用全屏廣告模式
  static const bool _debugDisableFullscreenAd = false;

  ///4， 切換到全屏廣告狀態
  void enterFullscreenAd() {
    // 🔧 調試模式：跳過全屏廣告
    if (_debugDisableFullscreenAd) {
      debugPrint('[StateProvider] 🔧 調試模式：跳過全屏廣告');
      return;
    }

    if (_currentState.canTransitionTo(AppState.fullscreenAd)) {
      // 🔧 修复：设置状态切换标志，防止竞争条件
      _isStateTransitioning = true;

      _clearFullManualDefaultTimers();

      // 暂停通告轮播定时器
      if (_isNoticeCarouselActive) {
        _pauseNoticeCarousel();
      }

      _currentState = _currentState.toFullscreenAd();
      _topCarouselProvider?.pauseTopCarousel();

      // 暂停RTHK新闻跑马灯
      _rthkNewsProvider?.pauseScrolling();

      // 更新媒體狀態
      _updateMediaStateBasedOnCurrentState();

      // 启动全屏广告状态总时长定时器
      _startFullscreenAdTimer();

      // 直接调用FullscreenAdProvider进入全屏广告模式
      _fullscreenAdProvider?.enterFullscreenMode();

      notifyListeners();

      // 調用顯示全屏廣告的回調
      _onShowFullscreenAd?.call();

      // 🔧 修复：延迟重置状态切换标志，给UI足够时间完成更新
      Future.delayed(const Duration(milliseconds: 500), () {
        _isStateTransitioning = false;
      });
    }
  }

  ///5， 切換到手動操作狀態
  void enterManualOperation() {
    if (_currentState.canTransitionTo(AppState.manualOperation)) {
      // 🔧 修复：设置状态切换标志，防止竞争条件
      _isStateTransitioning = true;

      // 🔧 修复：在进入手动操作模式前，保存当前轮播状态（不退出独立通告模式）
      if (_announcementCarouselProvider != null) {
        // 检查是否在独立通告模式
        final isInIndependentMode =
            _announcementCarouselProvider!.isInIndependentAnnouncementMode;
        debugPrint('[StateProvider] 🔍 进入手动操作前检查独立通告模式: $isInIndependentMode');

        if (isInIndependentMode) {
          debugPrint('[StateProvider] 📝 在独立通告模式下进入手动操作，保持独立模式状态');
          // 在独立通告模式下，我们仍然需要保存轮播状态，但不退出独立模式
          // 独立模式的退出将在手动操作超时后处理
        }

        // 无论是否在独立模式，都保存当前的轮播状态
        _announcementCarouselProvider!.saveManualOperationState();
      }

      // 在状态切换前记录之前的状态
      bool wasInFullscreenAd =
          _currentState.currentAppState == AppState.fullscreenAd;

      if (wasInFullscreenAd) {
        _fullscreenAdProvider?.exitFullscreenMode();
      }

      _clearFullManualDefaultTimers();
      _currentState = _currentState.toManualOperation();
      _lastUserInteractionTime = DateTime.now();

      // 如果是从全屏广告状态切换过来，恢复其他组件
      if (wasInFullscreenAd) {
        // 恢复顶部广告轮播
        _topCarouselProvider?.resumeFromFullscreenAdExit();

        // 恢复RTHK新闻跑马灯
        _rthkNewsProvider?.resumeScrolling();
      }

      // 更新媒體狀態
      _updateMediaStateBasedOnCurrentState();

      _startManualOperationTimer();
      notifyListeners();

      debugPrint('[StateProvider] 🔄 已进入手动操作模式');

      // 🔧 修复：延迟重置状态切换标志，给UI足够时间完成更新
      Future.delayed(const Duration(milliseconds: 500), () {
        _isStateTransitioning = false;
      });
    }
  }

  ///6， 切換到默認狀態
  Future<void> enterDefaultState() async {
    if (_currentState.canTransitionTo(AppState.defaultState)) {
      // 🔧 修复：设置状态切换标志，防止竞争条件
      _isStateTransitioning = true;

      bool wasInFullscreenAd =
          _currentState.currentAppState == AppState.fullscreenAd;

      if (wasInFullscreenAd) {
        await _fullscreenAdProvider?.exitFullscreenMode();
      }

      _clearFullManualDefaultTimers();
      _currentState = _currentState.toDefaultState();

      if (wasInFullscreenAd) {
        // 恢复顶部广告轮播（修复音视频不同步问题）
        _topCarouselProvider?.resumeFromFullscreenAdExit();

        _rthkNewsProvider?.resumeScrolling();
      }

      _updateMediaStateBasedOnCurrentState();

      _startDefaultStateTimer();
      notifyListeners();

      _onCloseFullscreenAd?.call();

      _isStateTransitioning = false;
    }
  }

  ///6a， 進入通告輪播模式（從手動操作狀態恢復）
  void _enterAnnouncementCarouselMode() {
    debugPrint('[StateProvider] 🚀 开始进入通告轮播模式...');
    _clearFullManualDefaultTimers();

    _isTopMediaPaused = false;
    _isMiddleMediaPaused = false;
    _isBottomMediaPaused = false;

    // 🔧 修复：手动操作超时后，先退出独立通告模式，再恢复正常轮播内容
    debugPrint(
        '[StateProvider] 🔍 检查AnnouncementCarouselProvider是否存在: ${_announcementCarouselProvider != null}');
    if (_announcementCarouselProvider != null) {
      try {
        // 检查独立通告模式状态
        debugPrint('[StateProvider] 🔍 开始检查独立通告模式状态...');
        final isInIndependentMode =
            _announcementCarouselProvider!.isInIndependentAnnouncementMode;
        debugPrint(
            '[StateProvider] 🔍 手动操作超时，检查独立通告模式状态: $isInIndependentMode');

        if (isInIndependentMode) {
          debugPrint('[StateProvider] 🔄 手动操作超时，退出独立通告模式并恢复轮播');
          _announcementCarouselProvider!.exitIndependentAnnouncementMode();

          // 延迟一小段时间确保独立模式完全退出，然后恢复轮播
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_announcementCarouselProvider != null) {
              final hasContent =
                  _announcementCarouselProvider!.hasCarouselContent;
              if (hasContent) {
                _announcementCarouselProvider!.updateCarouselPauseState(false);
                _announcementCarouselProvider!.resumeMidCarousel(
                    noticeStayDuration,
                    forceJumpToIndex: false,
                    isFromManualOperation: true);
              }
            }

            // 启动通告轮播到全屏广告的计时器
            _startAnnouncementCarouselToFullscreenAdTimer();

            // 设置状态并通知
            _currentState = DefaultCarouselState();
            notifyListeners();

            debugPrint('[StateProvider] ✅ 已从独立通告模式恢复到通告轮播模式');
          });
          return; // 提前返回，延迟处理恢复逻辑
        } else {
          debugPrint('[StateProvider] ℹ️ 不在独立通告模式，直接恢复轮播');
        }
      } catch (e) {
        debugPrint('[StateProvider] ❌ 检查或退出独立通告模式时出错: $e');
        // 出错时强制恢复轮播
      }

      final hasContent = _announcementCarouselProvider!.hasCarouselContent;

      if (hasContent) {
        _announcementCarouselProvider!.updateCarouselPauseState(false);
        _announcementCarouselProvider!.resumeMidCarousel(noticeStayDuration,
            forceJumpToIndex: false, isFromManualOperation: true);
      }
    } else {
      debugPrint(
          '[StateProvider] ⚠️ AnnouncementCarouselProvider为null，无法处理独立通告模式');
    }

    // 启动通告轮播到全屏广告的计时器
    _startAnnouncementCarouselToFullscreenAdTimer();

    _currentState = DefaultCarouselState();

    notifyListeners();

    debugPrint('[StateProvider] ✅ 已进入通告轮播模式');
    debugPrint('[StateProvider] 🏁 _enterAnnouncementCarouselMode方法执行完成');
  }

  ///7， 用戶交互更新（重置手動操作計時器）
  void onUserInteraction() {
    final now = DateTime.now();

    // 🔧 已取消：移除状态切换中的用户交互阻止机制
    // 原先會在狀態切換時阻止用戶交互，現在允許立即響應

    if (_currentState.currentAppState == AppState.manualOperation) {
      _lastUserInteractionTime = now;
      // 添加节流机制：只有在距离上次重置定时器1秒后才允许重置
      if (_lastTimerResetTime == null ||
          now.difference(_lastTimerResetTime!).inSeconds >= 1) {
        _lastTimerResetTime = now;
        _resetManualOperationTimer();
      }
    } else {
      // 🔧 修复：添加防误判逻辑，避免在状态切换过程中误触发手动操作
      // 只有在默认状态且距离上次全屏广告结束超过2秒时，才切换到手动状态
      if (_currentState.currentAppState == AppState.defaultState) {
        // 🔧 已取消：移除全屏广告状态切换后的保护时间机制
        // 原先有5秒保护时间，现在允许立即响应用户交互
      }

      // 只有在默认状态下才允许切换到手动操作状态
      if (_currentState.currentAppState == AppState.defaultState) {
        _lastTimerResetTime = now;
        enterManualOperation();
      }
    }
  }

  ///8， 启动全屏广告状态定时器
  void _startFullscreenAdTimer() {
    _fullscreenAdTimer?.cancel();
    final duration = Duration(seconds: fullscreenAdDuration);
    _fullscreenAdTimer = Timer(duration, () async {
      if (_currentState.currentAppState == AppState.fullscreenAd) {
        await enterDefaultState();
      }
    });
  }

  ///9， 啟動手動操作計時器（使用配置的手動操作超時時間）
  void _startManualOperationTimer() {
    _manualOperationTimer?.cancel();
    final duration = Duration(seconds: normalToAnnouncementCarouselDuration);
    _manualOperationTimer = Timer(duration, () {
      if (_currentState.currentAppState == AppState.manualOperation) {
        _enterAnnouncementCarouselMode();
      }
    });
  }

  ///10， 重置手動操作計時器
  void _resetManualOperationTimer() {
    if (_currentState.currentAppState == AppState.manualOperation) {
      _startManualOperationTimer();
    }
  }

  ///11， 啟動默認狀態計時器（使用通告輪播到全屏廣告的時間配置）
  void _startDefaultStateTimer() {
    _defaultStateTimer?.cancel();
    final duration =
        Duration(seconds: announcementCarouselToFullAdsCarouselDuration);
    _defaultStateTimer = Timer(duration, () {
      if (_currentState.currentAppState == AppState.defaultState) {
        enterFullscreenAd();
      }
    });
  }

  ///11a， 啟動通告輪播到全屏廣告的計時器
  void _startAnnouncementCarouselToFullscreenAdTimer() {
    _defaultStateTimer?.cancel();
    final duration =
        Duration(seconds: announcementCarouselToFullAdsCarouselDuration);

    _defaultStateTimer = Timer(duration, () {
      if (_currentState.currentAppState == AppState.defaultState) {
        enterFullscreenAd();
      }
    });
  }

  ///12， 清除全屏、手动和默认状态计时器
  void _clearFullManualDefaultTimers() {
    _fullscreenAdTimer?.cancel();
    _fullscreenAdTimer = null;

    _manualOperationTimer?.cancel();
    _manualOperationTimer = null;

    _defaultStateTimer?.cancel();
    _defaultStateTimer = null;
  }

  ///13， 檢查是否可以轉換到指定狀態
  bool canTransitionTo(AppState targetState) {
    return _currentState.canTransitionTo(targetState);
  }

  ///14， 嘗試狀態轉換，返回是否成功
  Future<bool> tryTransitionTo(AppState targetState) async {
    try {
      switch (targetState) {
        case AppState.defaultState:
          await enterDefaultState();
          return true;
        case AppState.fullscreenAd:
          enterFullscreenAd();
          return true;
        case AppState.manualOperation:
          enterManualOperation();
          return true;
      }
    } catch (e) {
      return false;
    }
  }

  ///15， 重置到默認狀態（強制重置，忽略轉換規則）
  void resetToDefault() {
    _clearFullManualDefaultTimers();
    _currentState = DefaultCarouselState();
    _lastTimerResetTime = null; // 重置節流計時器
    _startDefaultStateTimer();
    notifyListeners();
  }

  ///16， 獲取狀態描述（用於調試）
  String getStateDescription() {
    final now = DateTime.now();
    String timerInfo = '';

    switch (_currentState.currentAppState) {
      case AppState.fullscreenAd:
        timerInfo =
            'Fullscreen ad state timer: active (${fullscreenAdDuration}s timeout)';
        break;
      case AppState.manualOperation:
        if (_lastUserInteractionTime != null) {
          final timeSinceInteraction =
              now.difference(_lastUserInteractionTime!).inSeconds;
          timerInfo =
              'Manual operation timer: ${manualOperationTimeout - timeSinceInteraction}s remaining';
        }
        break;
      case AppState.defaultState:
        timerInfo =
            'Default state timer: ${announcementCarouselToFullAdsCarouselDuration}s remaining';
        break;
    }

    return '''
Current App State: ${currentAppState.name}
Top Ad: ${_currentState.topAdState.name}
Middle Notice: ${_currentState.middleNoticeState.name}
Bottom Area: ${_currentState.bottomAreaState.name}
Fullscreen Ad: ${_currentState.fullscreenAdState.name}
Timer Info: $timerInfo
''';
  }

  ///17， 釋放資源
  @override
  void dispose() {
    _clearFullManualDefaultTimers();
    _clearNoticeCarouselTimers();
    super.dispose();
  }

  ///26， 暂停所有状态定时器（用于设置頁面等场景）
  void pauseAllStateTimers() {
    _clearFullManualDefaultTimers();
    _clearNoticeCarouselTimers();

    // 重置用户交互时间和节流时间
    _lastUserInteractionTime = null;
    _lastTimerResetTime = null; // 重置節流計時器
  }

  ///18， 清除通告轮播定时器
  void _clearNoticeCarouselTimers() {
    _noticeCarouselTimer?.cancel();
    _noticeCarouselTimer = null;

    _noticeLogTimer?.cancel();
    _noticeLogTimer = null;
  }

  ///19， 启动通告轮播
  void startNoticeCarousel() {
    if (_isNoticeCarouselActive) {
      return;
    }

    _isNoticeCarouselActive = true;
    _isNoticeCarouselPaused = false;
    _noticeTimerStartTime = DateTime.now();
    _noticeElapsedTime = Duration.zero;

    _startNoticeCarouselTimer();
    _startNoticeLogTimer();

    notifyListeners();
  }

  ///20， 停止通告轮播
  void stopNoticeCarousel() {
    if (!_isNoticeCarouselActive) return;

    _isNoticeCarouselActive = false;
    _isNoticeCarouselPaused = false;
    _clearNoticeCarouselTimers();

    notifyListeners();
  }

  ///21， 暂停通告轮播
  void _pauseNoticeCarousel() {
    if (!_isNoticeCarouselActive || _isNoticeCarouselPaused) return;

    _isNoticeCarouselPaused = true;

    // 计算已过时间
    if (_noticeTimerStartTime != null) {
      _noticeElapsedTime = DateTime.now().difference(_noticeTimerStartTime!);
    }

    _clearNoticeCarouselTimers();
  }

  ///22， 恢复通告轮播
  ///23， 启动通告轮播定时器
  void _startNoticeCarouselTimer([Duration? customDuration]) {
    _noticeCarouselTimer?.cancel();

    final duration = customDuration ?? Duration(seconds: noticeStayDuration);

    _noticeCarouselTimer = Timer(duration, () {
      if (_isNoticeCarouselActive && !_isNoticeCarouselPaused) {
        _onNoticeCarouselNext?.call();
        _resetNoticeTimer();
      }
    });
  }

  ///24， 启动通告Log输出定时器
  void _startNoticeLogTimer() {
    _noticeLogTimer?.cancel();

    _noticeLogTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isNoticeCarouselActive || _isNoticeCarouselPaused) {
        timer.cancel();
        return;
      }

      if (_noticeTimerStartTime != null) {
        final elapsed = DateTime.now().difference(_noticeTimerStartTime!) +
            _noticeElapsedTime;
        final remaining = Duration(seconds: noticeStayDuration) - elapsed;
        final remainingSeconds = remaining.isNegative ? 0 : remaining.inSeconds;
        remainingSeconds; // 避免未使用变量警告
      }
    });
  }

  ///25， 重置通告定时器状态
  void _resetNoticeTimer() {
    _noticeTimerStartTime = DateTime.now();
    _noticeElapsedTime = Duration.zero;
    _startNoticeCarouselTimer();
  }
}
