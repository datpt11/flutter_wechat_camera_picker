///
/// [Author] Alex (https://github.com/AlexV525)
/// [Date] 2020/7/13 11:08
///
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wechat_camera_picker/wechat_camera_picker.dart';

import '../constants/constants.dart';
import '../widget/circular_progress_bar.dart';

import 'builder/slide_page_transition_builder.dart';

/// Create a camera picker integrate with [CameraDescription].
/// 通过 [CameraDescription] 整合的拍照选择
///
/// The picker provides create an [AssetEntity] through the camera.
/// However, this might failed (high probability) if there're any steps
/// went wrong during the process.
/// 该选择器可以通过拍照创建 [AssetEntity] ，但由于过程中有的步骤随时会出现问题，
/// 使用时有较高的概率会遇到失败。
class CameraPicker extends StatefulWidget {
  const CameraPicker({
    Key key,
    this.shouldKeptInLocal = false,
    this.isAllowRecording = false,
    this.theme,
  }) : super(key: key);

  /// Whether the taken file should be kept in local.
  /// 拍照的文件是否应该保存在本地
  final bool shouldKeptInLocal;

  /// Whether the picker can record video.
  /// 选择器是否可以录像
  final bool isAllowRecording;

  final ThemeData theme;

  /// Static method to create [AssetEntity] through camera.
  /// 通过相机创建 [AssetEntity] 的静态方法
  static Future<AssetEntity> pickFromCamera(
    BuildContext context, {
    bool shouldKeptInLocal = true,
  }) async {
    final AssetEntity result = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<AssetEntity>(
      SlidePageTransitionBuilder<AssetEntity>(
        builder: CameraPicker(
          shouldKeptInLocal: shouldKeptInLocal,
        ),
        transitionCurve: Curves.easeIn,
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
    return result;
  }

  /// Build a dark theme according to the theme color.
  /// 通过主题色构建一个默认的暗黑主题
  static ThemeData themeData(Color themeColor) => ThemeData.dark().copyWith(
        buttonColor: themeColor,
        brightness: Brightness.dark,
        primaryColor: Colors.grey[900],
        primaryColorBrightness: Brightness.dark,
        primaryColorLight: Colors.grey[900],
        primaryColorDark: Colors.grey[900],
        accentColor: themeColor,
        accentColorBrightness: Brightness.dark,
        canvasColor: Colors.grey[850],
        scaffoldBackgroundColor: Colors.grey[900],
        bottomAppBarColor: Colors.grey[900],
        cardColor: Colors.grey[900],
        highlightColor: Colors.transparent,
        toggleableActiveColor: themeColor,
        cursorColor: themeColor,
        textSelectionColor: themeColor.withAlpha(100),
        textSelectionHandleColor: themeColor,
        indicatorColor: themeColor,
        appBarTheme: const AppBarTheme(
          brightness: Brightness.dark,
          elevation: 0,
        ),
        colorScheme: ColorScheme(
          primary: Colors.grey[900],
          primaryVariant: Colors.grey[900],
          secondary: themeColor,
          secondaryVariant: themeColor,
          background: Colors.grey[900],
          surface: Colors.grey[900],
          brightness: Brightness.dark,
          error: const Color(0xffcf6679),
          onPrimary: Colors.black,
          onSecondary: Colors.black,
          onSurface: Colors.white,
          onBackground: Colors.white,
          onError: Colors.black,
        ),
      );

  @override
  _CameraPickerState createState() => _CameraPickerState();
}

class _CameraPickerState extends State<CameraPicker> {
  /// The [Duration] for record detection. (200ms)
  /// 检测是否开始录制的时长 (200毫秒)
  final Duration recordDetectDuration = kThemeChangeDuration;

  /// Available cameras.
  /// 可用的相机实例
  List<CameraDescription> cameras;

  /// The controller for the current camera.
  /// 当前相机实例的控制器
  CameraController controller;

  /// The index of the current cameras. Defaults to `0`.
  /// 当前相机的索引。默认为0
  int currentCameraIndex = 0;

  /// The path which the temporary file will be stored.
  /// 临时文件会存放的目录
  String cacheFilePath;

  /// The path of the taken file.
  /// 拍照文件的路径。
  String takenFilePath;

  /// Whether the [shootingButton] should animate according to the gesture.
  /// 拍照按钮是否需要执行动画
  ///
  /// This happens when the [shootingButton] is being long pressed. It will animate
  /// for video recording state.
  /// 当长按拍照按钮时，会进入准备录制视频的状态，此时需要执行动画。
  bool isShootingButtonAnimate = false;

  /// Whether the recording progress started.
  /// 是否已开始录制视频
  ///
  /// After [shootingButton] animated, the [CircleProgressBar] will become visible.
  /// 当拍照按钮动画执行结束后，进度将变为可见状态并开始更新其状态。
  bool isRecording = false;

  /// The [Timer] for record start detection.
  /// 用于检测是否开始录制的定时器
  ///
  /// When the [shootingButton] started animate, this [Timer] will start at the same
  /// time. When the time is more than [recordDetectDuration], which means we should
  /// start recoding, the timer finished.
  Timer recordDetectTimer;

  /// Whether the current [CameraDescription] initialized.
  /// 当前的相机实例是否已完成初始化
  bool get isInitialized => controller?.value?.isInitialized ?? false;

  /// Whether the taken file should be kept in local. (A non-null wrapper)
  /// 拍照的文件是否应该保存在本地（非空包装）
  bool get shouldKeptInLocal => widget.shouldKeptInLocal ?? false;

  /// A getter to the current [CameraDescription].
  /// 获取当前相机实例
  CameraDescription get currentCamera => cameras?.elementAt(currentCameraIndex);

  ThemeData _theme;

  /// Get [ThemeData] of the [AssetPicker] through [Constants.pickerKey].
  /// 通过常量全局 Key 获取当前选择器的主题
  ThemeData get theme => _theme;

  @override
  void initState() {
    super.initState();
    _theme = widget.theme ?? CameraPicker.themeData(C.themeColor);

    // TODO(Alex): Currently hide status bar will cause the viewport shaking on Android.
    /// Hide system status bar automatically on iOS.
    /// 在iOS设备上自动隐藏状态栏
    if (Platform.isIOS) {
      SystemChrome.setEnabledSystemUIOverlays(<SystemUiOverlay>[]);
    }
    initStorePath();
    initCameras();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIOverlays(SystemUiOverlay.values);
    controller?.dispose();
    super.dispose();
  }

  /// Defined the path according to [shouldKeptInLocal], with platforms specification.
  /// 根据 [shouldKeptInLocal] 及平台规定确定存储路径。
  ///
  /// * When [Platform.isIOS], use [getApplicationDocumentsDirectory].
  /// * When platform is others: [shouldKeptInLocal] ?
  ///   * [true] : [getExternalStorageDirectory]'s path
  ///   * [false]: [getExternalCacheDirectories]'s last path
  Future<void> initStorePath() async {
    if (Platform.isIOS) {
      cacheFilePath = (await getApplicationDocumentsDirectory()).path;
    } else {
      if (shouldKeptInLocal) {
        cacheFilePath = (await getExternalStorageDirectory()).path;
      } else {
        cacheFilePath = (await getExternalCacheDirectories()).last.path;
      }
    }
    if (cacheFilePath != null) {
      cacheFilePath += '/picker';
    }
  }

  /// Initialize cameras instances.
  /// 初始化相机实例
  Future<void> initCameras({CameraDescription cameraDescription}) async {
    controller?.dispose();

    /// When it's null, which means this is the first time initializing the cameras.
    /// So cameras should fetch.
    if (cameraDescription == null) {
      cameras = await availableCameras();
    }

    /// After cameras fetched, judge again with the list is empty or not to ensure
    /// there is at least an available camera for use.
    if (cameraDescription == null && (cameras?.isEmpty ?? true)) {
      realDebugPrint('No cameras found.');
      return;
    }

    /// Initialize the controller with the max resolution preset.
    /// - No one want the lower resolutions. :)
    controller = CameraController(
      cameraDescription ?? cameras[0],
      ResolutionPreset.max,
    );
    controller.initialize().then((dynamic _) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  /// The method to switch cameras.
  /// 切换相机的方法
  ///
  /// Switch cameras in order. When the [currentCameraIndex] reached the length
  /// of cameras, start from the beginning.
  /// 按顺序切换相机。当达到相机数量时从头开始。
  void switchCameras() {
    ++currentCameraIndex;
    if (currentCameraIndex == cameras.length) {
      currentCameraIndex = 0;
    }
    initCameras(cameraDescription: currentCamera);
  }

  /// The method to take a picture.
  /// 拍照方法
  ///
  /// The picture will only taken when [isInitialized], and the camera is not
  /// taking pictures.
  /// 仅当初始化成功且相机未在拍照时拍照。
  Future<void> takePicture() async {
    if (isInitialized && !controller.value.isTakingPicture) {
      try {
        final String path = '${cacheFilePath}_$currentTimeStamp.jpg';
        await controller.takePicture(path);
        takenFilePath = path;
        if (mounted) {
          setState(() {});
        }
      } catch (e) {
        realDebugPrint('Error when taking pictures: $e');
      }
    }
  }

  /// Make sure the [takenFilePath] is `null` before pop.
  /// Otherwise, make it `null` .
  Future<bool> clearTakenFileBeforePop() async {
    if (takenFilePath != null) {
      setState(() {
        takenFilePath = null;
      });
      return false;
    }
    return true;
  }

  /// When users confirm to use the taken file, create the [AssetEntity] using
  /// [Editor.saveImage] (PhotoManager.editor.saveImage), then delete the file
  /// if not [shouldKeptInLocal]. While the entity might returned null, there's
  /// no side effects if popping `null` because the parent picker will ignore it.
  Future<void> createAssetEntityAndPop() async {
    try {
      final File file = File(takenFilePath);
      final Uint8List data = await file.readAsBytes();
      final AssetEntity entity = await PhotoManager.editor.saveImage(
        data,
        title: takenFilePath,
      );
      if (!shouldKeptInLocal) {
        file.delete();
      }
      Navigator.of(context).pop(entity);
    } catch (e) {
      realDebugPrint('Error when creating entity: $e');
    }
  }

  /// Settings action section widget.
  /// 设置操作区
  ///
  /// This displayed at the top of the screen.
  /// 该区域显示在屏幕上方。
  Widget get settingsAction {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Row(
        children: const <Widget>[
          Spacer(),
          // TODO(Alex): There's an issue tracking NPE of the camera plugin, so switching is temporary disabled .
//          if ((cameras?.length ?? 0) > 1) switchCamerasButton,
        ],
      ),
    );
  }

  /// The button to switch between cameras.
  /// 切换相机的按钮
  Widget get switchCamerasButton {
    return InkWell(
      onTap: switchCameras,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(
          Icons.switch_camera,
          color: Colors.white,
          size: 30.0,
        ),
      ),
    );
  }

  /// Shooting action section widget.
  /// 拍照操作区
  ///
  /// This displayed at the top of the screen.
  /// 该区域显示在屏幕下方。
  Widget get shootingActions {
    return SizedBox(
      height: Screens.width / 3.5,
      child: Row(
        children: <Widget>[
          Expanded(
            child: !isRecording ? Center(child: backButton) : const SizedBox.shrink(),
          ),
          Expanded(child: Center(child: shootingButton)),
          const Spacer(),
        ],
      ),
    );
  }

  /// The back button near to the [shootingButton].
  /// 靠近拍照键的返回键
  Widget get backButton {
    return InkWell(
      borderRadius: maxBorderRadius,
      onTap: Navigator.of(context).pop,
      child: Container(
        margin: const EdgeInsets.all(10.0),
        width: Screens.width / 15,
        height: Screens.width / 15,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            Icons.keyboard_arrow_down,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  /// The shooting button.
  /// 拍照按钮
  // TODO(Alex): Need further integration with video recording.
  Widget get shootingButton {
    final Size outerSize = Size.square(Screens.width / 3.5);
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerUp: (PointerUpEvent event) {
        recordDetectTimer?.cancel();
        if (isRecording) {
          isRecording = false;
          if (mounted) {
            setState(() {});
          }
        }
        if (isShootingButtonAnimate) {
          isShootingButtonAnimate = false;
          if (mounted) {
            setState(() {});
          }
        }
      },
      child: InkWell(
        borderRadius: maxBorderRadius,
        onTap: () {},
        onLongPress: () {
          recordDetectTimer = Timer(recordDetectDuration, () {
            isRecording = true;
            if (mounted) {
              setState(() {});
            }
          });
          setState(() {
            isShootingButtonAnimate = true;
          });
        },
        child: SizedBox.fromSize(
          size: outerSize,
          child: Stack(
            children: <Widget>[
              Center(
                child: AnimatedContainer(
                  duration: kThemeChangeDuration,
                  width: isShootingButtonAnimate
                      ? outerSize.width
                      : (Screens.width / 5),
                  height: isShootingButtonAnimate
                      ? outerSize.height
                      : (Screens.width / 5),
                  padding: EdgeInsets.all(
                      Screens.width / (isShootingButtonAnimate ? 10 : 35)),
                  decoration: BoxDecoration(
                    color: Colors.white30,
                    shape: BoxShape.circle,
                  ),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              if (isRecording)
                CircleProgressBar(
                  duration: 15.seconds,
                  outerRadius: outerSize.width,
                  ringsWidth: 2.0,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The preview section for the taken file.
  /// 拍摄文件的预览区
  Widget get takenFilePreviewWidget {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: <Widget>[
          Positioned.fill(child: Image.file(File(takenFilePath))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 20.0,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      previewBackButton,
                      const Spacer(),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      const Spacer(),
                      previewConfirmButton,
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The back button for the preview section.
  /// 预览区的返回按钮
  Widget get previewBackButton {
    return InkWell(
      borderRadius: maxBorderRadius,
      onTap: () {
        File(takenFilePath).delete();
        setState(() {
          takenFilePath = null;
        });
      },
      child: Container(
        margin: const EdgeInsets.all(10.0),
        width: Screens.width / 15,
        height: Screens.width / 15,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            Icons.close,
            color: Colors.black,
            size: 18.0,
          ),
        ),
      ),
    );
  }

  /// The confirm button for the preview section.
  /// 预览区的确认按钮
  Widget get previewConfirmButton {
    return MaterialButton(
      minWidth: 20.0,
      height: 32.0,
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      color: theme.colorScheme.secondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3.0),
      ),
      child: Text(
        '完成',
        style: TextStyle(
          color: theme.textTheme.bodyText1.color,
          fontSize: 17.0,
          fontWeight: FontWeight.normal,
        ),
      ),
      onPressed: createAssetEntityAndPop,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: clearTakenFileBeforePop,
      child: Theme(
        data: theme,
        child: Material(
          color: Colors.black,
          child: Stack(
            children: <Widget>[
              if (isInitialized)
                Center(
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: CameraPreview(controller),
                  ),
                )
              else
                const SizedBox.shrink(),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      settingsAction,
                      shootingActions,
                    ],
                  ),
                ),
              ),
              if (takenFilePath != null) takenFilePreviewWidget,
            ],
          ),
        ),
      ),
    );
  }
}