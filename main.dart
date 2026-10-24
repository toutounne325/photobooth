/*
 * Protection légale pour le trading, propriété exclusive de Pirate Pips ™.
 * AVERTISSEMENT LÉGAL (DISCLAIMER) : Le trading sur les marchés financiers comporte un risque élevé de perte en capital.
 * Les performances passées ne garantissent pas les résultats futurs. Ce code est la propriété intellectuelle exclusive
 * de Pirate Pips ™ et ne constitue en aucun cas un conseil en investissement.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// POINT D'ENTRÉE & VERROUILLAGE KIOSQUE PORTRAIT
// ============================================================================

List<CameraDescription> globalAvailableCameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  try {
    globalAvailableCameras = await availableCameras();
  } catch (e) {
    debugPrint('Erreur lors de la détection des caméras : $e');
  }

  runApp(const HalloweenPhotoboothApp());
}

// ============================================================================
// THÈME VISUEL HALLOWEEN
// ============================================================================

class HalloweenColors {
  static const Color backgroundBlack = Color(0xFF0B0A0E);
  static const Color surfaceAnthracite = Color(0xFF17141F);
  static const Color pumpkinOrange = Color(0xFFFF7518);
  static const Color pumpkinGlow = Color(0xFFFF9A44);
  static const Color darkPurple = Color(0xFF2B113F);
  static const Color mysticViolet = Color(0xFF5A228B);
  static const Color textLight = Color(0xFFF6F2FA);
}

class HalloweenPhotoboothApp extends StatelessWidget {
  const HalloweenPhotoboothApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Halloween Photobooth Kiosk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: HalloweenColors.backgroundBlack,
        primaryColor: HalloweenColors.pumpkinOrange,
        colorScheme: const ColorScheme.dark(
          primary: HalloweenColors.pumpkinOrange,
          secondary: HalloweenColors.mysticViolet,
          surface: HalloweenColors.surfaceAnthracite,
        ),
        useMaterial3: true,
      ),
      home: const PhotoboothKioskScreen(),
    );
  }
}

// ============================================================================
// MODÈLES DE DONNÉES
// ============================================================================

class BoothConfig {
  final String webhookUrl;
  final int countdownSeconds;
  final bool useFrontCamera;
  final bool isMirrored;
  final String adminPin;
  final int resultDurationSeconds;

  const BoothConfig({
    this.webhookUrl = '',
    this.countdownSeconds = 3,
    this.useFrontCamera = true,
    this.isMirrored = true,
    this.adminPin = '1031',
    this.resultDurationSeconds = 12,
  });

  BoothConfig copyWith({
    String? webhookUrl,
    int? countdownSeconds,
    bool? useFrontCamera,
    bool? isMirrored,
    String? adminPin,
    int? resultDurationSeconds,
  }) {
    return BoothConfig(
      webhookUrl: webhookUrl ?? this.webhookUrl,
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
      useFrontCamera: useFrontCamera ?? this.useFrontCamera,
      isMirrored: isMirrored ?? this.isMirrored,
      adminPin: adminPin ?? this.adminPin,
      resultDurationSeconds: resultDurationSeconds ?? this.resultDurationSeconds,
    );
  }
}

class FrameItem {
  final String id;
  final String title;
  final String assetPath;
  final Uint8List pngBytes;

  const FrameItem({
    required this.id,
    required this.title,
    required this.assetPath,
    required this.pngBytes,
  });
}

class ImageMergeJob {
  final Uint8List rawPhotoBytes;
  final Uint8List framePngBytes;
  final bool flipHorizontally;
  final int jpegQuality;

  const ImageMergeJob({
    required this.rawPhotoBytes,
    required this.framePngBytes,
    required this.flipHorizontally,
    this.jpegQuality = 95,
  });
}

// ============================================================================
// MOTEUR DE FUSION MATRICIELLE PIXEL-PERFECT (ISOLATE)
// ============================================================================

Uint8List processAndMergePhotoIsolate(ImageMergeJob job) {
  img.Image? capturedImage = img.decodeImage(job.rawPhotoBytes);
  if (capturedImage == null) {
    throw Exception('Impossible de décoder la photo brute.');
  }

  capturedImage = img.bakeOrientation(capturedImage);

  if (job.flipHorizontally) {
    capturedImage = img.flipHorizontal(capturedImage);
  }

  img.Image? frameImage = img.decodePng(job.framePngBytes);
  if (frameImage == null) {
    throw Exception('Impossible de décoder le cadre PNG.');
  }

  final int targetWidth = frameImage.width;
  final int targetHeight = frameImage.height;
  final double targetAspect = targetWidth / targetHeight;

  final int srcWidth = capturedImage.width;
  final int srcHeight = capturedImage.height;
  final double srcAspect = srcWidth / srcHeight;

  int cropWidth = srcWidth;
  int cropHeight = srcHeight;
  int cropX = 0;
  int cropY = 0;

  if (srcAspect > targetAspect) {
    cropWidth = (srcHeight * targetAspect).round();
    cropX = ((srcWidth - cropWidth) / 2).round();
  } else if (srcAspect < targetAspect) {
    cropHeight = (srcWidth / targetAspect).round();
    cropY = ((srcHeight - cropHeight) / 2).round();
  }

  final img.Image croppedPhoto = img.copyCrop(
    capturedImage,
    x: cropX,
    y: cropY,
    width: cropWidth,
    height: cropHeight,
  );

  final img.Image canvas = img.copyResize(
    croppedPhoto,
    width: targetWidth,
    height: targetHeight,
    interpolation: img.Interpolation.linear,
  );

  img.compositeImage(
    canvas,
    frameImage,
    dstX: 0,
    dstY: 0,
    blend: img.BlendMode.alpha,
  );

  return Uint8List.fromList(img.encodeJpg(canvas, quality: job.jpegQuality));
}

// ============================================================================
// GESTION DES RESSOURCES & CADRES PNG DE SECOURS
// ============================================================================

class FrameAssetsManager {
  static const List<Map<String, String>> _configuredFrames = [
    {
      'id': 'pumpkin_border',
      'title': 'Citrouille Maudite',
      'path': 'assets/frames/frame_1.png',
    },
    {
      'id': 'spider_web',
      'title': 'Toile d\'Araignée',
      'path': 'assets/frames/frame_2.png',
    },
    {
      'id': 'vampire_gothic',
      'title': 'Manoir Vampire',
      'path': 'assets/frames/frame_3.png',
    },
    {
      'id': 'neon_witch',
      'title': 'Sorcière Néon',
      'path': 'assets/frames/frame_4.png',
    },
  ];

  static Future<List<FrameItem>> loadAllFrames() async {
    final List<FrameItem> loaded = [];

    for (int i = 0; i < _configuredFrames.length; i++) {
      final item = _configuredFrames[i];
      Uint8List? bytes;

      try {
        final ByteData data = await rootBundle.load(item['path']!);
        bytes = data.buffer.asUint8List();
      } catch (_) {
        bytes = await compute(_generateFallbackHalloweenFrameIsolate, i);
      }

      loaded.add(
        FrameItem(
          id: item['id']!,
          title: item['title']!,
          assetPath: item['path']!,
          pngBytes: bytes,
        ),
      );
    }

    return loaded;
  }

  static Uint8List _generateFallbackHalloweenFrameIsolate(int styleIndex) {
    const int width = 900;
    const int height = 1200;
    final img.Image frame = img.Image(width: width, height: height, numChannels: 4);

    img.fill(frame, color: img.ColorRgba8(0, 0, 0, 0));

    late final img.ColorRgba8 primaryColor;
    late final img.ColorRgba8 secondaryColor;

    switch (styleIndex % 4) {
      case 0:
        primaryColor = img.ColorRgba8(255, 117, 24, 255);
        secondaryColor = img.ColorRgba8(43, 17, 63, 235);
        break;
      case 1:
        primaryColor = img.ColorRgba8(138, 43, 226, 255);
        secondaryColor = img.ColorRgba8(220, 220, 235, 220);
        break;
      case 2:
        primaryColor = img.ColorRgba8(190, 15, 45, 255);
        secondaryColor = img.ColorRgba8(255, 185, 50, 230);
        break;
      default:
        primaryColor = img.ColorRgba8(57, 255, 20, 255);
        secondaryColor = img.ColorRgba8(55, 15, 85, 240);
        break;
    }

    const int border = 36;
    const int footerHeight = 140;

    img.fillRect(frame, x1: 0, y1: 0, x2: width, y2: border, color: primaryColor);
    img.fillRect(
        frame, x1: 0, y1: height - footerHeight, x2: width, y2: height, color: secondaryColor);
    img.fillRect(frame, x1: 0, y1: 0, x2: border, y2: height, color: primaryColor);
    img.fillRect(
        frame, x1: width - border, y1: 0, x2: width, y2: height, color: primaryColor);

    img.drawRect(
      frame,
      x1: border + 8,
      y1: border + 8,
      x2: width - border - 8,
      y2: height - footerHeight - 8,
      color: primaryColor,
      thickness: 4,
    );

    for (int r = 40; r <= 160; r += 40) {
      img.drawLine(
        frame,
        x1: border,
        y1: border + r,
        x2: border + r,
        y2: border,
        color: primaryColor,
        thickness: 3,
      );
      img.drawLine(
        frame,
        x1: width - border,
        y1: border + r,
        x2: width - border - r,
        y2: border,
        color: primaryColor,
        thickness: 3,
      );
    }

    img.drawString(
      frame,
      'HALLOWEEN PHOTOBOOTH',
      font: img.arial48,
      x: 185,
      y: height - 92,
      color: img.ColorRgba8(255, 255, 255, 255),
    );

    return Uint8List.fromList(img.encodePng(frame));
  }
}

// ============================================================================
// SERVICE AUDIO
// ============================================================================

class SoundEffectsService {
  final AudioPlayer _beepPlayer = AudioPlayer();
  final AudioPlayer _shutterPlayer = AudioPlayer();

  late final Uint8List _beepWavBytes;
  late final Uint8List _shutterWavBytes;

  SoundEffectsService() {
    _beepWavBytes = _generateSineWaveWav(frequencyHz: 880, durationMs: 140);
    _shutterWavBytes = _generateShutterWav(durationMs: 160);
  }

  Future<void> playCountdownBeep() async {
    try {
      await _beepPlayer.stop();
      try {
        await _beepPlayer.play(AssetSource('audio/beep.wav'));
      } catch (_) {
        await _beepPlayer.play(BytesSource(_beepWavBytes));
      }
    } catch (_) {}
  }

  Future<void> playShutterSound() async {
    try {
      await _shutterPlayer.stop();
      try {
        await _shutterPlayer.play(AssetSource('audio/shutter.wav'));
      } catch (_) {
        await _shutterPlayer.play(BytesSource(_shutterWavBytes));
      }
    } catch (_) {}
  }

  Uint8List _generateSineWaveWav({required double frequencyHz, required int durationMs}) {
    const int sampleRate = 44100;
    final int numSamples = ((sampleRate * durationMs) / 1000).round();
    final int dataSize = numSamples * 2;
    final ByteData buffer = ByteData(44 + dataSize);

    _writeWavHeader(buffer, sampleRate, dataSize);

    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      final double envelope = 1.0 - (i / numSamples);
      final double sample = math.sin(2 * math.pi * frequencyHz * t) * envelope;
      final int pcmValue = (sample * 24000).toInt().clamp(-32768, 32767);
      buffer.setInt16(44 + i * 2, pcmValue, Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  Uint8List _generateShutterWav({required int durationMs}) {
    const int sampleRate = 44100;
    final int numSamples = ((sampleRate * durationMs) / 1000).round();
    final int dataSize = numSamples * 2;
    final ByteData buffer = ByteData(44 + dataSize);
    final math.Random random = math.Random(1031);

    _writeWavHeader(buffer, sampleRate, dataSize);

    for (int i = 0; i < numSamples; i++) {
      final double progress = i / numSamples;
      final double burst = (progress < 0.25 || (progress > 0.55 && progress < 0.75))
          ? (1.0 - (progress % 0.25) * 4.0)
          : 0.05;
      final double noise = (random.nextDouble() * 2.0 - 1.0) * burst;
      final int pcmValue = (noise * 28000).toInt().clamp(-32768, 32767);
      buffer.setInt16(44 + i * 2, pcmValue, Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  void _writeWavHeader(ByteData buffer, int sampleRate, int dataSize) {
    final List<int> riff = ascii.encode('RIFF');
    final List<int> wave = ascii.encode('WAVE');
    final List<int> fmt = ascii.encode('fmt ');
    final List<int> data = ascii.encode('data');

    for (int i = 0; i < 4; i++) {
      buffer.setUint8(i, riff[i]);
      buffer.setUint8(8 + i, wave[i]);
      buffer.setUint8(12 + i, fmt[i]);
      buffer.setUint8(36 + i, data[i]);
    }
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, 1, Endian.little);
    buffer.setUint16(22, 1, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little);
    buffer.setUint16(32, 2, Endian.little);
    buffer.setUint16(34, 16, Endian.little);
    buffer.setUint32(40, dataSize, Endian.little);
  }

  void dispose() {
    _beepPlayer.dispose();
    _shutterPlayer.dispose();
  }
}

// ============================================================================
// SERVICE STOCKAGE & SYNCHRONISATION CLOUD GOOGLE DRIVE AVEC RETOUR D'URL
// ============================================================================

class StorageAndCloudService {
  static const String _queuePrefsKey = 'halloween_offline_upload_queue';

  static Future<File> savePhotoToLocalGallery(
    Uint8List jpegBytes,
    String fileName,
  ) async {
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final Directory localPhotosDir = Directory('${appDocDir.path}/HalloweenPhotos');
    if (!await localPhotosDir.exists()) {
      await localPhotosDir.create(recursive: true);
    }

    final File localFile = File('${localPhotosDir.path}/$fileName');
    await localFile.writeAsBytes(jpegBytes, flush: true);

    if (Platform.isAndroid) {
      try {
        final Directory publicDir = Directory('/storage/emulated/0/Pictures/HalloweenPhotobooth');
        if (!await publicDir.exists()) {
          await publicDir.create(recursive: true);
        }
        final File galleryFile = File('${publicDir.path}/$fileName');
        await galleryFile.writeAsBytes(jpegBytes, flush: true);
      } catch (_) {}
    }

    return localFile;
  }

  /// Téléverse la photo et renvoie l'URL publique de téléchargement/visualisation
  /// en suivant la redirection HTTP 302 native de Google Apps Script.
  static Future<String?> uploadAndRetrieveDirectUrl({
    required File photoFile,
    required String fileName,
    required String webhookUrl,
  }) async {
    if (webhookUrl.trim().isEmpty) return null;

    try {
      final Uint8List bytes = await photoFile.readAsBytes();
      final String base64Image = base64Encode(bytes);

      final String payload = jsonEncode({
        'image': base64Image,
        'filename': fileName,
      });

      final client = http.Client();
      final request = http.Request('POST', Uri.parse(webhookUrl.trim()))
        ..headers['Content-Type'] = 'application/json'
        ..body = payload
        ..followRedirects = false;

      final streamedResponse =
          await client.send(request).timeout(const Duration(seconds: 25));
      final response = await http.Response.fromStream(streamedResponse);

      // Traitement de la redirection HTTP 302 spécifique à Google Apps Script
      if (response.statusCode == 302 ||
          response.statusCode == 301 ||
          response.statusCode == 307) {
        final String? redirectUrl = response.headers['location'];
        if (redirectUrl != null && redirectUrl.isNotEmpty) {
          final getResponse = await client
              .get(Uri.parse(redirectUrl))
              .timeout(const Duration(seconds: 15));
          if (getResponse.statusCode == 200) {
            final Map<String, dynamic> data =
                jsonDecode(getResponse.body) as Map<String, dynamic>;
            if (data['status'] == 'success' && data['url'] != null) {
              return data['url'] as String;
            }
          }
        }
      } else if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'success' && data['url'] != null) {
          return data['url'] as String;
        }
      }

      // Si échec du retour direct, mise en file d'attente
      await _enqueueOfflinePhoto(photoFile.path, fileName);
    } catch (e) {
      debugPrint('Mode hors-ligne ou erreur de synchronisation : $e');
      await _enqueueOfflinePhoto(photoFile.path, fileName);
    }

    return null;
  }

  static Future<void> _enqueueOfflinePhoto(String filePath, String fileName) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> currentQueue = prefs.getStringList(_queuePrefsKey) ?? [];
    final String entry = jsonEncode({'path': filePath, 'filename': fileName});
    if (!currentQueue.contains(entry)) {
      currentQueue.add(entry);
      await prefs.setStringList(_queuePrefsKey, currentQueue);
    }
  }

  static Future<int> getPendingQueueCount() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_queuePrefsKey) ?? []).length;
  }

  static Future<int> flushOfflineQueue(String webhookUrl) async {
    if (webhookUrl.trim().isEmpty) return 0;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> queue = prefs.getStringList(_queuePrefsKey) ?? [];
    if (queue.isEmpty) return 0;

    final List<String> remaining = [];
    int syncedCount = 0;

    for (final String itemJson in queue) {
      try {
        final Map<String, dynamic> map = jsonDecode(itemJson) as Map<String, dynamic>;
        final String? url = await uploadAndRetrieveDirectUrl(
          photoFile: File(map['path'] as String),
          fileName: map['filename'] as String,
          webhookUrl: webhookUrl.trim(),
        );
        if (url != null) {
          syncedCount++;
        } else {
          remaining.add(itemJson);
        }
      } catch (_) {}
    }

    await prefs.setStringList(_queuePrefsKey, remaining);
    return syncedCount;
  }
}

// ============================================================================
// ÉCRAN PRINCIPAL KIOSQUE & RÉSULTAT AVEC QR CODE
// ============================================================================

class PhotoboothKioskScreen extends StatefulWidget {
  const PhotoboothKioskScreen({super.key});

  @override
  State<PhotoboothKioskScreen> createState() => _PhotoboothKioskScreenState();
}

class _PhotoboothKioskScreenState extends State<PhotoboothKioskScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  String? _cameraError;

  List<FrameItem> _frames = [];
  int _selectedFrameIndex = 0;

  BoothConfig _config = const BoothConfig();
  final SoundEffectsService _soundService = SoundEffectsService();

  bool _isCountingDown = false;
  int _currentCountdownValue = 0;
  bool _showWhiteFlash = false;
  bool _isProcessingImage = false;

  // États du résultat & QR Code
  Uint8List? _finalResultJpegBytes;
  File? _lastSavedFile;
  String? _uploadedPhotoUrl;
  bool _isUploadingForQr = false;

  Timer? _resultReturnTimer;
  double _resultProgress = 1.0;
  Timer? _adminHoldTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeBooth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _adminHoldTimer?.cancel();
    _resultReturnTimer?.cancel();
    _cameraController?.dispose();
    _soundService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _setupCamera();
    }
  }

  Future<void> _initializeBooth() async {
    await _loadConfigFromPrefs();
    final List<FrameItem> frames = await FrameAssetsManager.loadAllFrames();
    if (mounted) {
      setState(() {
        _frames = frames;
      });
    }
    await _setupCamera();

    if (_config.webhookUrl.isNotEmpty) {
      unawaited(StorageAndCloudService.flushOfflineQueue(_config.webhookUrl));
    }
  }

  Future<void> _loadConfigFromPrefs() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _config = BoothConfig(
        webhookUrl: prefs.getString('cfg_webhook_url') ?? '',
        countdownSeconds: prefs.getInt('cfg_countdown_sec') ?? 3,
        useFrontCamera: prefs.getBool('cfg_use_front_cam') ?? true,
        isMirrored: prefs.getBool('cfg_is_mirrored') ?? true,
        adminPin: prefs.getString('cfg_admin_pin') ?? '1031',
        resultDurationSeconds: prefs.getInt('cfg_result_dur_sec') ?? 12,
      );
    });
  }

  Future<void> _saveConfigToPrefs(BoothConfig newConfig) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('cfg_webhook_url', newConfig.webhookUrl);
    await prefs.setInt('cfg_countdown_sec', newConfig.countdownSeconds);
    await prefs.setBool('cfg_use_front_cam', newConfig.useFrontCamera);
    await prefs.setBool('cfg_is_mirrored', newConfig.isMirrored);
    await prefs.setString('cfg_admin_pin', newConfig.adminPin);
    await prefs.setInt('cfg_result_dur_sec', newConfig.resultDurationSeconds);

    final bool cameraChanged = _config.useFrontCamera != newConfig.useFrontCamera;
    setState(() {
      _config = newConfig;
    });

    if (cameraChanged) {
      await _setupCamera();
    }
  }

  Future<void> _setupCamera() async {
    if (globalAvailableCameras.isEmpty) {
      setState(() {
        _cameraError = 'Aucune caméra détectée sur cet appareil.';
        _isCameraInitialized = false;
      });
      return;
    }

    await _cameraController?.dispose();

    final CameraLensDirection desiredDirection =
        _config.useFrontCamera ? CameraLensDirection.front : CameraLensDirection.back;

    CameraDescription selectedCamera = globalAvailableCameras.first;
    for (final cam in globalAvailableCameras) {
      if (cam.lensDirection == desiredDirection) {
        selectedCamera = cam;
        break;
      }
    }

    final CameraController controller = CameraController(
      selectedCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _cameraController = controller;

    try {
      await controller.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _cameraError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cameraError = 'Erreur d\'accès à la caméra : $e';
          _isCameraInitialized = false;
        });
      }
    }
  }

  // ==========================================================================
  // DÉCOMPTE, CAPTURE, FUSION ET GÉNÉRATION DU QR CODE
  // ==========================================================================

  Future<void> _startCountdownAndCapture() async {
    if (_isCountingDown ||
        _isProcessingImage ||
        _finalResultJpegBytes != null ||
        !_isCameraInitialized ||
        _cameraController == null) {
      return;
    }

    setState(() {
      _isCountingDown = true;
      _currentCountdownValue = _config.countdownSeconds;
      _uploadedPhotoUrl = null;
      _isUploadingForQr = false;
    });

    for (int i = _config.countdownSeconds; i >= 1; i--) {
      if (!mounted) return;
      setState(() {
        _currentCountdownValue = i;
      });
      unawaited(_soundService.playCountdownBeep());
      await Future.delayed(const Duration(seconds: 1));
    }

    if (!mounted) return;

    setState(() {
      _isCountingDown = false;
      _showWhiteFlash = true;
    });
    unawaited(_soundService.playShutterSound());

    await Future.delayed(const Duration(milliseconds: 150));

    if (!mounted) return;
    setState(() {
      _showWhiteFlash = false;
      _isProcessingImage = true;
    });

    try {
      final XFile rawPicture = await _cameraController!.takePicture();
      final Uint8List rawBytes = await rawPicture.readAsBytes();
      final Uint8List selectedFrameBytes = _frames[_selectedFrameIndex].pngBytes;

      final Uint8List mergedJpegBytes = await compute(
        processAndMergePhotoIsolate,
        ImageMergeJob(
          rawPhotoBytes: rawBytes,
          framePngBytes: selectedFrameBytes,
          flipHorizontally: _config.isMirrored,
          jpegQuality: 95,
        ),
      );

      final String fileName = 'halloween_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final File savedFile = await StorageAndCloudService.savePhotoToLocalGallery(
        mergedJpegBytes,
        fileName,
      );

      if (!mounted) return;

      setState(() {
        _isProcessingImage = false;
        _finalResultJpegBytes = mergedJpegBytes;
        _lastSavedFile = savedFile;
        _resultProgress = 1.0;
        _isUploadingForQr = _config.webhookUrl.isNotEmpty;
      });

      _startResultAutoReturnTimer();

      // Téléversement immédiat pour récupérer l'URL et afficher le QR Code
      if (_config.webhookUrl.isNotEmpty) {
        StorageAndCloudService.uploadAndRetrieveDirectUrl(
          photoFile: savedFile,
          fileName: fileName,
          webhookUrl: _config.webhookUrl,
        ).then((String? directUrl) {
          if (mounted && _finalResultJpegBytes != null) {
            setState(() {
              _uploadedPhotoUrl = directUrl;
              _isUploadingForQr = false;
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Erreur capture/fusion : $e');
      if (mounted) {
        setState(() {
          _isProcessingImage = false;
          _isCountingDown = false;
        });
      }
    }
  }

  void _startResultAutoReturnTimer() {
    _resultReturnTimer?.cancel();
    const int tickMs = 50;
    final int totalMs = _config.resultDurationSeconds * 1000;
    int elapsedMs = 0;

    _resultReturnTimer = Timer.periodic(const Duration(milliseconds: tickMs), (timer) {
      elapsedMs += tickMs;
      if (!mounted) {
        timer.cancel();
        return;
      }

      final double remainingRatio = (1.0 - (elapsedMs / totalMs)).clamp(0.0, 1.0);
      setState(() {
        _resultProgress = remainingRatio;
      });

      if (elapsedMs >= totalMs) {
        timer.cancel();
        _resetToLiveView(deleteLastPhoto: false);
      }
    });
  }

  Future<void> _resetToLiveView({required bool deleteLastPhoto}) async {
    _resultReturnTimer?.cancel();

    if (deleteLastPhoto && _lastSavedFile != null) {
      try {
        if (await _lastSavedFile!.exists()) {
          await _lastSavedFile!.delete();
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _finalResultJpegBytes = null;
        _lastSavedFile = null;
        _uploadedPhotoUrl = null;
        _isUploadingForQr = false;
        _resultProgress = 1.0;
      });
    }
  }

  // ==========================================================================
  // BACK-OFFICE ADMINISTRATEUR (4 SECONDES COIN HAUT DROIT)
  // ==========================================================================

  void _onAdminCornerTouchDown(TapDownDetails details) {
    _adminHoldTimer?.cancel();
    _adminHoldTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        HapticFeedback.heavyImpact();
        _showPinVerificationDialog();
      }
    });
  }

  void _onAdminCornerTouchEnd() {
    _adminHoldTimer?.cancel();
  }

  Future<void> _showPinVerificationDialog() async {
    final TextEditingController pinController = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: HalloweenColors.surfaceAnthracite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: HalloweenColors.pumpkinOrange, width: 2),
              ),
              title: const Row(
                children: [
                  Icon(Icons.lock, color: HalloweenColors.pumpkinOrange),
                  SizedBox(width: 10),
                  Text('Accès Administrateur'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Saisissez le code PIN à 4 chiffres (défaut : 1031) :',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      letterSpacing: 12,
                      fontWeight: FontWeight.bold,
                      color: HalloweenColors.pumpkinOrange,
                    ),
                    decoration: InputDecoration(
                      errorText: errorText,
                      filled: true,
                      fillColor: HalloweenColors.backgroundBlack,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Annuler', style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HalloweenColors.pumpkinOrange,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () {
                    if (pinController.text.trim() == _config.adminPin) {
                      Navigator.of(dialogContext).pop();
                      _openAdminSettingsModal();
                    } else {
                      setDialogState(() {
                        errorText = 'Code PIN incorrect';
                      });
                    }
                  },
                  child: const Text(
                    'Déverrouiller',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openAdminSettingsModal() async {
    final int pendingCount = await StorageAndCloudService.getPendingQueueCount();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: HalloweenColors.surfaceAnthracite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return AdminSettingsSheet(
          initialConfig: _config,
          pendingQueueCount: pendingCount,
          onSave: (BoothConfig updated) async {
            await _saveConfigToPrefs(updated);
          },
        );
      },
    );

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  // ==========================================================================
  // INTERFACE UTILISATEUR
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HalloweenColors.backgroundBlack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_finalResultJpegBytes != null)
            _buildResultViewWithQr()
          else
            _buildLivePreviewAndControls(),

          if (_isCountingDown) _buildAnimatedCountdownOverlay(),

          if (_isProcessingImage) _buildProcessingOverlay(),

          if (_showWhiteFlash)
            Container(
              color: Colors.white,
              width: double.infinity,
              height: double.infinity,
            ),

          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: _onAdminCornerTouchDown,
              onTapUp: (_) => _onAdminCornerTouchEnd(),
              onTapCancel: _onAdminCornerTouchEnd,
              child: const SizedBox(
                width: 90,
                height: 90,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLivePreviewAndControls() {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.auto_awesome,
                  color: HalloweenColors.pumpkinOrange,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Text(
                  'HALLOWEEN PHOTOBOOTH',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                    color: HalloweenColors.pumpkinOrange,
                    shadows: [
                      Shadow(
                        color: HalloweenColors.pumpkinOrange.withOpacity(0.6),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Container(
                    decoration: BoxDecoration(
                      color: HalloweenColors.surfaceAnthracite,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: HalloweenColors.pumpkinOrange.withOpacity(0.85),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: HalloweenColors.mysticViolet.withOpacity(0.45),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(19),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildCameraFeedWidget(),
                          if (_frames.isNotEmpty)
                            IgnorePointer(
                              child: Image.memory(
                                _frames[_selectedFrameIndex].pngBytes,
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 104,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _frames.length,
              itemBuilder: (context, index) {
                final FrameItem frame = _frames[index];
                final bool isSelected = index == _selectedFrameIndex;
                return GestureDetector(
                  onTap: _isCountingDown
                      ? null
                      : () {
                          setState(() {
                            _selectedFrameIndex = index;
                          });
                        },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.only(right: 14),
                    width: 82,
                    decoration: BoxDecoration(
                      color: HalloweenColors.darkPurple,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? HalloweenColors.pumpkinOrange
                            : Colors.white24,
                        width: isSelected ? 3.5 : 1.5,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: HalloweenColors.pumpkinOrange.withOpacity(0.5),
                                blurRadius: 10,
                              ),
                            ]
                          : [],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(6.0),
                            child: Image.memory(
                              frame.pngBytes,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5, left: 4, right: 4),
                          child: Text(
                            frame.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight:
                                  isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected
                                  ? HalloweenColors.pumpkinOrange
                                  : Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: GestureDetector(
              onTap: _isCountingDown ? null : _startCountdownAndCapture,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isCountingDown ? 0.4 : 1.0,
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [
                        HalloweenColors.pumpkinOrange,
                        HalloweenColors.pumpkinGlow,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: Colors.white, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: HalloweenColors.pumpkinOrange.withOpacity(0.65),
                        blurRadius: 20,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    size: 42,
                    color: HalloweenColors.backgroundBlack,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraFeedWidget() {
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: HalloweenColors.pumpkinOrange,
                size: 56,
              ),
              const SizedBox(height: 12),
              Text(
                _cameraError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isCameraInitialized || _cameraController == null) {
      return const Center(
        child: CircularProgressIndicator(color: HalloweenColors.pumpkinOrange),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _cameraController!.value.previewSize!.height,
              height: _cameraController!.value.previewSize!.width,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.rotationY(_config.isMirrored ? math.pi : 0.0),
                child: CameraPreview(_cameraController!),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedCountdownOverlay() {
    return Container(
      color: Colors.black45,
      alignment: Alignment.center,
      child: TweenAnimationBuilder<double>(
        key: ValueKey<int>(_currentCountdownValue),
        tween: Tween<double>(begin: 1.7, end: 1.0),
        duration: const Duration(milliseconds: 750),
        curve: Curves.elasticOut,
        builder: (context, scaleValue, child) {
          return Transform.scale(
            scale: scaleValue,
            child: Container(
              width: 190,
              height: 190,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: HalloweenColors.darkPurple.withOpacity(0.88),
                border: Border.all(
                  color: HalloweenColors.pumpkinOrange,
                  width: 5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: HalloweenColors.pumpkinOrange.withOpacity(0.75),
                    blurRadius: 35,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Text(
                '$_currentCountdownValue',
                style: const TextStyle(
                  fontSize: 105,
                  fontWeight: FontWeight.w900,
                  color: HalloweenColors.pumpkinOrange,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(
              color: HalloweenColors.pumpkinOrange,
              strokeWidth: 6,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Création du souvenir et du QR Code...',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: HalloweenColors.textLight,
              shadows: [
                Shadow(
                  color: HalloweenColors.pumpkinOrange.withOpacity(0.6),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Écran de résultat avec affichage de la photo et du QR Code Google Drive
  Widget _buildResultViewWithQr() {
    final int secondsLeft =
        (_resultProgress * _config.resultDurationSeconds).ceil();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          children: [
            const Text(
              'MAGNIFIQUE HORREUR !',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: HalloweenColors.pumpkinOrange,
              ),
            ),
            const SizedBox(height: 10),

            // Zone centrale : Photo et QR Code
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Sur tablette large (mode portrait ou grand écran)
                  final bool isWide = constraints.maxWidth > 550;

                  final Widget photoWidget = AspectRatio(
                    aspectRatio: 3 / 4,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: HalloweenColors.pumpkinOrange,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: HalloweenColors.pumpkinOrange.withOpacity(0.4),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(17),
                        child: Image.memory(
                          _finalResultJpegBytes!,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  );

                  final Widget qrWidget = _buildQrCodeContainer();

                  if (isWide) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(flex: 3, child: photoWidget),
                        const SizedBox(width: 24),
                        Flexible(flex: 2, child: qrWidget),
                      ],
                    );
                  } else {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(child: photoWidget),
                        const SizedBox(height: 12),
                        qrWidget,
                      ],
                    );
                  }
                },
              ),
            ),

            const SizedBox(height: 14),

            // Barre de compte à rebours
            Column(
              children: [
                Text(
                  'Prêt pour l\'invité suivant dans $secondsLeft s...',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _resultProgress,
                    minHeight: 8,
                    backgroundColor: HalloweenColors.darkPurple,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      HalloweenColors.pumpkinOrange,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Bouton Reprendre
            SizedBox(
              width: 220,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: HalloweenColors.darkPurple,
                  foregroundColor: Colors.white,
                  side: const BorderSide(
                    color: HalloweenColors.pumpkinOrange,
                    width: 2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => _resetToLiveView(deleteLastPhoto: true),
                icon: const Icon(Icons.refresh, color: HalloweenColors.pumpkinOrange),
                label: const Text(
                  'Reprendre',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Conteneur du QR Code à fond blanc contrasté pour un scan instantané
  Widget _buildQrCodeContainer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: HalloweenColors.surfaceAnthracite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: HalloweenColors.pumpkinOrange.withOpacity(0.7),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: HalloweenColors.pumpkinOrange.withOpacity(0.2),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'RÉCUPÈRE TA PHOTO',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: HalloweenColors.pumpkinOrange,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Scanne avec ton smartphone',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 10),

          // État du QR Code : Chargement / Affichage / Hors-ligne
          if (_isUploadingForQr) ...[
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: HalloweenColors.pumpkinOrange,
                    strokeWidth: 3,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Envoi Cloud...',
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_uploadedPhotoUrl != null && _uploadedPhotoUrl!.isNotEmpty) ...[
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 8),
                ],
              ),
              padding: const EdgeInsets.all(8),
              child: QrImageView(
                data: _uploadedPhotoUrl!,
                version: QrVersions.auto,
                size: 140.0,
                backgroundColor: Colors.white,
                padding: EdgeInsets.zero,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
          ] else ...[
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: HalloweenColors.darkPurple,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              padding: const EdgeInsets.all(10),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 36),
                  SizedBox(height: 6),
                  Text(
                    'Enregistré en galerie',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// MODALE D'ADMINISTRATION
// ============================================================================

class AdminSettingsSheet extends StatefulWidget {
  final BoothConfig initialConfig;
  final int pendingQueueCount;
  final Future<void> Function(BoothConfig) onSave;

  const AdminSettingsSheet({
    super.key,
    required this.initialConfig,
    required this.pendingQueueCount,
    required this.onSave,
  });

  @override
  State<AdminSettingsSheet> createState() => _AdminSettingsSheetState();
}

class _AdminSettingsSheetState extends State<AdminSettingsSheet> {
  late TextEditingController _webhookController;
  late int _countdownSeconds;
  late bool _useFrontCamera;
  late bool _isMirrored;
  late int _resultDurationSeconds;
  late int _pendingCount;
  bool _isSyncingQueue = false;

  @override
  void initState() {
    super.initState();
    _webhookController = TextEditingController(text: widget.initialConfig.webhookUrl);
    _countdownSeconds = widget.initialConfig.countdownSeconds;
    _useFrontCamera = widget.initialConfig.useFrontCamera;
    _isMirrored = widget.initialConfig.isMirrored;
    _resultDurationSeconds = widget.initialConfig.resultDurationSeconds;
    _pendingCount = widget.pendingQueueCount;
  }

  @override
  void dispose() {
    _webhookController.dispose();
    super.dispose();
  }

  Future<void> _forceOfflineQueueSync() async {
    setState(() {
      _isSyncingQueue = true;
    });
    await StorageAndCloudService.flushOfflineQueue(_webhookController.text.trim());
    final int updatedCount = await StorageAndCloudService.getPendingQueueCount();
    if (mounted) {
      setState(() {
        _pendingCount = updatedCount;
        _isSyncingQueue = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: bottomInset + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.settings, color: HalloweenColors.pumpkinOrange, size: 28),
                    SizedBox(width: 10),
                    Text(
                      'Back-Office Administrateur',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 28),

            const Text(
              'URL du Webhook Google Apps Script (Drive) :',
              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _webhookController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'https://script.google.com/macros/s/.../exec',
                prefixIcon: const Icon(Icons.link, color: HalloweenColors.pumpkinOrange),
                filled: true,
                fillColor: HalloweenColors.backgroundBlack,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 18),

            const Text(
              'Durée d\'affichage du résultat & QR Code :',
              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Row(
              children: [8, 12, 16].map((int sec) {
                final bool selected = _resultDurationSeconds == sec;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text('$sec s'),
                      selected: selected,
                      selectedColor: HalloweenColors.pumpkinOrange,
                      labelStyle: TextStyle(
                        color: selected ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (_) {
                        setState(() {
                          _resultDurationSeconds = sec;
                        });
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),

            const Text(
              'Temps du décompte avant prise de vue :',
              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Row(
              children: [3, 5, 10].map((int sec) {
                final bool selected = _countdownSeconds == sec;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text('$sec s'),
                      selected: selected,
                      selectedColor: HalloweenColors.pumpkinOrange,
                      labelStyle: TextStyle(
                        color: selected ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (_) {
                        setState(() {
                          _countdownSeconds = sec;
                        });
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: HalloweenColors.pumpkinOrange,
              secondary: const Icon(Icons.cameraswitch, color: HalloweenColors.pumpkinOrange),
              title: const Text('Utiliser la caméra frontale'),
              value: _useFrontCamera,
              onChanged: (bool val) {
                setState(() {
                  _useFrontCamera = val;
                });
              },
            ),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: HalloweenColors.pumpkinOrange,
              secondary: const Icon(Icons.flip, color: HalloweenColors.pumpkinOrange),
              title: const Text('Effet miroir'),
              value: _isMirrored,
              onChanged: (bool val) {
                setState(() {
                  _isMirrored = val;
                });
              },
            ),

            const Divider(color: Colors.white24, height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Photos en attente réseau : $_pendingCount',
                  style: const TextStyle(color: Colors.white70),
                ),
                TextButton.icon(
                  onPressed: _isSyncingQueue ? null : _forceOfflineQueueSync,
                  icon: _isSyncingQueue
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload, color: HalloweenColors.pumpkinOrange),
                  label: const Text(
                    'Synchroniser',
                    style: TextStyle(color: HalloweenColors.pumpkinOrange),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: HalloweenColors.pumpkinOrange,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () async {
                  final BoothConfig updated = widget.initialConfig.copyWith(
                    webhookUrl: _webhookController.text.trim(),
                    countdownSeconds: _countdownSeconds,
                    useFrontCamera: _useFrontCamera,
                    isMirrored: _isMirrored,
                    resultDurationSeconds: _resultDurationSeconds,
                  );
                  await widget.onSave(updated);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                icon: const Icon(Icons.save),
                label: const Text(
                  'Enregistrer',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
