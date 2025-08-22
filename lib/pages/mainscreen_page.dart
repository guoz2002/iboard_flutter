import 'dart:async'; // Added import for Timer

import 'package:flutter/foundation.dart'
    show listEquals; // Added import for listEquals
import 'package:flutter/material.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/providers/advertisement_provider.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:iboard_app/providers/announcement_carousel_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:iboard_app/providers/ad_top_carousel_provider.dart';
import 'package:iboard_app/providers/ad_full_carousel_provider.dart';
import 'package:iboard_app/providers/weather_provider.dart';
import 'package:iboard_app/providers/rthk_news_provider.dart';
import 'package:iboard_app/widgets/carousel_widget.dart' as custom_carousel;
import 'package:iboard_app/widgets/mainscreen/bottom_display/bottom_display_widget.dart';
import 'package:iboard_app/widgets/rthk_news_ticker_widget.dart';
// ArrearDisplayWidget已删除，功能整合到MainScreenWidget
import 'package:iboard_app/widgets/mainscreen/main_display/arrear_table_widget.dart';
import 'package:iboard_app/pages/settings_page.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/arrear_provider.dart';

class AnnouncementPage extends StatefulWidget {
  const AnnouncementPage({super.key});

  @override
  AnnouncementPageState createState() => AnnouncementPageState();
}

class AnnouncementPageState extends State<AnnouncementPage> {
  final Logger _logger = Logger();
  late custom_carousel.CarouselController _bottomCarouselController;

  Timer? _bottomTimer;
  Timer? _debugTimer; // 添加调试定时器
  Timer? _watchdogTimer; // 添加监控定时器
  List<AnnouncementModel>?
      _previousAnnouncementsForBuild; // Added state variable
  List<AdModel>? _previousAdvertisementsForBuild; // Added for ad tracking

  // 轮播暂停状态管理 - 按区域分别控制
  bool _isBottomCarouselPaused = false;
  AppState? _previousAppState;
  AppState? _lastLoggedAppState; // 添加用于追踪上次记录的应用状态

  // 设备ID点击计数相关
  int _deviceIdClickCount = 0; // 设备ID点击次数
  Timer? _clickResetTimer; // 点击重置定时器

  // 欠费组件的GlobalKey，用于调用组件方法
  // ArrearDisplayWidget已删除，功能整合到MainScreenWidget
  final GlobalKey<ArrearTableWidgetState> _arrearTableKey =
      GlobalKey<ArrearTableWidgetState>();
  late ArrearProvider _arrearProvider;

  ///1， 根据当前应用状态更新轮播暂停状态
  void _updateCarouselStateBasedOnAppState(AppState appState) {
    // 使用 addPostFrameCallback 延迟执行状态更新，避免在构建过程中调用 setState()
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final topAdProvider = context.read<TopAdCarouselProvider>();
      final announcementCarouselProvider =
          context.read<AnnouncementCarouselProvider>();
      final bottomProvider = context.read<WeatherProvider>();

      // 检查状态是否发生变化
      if (_previousAppState != appState) {
        _previousAppState = appState;

        // 如果从全屏广告状态切换到手动操作状态，确保回到主屏幕
        if (appState == AppState.manualOperation) {
          announcementCarouselProvider.jumpToAnnouncementIndex(0);
        }
        
        // 如果从全屏广告状态切换到默认状态，确保从主屏幕开始轮播
        if (appState == AppState.defaultState && _previousAppState == AppState.fullscreenAd) {
          // 不需要跳转到主屏幕，因为resumeMidCarousel会处理索引恢复
        }
      }

      switch (appState) {
        case AppState.defaultState:
          // 默认状态：所有轮播都正常播放
          topAdProvider.updateCarouselPauseState(false);
          announcementCarouselProvider.updateCarouselPauseState(false);
          bottomProvider.updateCarouselPauseState(false);
          _isBottomCarouselPaused = false;
          break;
        case AppState.fullscreenAd:
          // 全屏广告状态：所有轮播都暂停
          topAdProvider.updateCarouselPauseState(true);
          announcementCarouselProvider.updateCarouselPauseState(true);
          bottomProvider.updateCarouselPauseState(true);
          _isBottomCarouselPaused = true;
          break;
        case AppState.manualOperation:
          // 手动操作状态：顶部和底部继续，中部暂停
          topAdProvider.updateCarouselPauseState(false);
          announcementCarouselProvider.updateCarouselPauseState(true);
          bottomProvider.updateCarouselPauseState(false);
          _isBottomCarouselPaused = false;
          break;
      }

      // _logger.i(
      //     '🎛️ 轮播状态更新[${appState.name}]: Top=${!topAdProvider.isTopCarouselPaused ? "运行" : "暂停"}, Mid=${!announcementCarouselProvider.isMidCarouselPaused ? "运行" : "暂停"}, Bottom=${!bottomProvider.isBottomCarouselPaused ? "运行" : "暂停"}');
    });
  }

  @override

  ///2， 初始化状态
  void initState() {
    super.initState();
    _bottomCarouselController = custom_carousel.CarouselController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 设置全屏广告预加载回调
      _setupFullscreenAdPreloadCallback();

      _initializeMidWidgets();
      _initializeTopWidgets();
      _initializeBottomWidgets();
      _initializeNewsAnnouncements(); // 初始化新闻公报
      _startDebugTimer(); // 启动调试定时器
      _startCarouselWatchdog(); // 启动轮播监控

      // Trigger data fetching
      final advertisementProvider =
          Provider.of<AdvertisementProvider>(context, listen: false);
      advertisementProvider.fetchAdvertisements();
    });

    // 初始化 _arrearProvider
    _arrearProvider = Provider.of<ArrearProvider>(context, listen: false);
    // 将 _arrearProvider 传递给 AnnouncementCarouselProvider
    final announcementCarouselProvider =
        Provider.of<AnnouncementCarouselProvider>(context, listen: false);
    announcementCarouselProvider.setArrearProvider(_arrearProvider);
  }

  ///2.1，初始化RTHK新闻
  void _initializeNewsAnnouncements() {
    final rthkNewsProvider = context.read<RthkNewsProvider>();

    // 启动RTHK新闻的定时更新
    rthkNewsProvider.fetchRthkNews();

    _logger.i('📰 RTHK新闻初始化完成');
  }

  ///2，设置全屏广告预加载回调
  void _setupFullscreenAdPreloadCallback() {
    final stateProvider = context.read<CarouselStateProvider>();
    final fullAdProvider = context.read<FullscreenAdProvider>();

    // 设置预加载回调
    stateProvider.setPreloadFullscreenAdCallback(() async {});

    // 设置进入全屏广告模式回调
    stateProvider.setEnterFullscreenAdModeCallback(() {
      fullAdProvider.enterFullscreenMode();
    });

    // 设置退出全屏广告模式回调
    stateProvider.setExitFullscreenAdModeCallback(() {
      fullAdProvider.exitFullscreenMode();
    });
  }

  @override

  ///3， 释放资源
  void dispose() {
    _bottomTimer?.cancel();
    _bottomTimer = null;

    _debugTimer?.cancel();
    _debugTimer = null;

    _watchdogTimer?.cancel();
    _watchdogTimer = null;

    _clickResetTimer?.cancel();
    _clickResetTimer = null;

    super.dispose();
  }

  ///4，启动调试定时器 - 每秒输出轮播的实时状态
  void _startDebugTimer() {
    _debugTimer?.cancel();

    // 启动通告轮播调试定时器（只启动一次）
    final announcementCarouselProvider =
        context.read<AnnouncementCarouselProvider>();
    final carouselStateProvider = context.read<CarouselStateProvider>();
    final apiNoticeStayDuration = carouselStateProvider.noticeStayDuration;
    announcementCarouselProvider.startDebugTimer(apiNoticeStayDuration);

    _debugTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      final currentAppState = carouselStateProvider.currentAppState;

      // 只在应用状态变化时输出日志
      if (_lastLoggedAppState != currentAppState) {
        // _logger.i(
        //     '🕐 [调试] 应用状态变化: ${_lastLoggedAppState?.name ?? "初始"} -> ${currentAppState.name}');
        _lastLoggedAppState = currentAppState;
      }
    });
  }

  ///5， 进入全屏广告状态，暂停所有轮播
  void _pauseAllCarousels() {
    final fullAdCarouselProvider =
        Provider.of<FullscreenAdProvider>(context, listen: false);
    final topAdCarouselProvider =
        Provider.of<TopAdCarouselProvider>(context, listen: false);
    final announcementCarouselProvider =
        Provider.of<AnnouncementCarouselProvider>(context, listen: false);
    final stateProvider =
        Provider.of<CarouselStateProvider>(context, listen: false);

    // 暂停顶部广告轮播
    topAdCarouselProvider.pauseTopCarousel();

    // 暂停通告轮播
    announcementCarouselProvider.pauseMidCarousel();

    // 启动全屏广告轮播
    fullAdCarouselProvider.enterFullscreenMode();

    // 设置日志输出标志 - 全屏广告模式下只显示全屏广告的日志
    fullAdCarouselProvider.startDebugTimer();
    announcementCarouselProvider.startDebugTimer(
        stateProvider.noticeStayDuration,
        enableLogging: false);
  }

  ///5.1，进入设置页面前暂停所有轮播和计时器
  void _pauseAllCarouselsForSettings() {
    // _logger.i('⚙️ 进入设置页面 - 暂停所有轮播和计时器');

    final topAdProvider = context.read<TopAdCarouselProvider>();
    final announcementCarouselProvider =
        context.read<AnnouncementCarouselProvider>();
    final fullAdCarouselProvider = context.read<FullscreenAdProvider>();
    final bottomProvider = context.read<WeatherProvider>();

    // 暂停顶部广告计时器
    topAdProvider.pauseAllTimersForSettings();

    // 暂停通告轮播计时器
    announcementCarouselProvider.pauseAllTimersForSettings();

    // 暂停底部天气二维码轮播计时器
    bottomProvider.pauseAllTimersForSettings();

    // 暂停全屏广告轮播（如果活跃状态）
    if (fullAdCarouselProvider.isActive) {
      fullAdCarouselProvider.pauseCarousel();
      fullAdCarouselProvider.stopDebugTimer();
    }

    // 暂停其他定时器
    _bottomTimer?.cancel();
    _debugTimer?.cancel();
    _watchdogTimer?.cancel();

    // 暂停其他轮播中的媒体内容
    _bottomCarouselController.pauseAllMedia();

    // 设置其他轮播为暂停状态
    _isBottomCarouselPaused = true;

    // 暂停全屏广告计时器（通过设置状态为手动操作模式）
    final carouselStateProvider = context.read<CarouselStateProvider>();
    carouselStateProvider.enterManualOperation();

    // _logger.i('⚙️ 设置页面模式 - 所有轮播已暂停');
  }

  ///6，正常退出全屏广告状态，恢复所有轮播
  void _resumeAllCarousels() {
    final fullAdCarouselProvider =
        Provider.of<FullscreenAdProvider>(context, listen: false);
    final topAdCarouselProvider =
        Provider.of<TopAdCarouselProvider>(context, listen: false);
    final announcementCarouselProvider =
        Provider.of<AnnouncementCarouselProvider>(context, listen: false);
    final stateProvider =
        Provider.of<CarouselStateProvider>(context, listen: false);

    // 退出全屏广告模式
    fullAdCarouselProvider.exitFullscreenMode();

    // 恢复顶部广告轮播
    topAdCarouselProvider.resumeTopCarousel();

    // 恢复通告轮播
    announcementCarouselProvider.resumeMidCarousel(
        stateProvider.noticeStayDuration,
        forceJumpToIndex: true);

    // 设置日志输出标志 - 默认状态下只显示顶部广告和通告轮播的日志
    fullAdCarouselProvider.startDebugTimer();
    announcementCarouselProvider
        .startDebugTimer(stateProvider.noticeStayDuration, enableLogging: true);
  }

  ///6.1，启动持续通告轮播（独立方法以确保一致性）- 真正的无限循环
  ///6，启动轮播监控定时器（检测并自动恢复中断的轮播）
  void _startCarouselWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final carouselStateProvider = context.read<CarouselStateProvider>();
      final currentAppState = carouselStateProvider.currentAppState;
      final announcementCarouselProvider =
          context.read<AnnouncementCarouselProvider>();

      // 只在默认状态下检查通告轮播
      if (currentAppState == AppState.defaultState &&
          !announcementCarouselProvider.isMidCarouselPaused) {
        final apiNoticeStayDuration = carouselStateProvider.noticeStayDuration;
        announcementCarouselProvider
            .checkAndRestoreMidCarousel(apiNoticeStayDuration);
      }
    });
    // _logger.i('🔍 [启动] 轮播监控定时器 (30s间隔检查) - 确保轮播不中断');
  }

  ///6，进入手动操作模式
  void _handleManualOperationMode() {
    // _logger.i('🖱️ 进入手动操作模式 - 暂停通告轮播，恢复顶部和底部轮播');

    final announcementCarouselProvider =
        context.read<AnnouncementCarouselProvider>();

    // 暂停中部通告轮播
    announcementCarouselProvider.pauseMidCarousel();

    // 恢复顶部广告轮播（如果被暂停了）
    final topAdProvider = context.read<TopAdCarouselProvider>();
    // 确保顶部广告能够立即恢复视频播放和轮播
    if (topAdProvider.isTopCarouselPaused) {
      topAdProvider.resumeTopCarousel();
    } else {
      topAdProvider.checkAndRestoreTopCarousel();
    }

    // 恢复底部轮播（如果被暂停了）
    if (_bottomCarouselController.widgetCount > 1 && !_isBottomCarouselPaused) {
      _bottomTimer?.cancel();

      // 从设置中获取底部轮播时间，默认为10秒
      final appDataProvider = context.read<AppDataProvider>();
      final deviceSettings = appDataProvider.deviceSettings;
      final bottomCarouselDuration =
          deviceSettings?.bottomCarouselDuration ?? 10;

      _bottomTimer =
          Timer.periodic(Duration(seconds: bottomCarouselDuration), (timer) {
        if (mounted &&
            _bottomCarouselController.widgetCount > 1 &&
            !_isBottomCarouselPaused) {
          _bottomCarouselController.playNext();
        }
      });
    }
  }

  ///7，自动隐藏欠费页面当进入全屏广告状态
  void _autoHideArrearPagesOnFullscreenAd() {
    final announcementCarouselProvider =
        context.read<AnnouncementCarouselProvider>();

    // 检查是否有欠费查询页面正在显示（已删除，功能整合到MainScreenWidget）
    // if (announcementCarouselProvider.isShowingArrearQuery) {
    //   // _logger.i('📺 [全屏广告] 检测到欠费查询页面正在显示，自动隐藏');
    //   announcementCarouselProvider.hideArrearQueryWidget(() {}, 10, 10);
    // }

    // 检查是否有欠费总览页面正在显示
    if (announcementCarouselProvider.isShowingArrearTable) {
      // _logger.i('📺 [全屏广告] 检测到欠费总览页面正在显示，自动隐藏');
      announcementCarouselProvider.hideArrearTableWidget(() {}, 10, 10);
    }
  }

  ///8，初始化中部轮播
  void _initializeMidWidgets() {
    final announcementProvider =
        Provider.of<AnnouncementProvider>(context, listen: false);
    final carouselStateProvider = context.read<CarouselStateProvider>();
    final announcementCarouselProvider =
        context.read<AnnouncementCarouselProvider>();

    // 使用轮播专用通告数组 - 只包含緊急和一般通告
    List<AnnouncementModel> carouselAnnouncements =
        announcementProvider.getCarouselAnnouncements();

    // 获取API配置的通告停留时间
    final apiNoticeStayDuration = carouselStateProvider.noticeStayDuration;
    final delayBeforeNotice = carouselStateProvider.normalToAnnouncementCarouselDuration;

    // 初始化通告轮播
    announcementCarouselProvider.initializeMidWidgets(
      carouselAnnouncements: carouselAnnouncements,
      apiNoticeStayDuration: apiNoticeStayDuration,
      delayBeforeNotice: delayBeforeNotice,
      onAnnouncementTap: (AnnouncementModel? announcement) {
        if (announcement == null) {
          // 显示欠费查询界面 - 立即进入手动操作状态
          // _logger.i('🔵 [MainScreenPage] 接收到欠费查询请求，从主页面跳转到欠费查询界面');
          // _logger.i(
          //     '🔵 [MainScreenPage] 当前应用状态: ${carouselStateProvider.currentAppState}');
          // 触发手动操作状态
          // _logger.i('🔵 [MainScreenPage] 准备进入手动操作状态');
          carouselStateProvider.enterManualOperation();
          // _logger.i(
          //     '🔵 [MainScreenPage] 已进入手动操作状态: ${carouselStateProvider.currentAppState}');
          // 欠费查询功能已整合到MainScreenWidget中，不再需要单独的覆盖层
          // _logger.i('🔵 [MainScreenPage] 欠费查询功能已整合到MainScreenWidget');
        } else {
          // _logger.i(
          //     '📰 [MainScreenPage] 接收到通告点击请求: ${announcement.title} (ID: ${announcement.id})');

          // 新逻辑：直接显示点击的通告，不依赖轮播列表查找
          // _logger.i(
          //     '📰 [MainScreenPage] 直接显示点击的通告，根据文件MD5: ${announcement.file.md5}');

          // 直接显示独立通告
          announcementCarouselProvider.showIndependentAnnouncement(announcement,
              () {
            // 返回主页时跳转到主屏幕
            announcementCarouselProvider.jumpToAnnouncementIndex(0);
          });

          // 触发手动操作状态
          // _logger.i('📰 [MainScreenPage] 准备进入手动操作状态');
          carouselStateProvider.enterManualOperation();
          // _logger.i(
          //     '📰 [MainScreenPage] 已进入手动操作状态: ${carouselStateProvider.currentAppState}');
        }
      },
      onHomeButtonPressed: () {
        // 主頁按鈕被按下時，跳轉到第一個項目（主屏幕）
        announcementCarouselProvider.jumpToAnnouncementIndex(0);
      },
    );
  }

  ///9，初始化顶部轮播
  void _initializeTopWidgets() {
    final advertisementProvider =
        Provider.of<AdvertisementProvider>(context, listen: false);
    final topAdProvider = context.read<TopAdCarouselProvider>();
    
    // 優先使用輪播專用的緩存數據
    List<AdModel> topAds = advertisementProvider.topCarouselAdvertisements;
    
    // 如果輪播數據為空，則使用舊的廣告數據作為後備
    if (topAds.isEmpty) {
      topAds = advertisementProvider.topAdvertisements;
      _logger.w('⚠️ 輪播專用數據為空，使用舊廣告數據作為後備: ${topAds.length} 個廣告');
    } else {
      _logger.i('✅ 使用輪播專用數據: ${topAds.length} 個廣告');
    }

    if (topAds.isNotEmpty) {
      topAdProvider.initializeTopWidgets(topAds);
      _logger.i('✅ 頂部廣告輪播初始化完成: ${topAds.length} 個廣告');
    } else {
      _logger.w('⚠️ 沒有可用的頂部廣告數據');
    }

    // 啟動頂部廣告調試定時器
    topAdProvider.startDebugTimer();
  }

  ///10，初始化底部轮播
  void _initializeBottomWidgets() {
    // 底部轮播现在由BottomWeatherQrcodeNewsCarouselProvider管理
    final bottomProvider = context.read<WeatherProvider>();
    bottomProvider.initializeBottomCarousel();
    // _logger.i('🌤️ [初始化] 底部天气二维码轮播初始化完成');
  }

  ///11，处理设备ID点击事件
  void _handleDeviceIdClick() {
    _deviceIdClickCount++;
    // _logger.i('📱 设备ID点击次数: $_deviceIdClickCount/8');

    // 取消之前的重置定时器
    _clickResetTimer?.cancel();

    if (_deviceIdClickCount >= 8) {
      // 达到8次点击，进入设置页面
      // _logger.i('🔧 连续点击8次，进入设置页面');
      _deviceIdClickCount = 0; // 重置计数

      // 进入设置页面前暂停所有轮播和计时器
      _pauseAllCarouselsForSettings();

      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SettingsPage()),
      );
    } else {
      // 设置5秒后重置计数器
      _clickResetTimer = Timer(const Duration(seconds: 5), () {
        _deviceIdClickCount = 0;
        // _logger.i('⏰ 点击计数器已重置');
      });
    }
  }

  @override

  ///12，处理视频播放器的初始化和播放
  Widget build(BuildContext context) {
    // Listen to AnnouncementProvider for changes
    final announcementProvider = context.watch<AnnouncementProvider>();
    final currentCarouselAnnouncements =
        announcementProvider.carouselAnnouncements; // 监听轮播专用通告数组

    // Listen to AdvertisementProvider for changes
    final advertisementProvider = context.watch<AdvertisementProvider>();
    final currentAdvertisements = advertisementProvider.topAdvertisements;

    // Listen to AppDataProvider for device ID
    final appDataProvider = context.watch<AppDataProvider>();
    final deviceId = appDataProvider.deviceId;

    // Listen to CarouselStateProvider for fullscreen ad state changes
    final carouselStateProvider = context.watch<CarouselStateProvider>();
    final currentAppState = carouselStateProvider.currentAppState;

    // Handle state changes for carousel and media control
    if (_previousAppState != currentAppState) {
      // _logger.i(
      //     '🔄 应用状态变化: ${_previousAppState?.name ?? "初始"} -> ${currentAppState.name}');

      // 更新轮播状态基于当前应用状态
      _updateCarouselStateBasedOnAppState(currentAppState);

      // 使用 addPostFrameCallback 延迟执行轮播控制操作
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        if (currentAppState == AppState.fullscreenAd) {
          // _logger.i('📺 进入全屏广告状态');
          _pauseAllCarousels();
          _autoHideArrearPagesOnFullscreenAd(); // 自动隐藏欠费页面
        } else if (currentAppState == AppState.manualOperation) {
          // _logger.i('🖱️ 进入手动操作状态');
          _handleManualOperationMode();
        } else if (currentAppState == AppState.defaultState) {
          // _logger.i('🏠 进入默认状态');
          // 確保通告輪播在默認狀態下恢復
          _resumeAllCarousels();
        }
      });

      _previousAppState = currentAppState;
    }

    // If carousel announcements have changed, re-initialize the mid widgets
    // 现在监听轮播通告数组的变化而不是所有通告的变化
    if (_previousAnnouncementsForBuild == null ||
        !listEquals(
            _previousAnnouncementsForBuild, currentCarouselAnnouncements)) {
      if (mounted) {
        // Ensure widget is still in the tree

        // 检查新的通告数据是否有效
        if (currentCarouselAnnouncements.isNotEmpty ||
            _previousAnnouncementsForBuild == null) {
          // 只有当新数据非空或首次初始化时才更新
          try {
            _initializeMidWidgets();
            _previousAnnouncementsForBuild =
                List.from(currentCarouselAnnouncements); // 更新存储的轮播通告列表
            // _logger.i('通告轮播更新成功: ${currentCarouselAnnouncements.length} 个通告');
          } catch (e) {
            _logger.e('初始化中部轮播失败，保持现有状态', error: e);
            // 不更新 _previousAnnouncementsForBuild，保持现有状态
          }
        } else {
          // 新数据为空但有旧数据，记录警告但不更新（保持现有轮播继续工作）
          _logger.w('收到空的通告数据，保持现有轮播继续工作。'
              '当前轮播: ${_previousAnnouncementsForBuild?.length ?? 0} 个通告');

          // 检查是否有网络错误信息
          if (announcementProvider.error != null) {
            _logger.w('通告获取错误: ${announcementProvider.error}');
          }
        }
      }
    }

    // If advertisements have changed, re-initialize the top widgets
    if (_previousAdvertisementsForBuild == null ||
        !listEquals(_previousAdvertisementsForBuild, currentAdvertisements)) {
      if (mounted) {
        // 检查新的广告数据是否有效
        if (currentAdvertisements.isNotEmpty ||
            _previousAdvertisementsForBuild == null) {
          // 只有当新数据非空或首次初始化时才更新
          try {
            _initializeTopWidgets();

            // 同时更新全屏广告数据 - 延迟到构建完成后执行避免setState错误
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                final fullAdCarouselProvider =
                    context.read<FullscreenAdProvider>();
                final fullAds = advertisementProvider.fullAdvertisements;
                fullAdCarouselProvider.updateFullscreenAds(fullAds);
                // _logger.i('全屏广告数据已更新: ${fullAds.length} 个全屏广告');
              }
            });

            _previousAdvertisementsForBuild =
                List.from(currentAdvertisements); // Update the stored list
            // _logger.i('广告轮播更新成功: ${currentAdvertisements.length} 个广告');
          } catch (e) {
            _logger.e('初始化顶部轮播失败，保持现有状态', error: e);
            // 不更新 _previousAdvertisementsForBuild，保持现有状态
          }
        } else {
          // 新数据为空但有旧数据，记录警告但不更新
          _logger.w('收到空的广告数据，保持现有轮播继续工作。'
              '当前轮播: ${_previousAdvertisementsForBuild?.length ?? 0} 个广告');

          // 检查是否有网络错误信息
          if (advertisementProvider.error != null) {
            _logger.w('广告获取错误: ${advertisementProvider.error}');
          }
        }
      }
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 上部區域 - 6/24 比例
            Expanded(
              flex: 6,
              child: SizedBox(
                  width: double.infinity,
                  child: Consumer<TopAdCarouselProvider>(
                      builder: (context, topAdProvider, child) {
                    return custom_carousel.CarouselWidget(
                      controller: topAdProvider.topCarouselController,
                      // autoPlayDuration is effectively managed by _startTopAdTimer
                      showIndicators: false,
                      allowManualSwipe: false,
                      onPageChanged: (index) {
                        if (topAdProvider.topAds.length > 1) {
                          topAdProvider.onPageChanged(index);
                        }
                        // setState(() {
                        //   _topCurrentIndex = index;
                        // });
                      },
                    );
                  })),
            ),
            // 中部區域 - 14/24 比例
            Expanded(
              flex: 14,
              child: Container(
                width: double.infinity,
                color: Colors.grey.shade50, // Background for the carousel area
                child: Stack(
                  children: [
                    // 轮播内容 - 始终存在，不被销毁
                    Consumer<AnnouncementCarouselProvider>(
                      builder: (context, announcementCarouselProvider, child) {
                        // _logger.i('🎬 [MainScreenPage] 轮播组件构建中');
                        return custom_carousel.CarouselWidget(
                          controller: announcementCarouselProvider
                              .midCarouselController,
                          showIndicators: false,
                          allowManualSwipe: false,
                          onPageChanged: (index) {},
                        );
                      },
                    ),
                    // 欠费查询覆盖层 - 已删除，功能整合到MainScreenWidget
                    // Consumer<AnnouncementCarouselProvider>(
                    //   builder: (context, announcementCarouselProvider, child) {
                    //     '🔄 [MainScreenPage Overlay] 检查覆盖层 - isShowingArrearQuery: ${announcementCarouselProvider.isShowingArrearQuery}');

                    //     if (announcementCarouselProvider.isShowingArrearQuery) {
                    //       '💰 [MainScreenPage Overlay] 显示欠费查询覆盖层');
                    //       return Container(
                    //         width: double.infinity,
                    //         height: double.infinity,
                    //         // ArrearDisplayWidget已删除，功能整合到MainScreenWidget的右側展示
                    //         child: const SizedBox.shrink(),
                    //       );
                    //     }

                    //     // 不显示欠费查询时返回空容器
                    //     return const SizedBox.shrink();
                    //   },
                    // ),

                    // 欠费总览覆盖层 - 按需显示
                    Consumer<AnnouncementCarouselProvider>(
                      builder: (context, announcementCarouselProvider, child) {
                        // _logger.i(
                        //     '🔄 [MainScreenPage Overlay] 检查欠费总览覆盖层 - isShowingArrearTable: ${announcementCarouselProvider.isShowingArrearTable}');

                        if (announcementCarouselProvider.isShowingArrearTable) {
                          // _logger.i('📊 [MainScreenPage Overlay] 显示欠费总览覆盖层');
                          return SizedBox(
                            width: double.infinity,
                            height: double.infinity,
                            child: ArrearTableWidget(
                              key: _arrearTableKey,
                              onHomeButtonPressed: () {
                                _logger.i(
                                    '🏠 [MainScreenPage Overlay] 欠费总览返回按钮被点击，隐藏覆盖层');
                                announcementCarouselProvider
                                    .hideArrearTableWidget(
                                  () {},
                                  carouselStateProvider.noticeStayDuration,
                                  carouselStateProvider.normalToAnnouncementCarouselDuration,
                                );
                                // _logger.i(
                                //     '🏠 [MainScreenPage Overlay] 欠费总览覆盖层已隐藏');
                              },
                            ),
                          );
                        }

                        // 不显示欠费总览时返回空容器
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
              ),
            ),
            // 底部區域 - 4/24 比例 (天气和二维码轮播区域)
            Expanded(
              flex: 4,
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    // 新闻跑马灯 - 1/8 比例
                    Container(
                      height: 40,
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return RthkNewsTickerWidget(
                            height: 40,
                            width: constraints.maxWidth,
                          );
                        },
                      ),
                    ),
                    // 底部轮播 - 7/8 比例
                    const Expanded(
                      child: BottomDisplayWidget(),
                    ),
                  ],
                ),
              ),
            ),
            // 设备ID显示区域 - 1/24 比例
            Container(
              width: double.infinity,
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: GestureDetector(
                  onTap: _handleDeviceIdClick,
                  child: Text(
                    deviceId != null ? '設備ID: $deviceId' : '設備ID: 未知',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
