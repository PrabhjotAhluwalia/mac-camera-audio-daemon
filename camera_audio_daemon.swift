import Foundation
import AVFoundation
import Darwin

final class CameraAudioDaemon: NSObject {
  private let pollIntervalSeconds: TimeInterval = 1.0
  private let outputDir: URL
  private var pollTimer: Timer?
  private var audioRecorder: AVAudioRecorder?
  private var activeRecordingURL: URL?
  private var isCameraInUse = false
  private var isMicPermissionGranted = false
  private let forceRecord = ProcessInfo.processInfo.environment["CAMERA_AUDIO_DAEMON_FORCE_RECORD"] == "1"
  private var lockFileDescriptor: Int32 = -1

  init(outputDir: URL) {
    self.outputDir = outputDir
    super.init()
  }

  func start() {
    guard acquireSingleInstanceLock() else {
      log("Another daemon instance is already running. Exiting.")
      exit(0)
    }
    ensureOutputDirectory()
    requestMicrophonePermission()
    startPolling()
    log("Started. Output: \(outputDir.path)")
    RunLoop.main.run()
  }

  private func startPolling() {
    pollTimer?.invalidate()
    pollTimer = Timer.scheduledTimer(withTimeInterval: pollIntervalSeconds, repeats: true) { [weak self] _ in
      self?.checkCameraState()
    }
    RunLoop.main.add(pollTimer!, forMode: .common)
    checkCameraState()
  }

  private func checkCameraState() {
    if forceRecord {
      if !isCameraInUse {
        isCameraInUse = true
        log("Force mode enabled: starting recording without camera-state check.")
        startAudioRecording()
      }
      return
    }

    var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
    if #available(macOS 14.0, *) {
      deviceTypes.append(.external)
    } else {
      deviceTypes.append(.externalUnknown)
    }

    let discovery = AVCaptureDevice.DiscoverySession(
      deviceTypes: deviceTypes,
      mediaType: .video,
      position: .unspecified
    )
    let devices = discovery.devices
    let currentlyInUse = devices.contains { device in
      device.isConnected && device.isInUseByAnotherApplication
    }
    let ioRegistryInUse = isFrontCameraActiveViaIORegistry()
    let finalInUse = currentlyInUse || ioRegistryInUse

    if finalInUse && !isCameraInUse {
      isCameraInUse = true
      log("Camera ON detected (AVFoundation=\(currentlyInUse), IORegistry=\(ioRegistryInUse)). Starting audio recording.")
      startAudioRecording()
      return
    }

    if !finalInUse && isCameraInUse {
      isCameraInUse = false
      log("Camera OFF detected. Stopping audio recording.")
      stopAudioRecording()
    }
  }

  private func requestMicrophonePermission() {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    log("Microphone permission status: \(status.rawValue)")
    let semaphore = DispatchSemaphore(value: 0)

    AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
      self?.isMicPermissionGranted = granted
      semaphore.signal()
    }

    _ = semaphore.wait(timeout: .now() + 8)
    if !isMicPermissionGranted {
      log("Microphone permission missing. Grant mic access in System Settings -> Privacy & Security -> Microphone.")
    } else {
      log("Microphone permission granted.")
    }
  }

  private func startAudioRecording() {
    if audioRecorder?.isRecording == true { return }
    if !isMicPermissionGranted {
      requestMicrophonePermission()
      if !isMicPermissionGranted {
        log("Camera turned on, but mic access is still blocked.")
        return
      }
    }

    let filename = "camera-session-\(timestamp()).m4a"
    let fileURL = outputDir.appendingPathComponent(filename)

    do {
      let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        AVEncoderBitRateKey: 192000
      ]

      let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
      recorder.isMeteringEnabled = true
      recorder.prepareToRecord()

      guard recorder.record() else {
        log("AVAudioRecorder refused to start.")
        return
      }

      audioRecorder = recorder
      activeRecordingURL = fileURL
      log("Recording started: \(fileURL.path)")
    } catch {
      log("Recording failed: \(error.localizedDescription)")
    }
  }

  private func stopAudioRecording() {
    let finishedURL = activeRecordingURL
    if let recorder = audioRecorder, recorder.isRecording {
      recorder.stop()
      log("Recording stopped.")
    }
    audioRecorder = nil
    activeRecordingURL = nil

    if let finishedURL {
      DispatchQueue.global(qos: .utility).async { [weak self] in
        self?.normalizeRecordingIfPossible(fileURL: finishedURL)
      }
    }
  }

  private func ensureOutputDirectory() {
    do {
      try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    } catch {
      log("Could not create output directory: \(error.localizedDescription)")
    }
  }

  private func isFrontCameraActiveViaIORegistry() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
    process.arguments = ["-r", "-l", "-c", "AppleH16CamIn"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()

    do {
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else { return false }
    } catch {
      return false
    }

    let data = output.fileHandleForReading.readDataToEndOfFile()
    guard let text = String(data: data, encoding: .utf8) else { return false }
    return text.contains("\"FrontCameraActive\" = Yes")
  }

  private func log(_ message: String) {
    let line = "[CameraAudioDaemon] \(message)"
    print(line)
    fflush(stdout)
  }

  private func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    return formatter.string(from: Date())
  }

  private func normalizeRecordingIfPossible(fileURL: URL) {
    guard let ffmpeg = resolveFFmpegPath() else {
      log("ffmpeg not found. Skipping normalization.")
      return
    }

    let tmpURL = fileURL.deletingPathExtension().appendingPathExtension("normalized.m4a")
    let process = Process()
    process.executableURL = ffmpeg
    process.arguments = [
      "-y",
      "-i", fileURL.path,
      "-af", "dynaudnorm=f=150:g=15",
      "-c:a", "aac",
      "-b:a", "192k",
      tmpURL.path
    ]
    process.standardOutput = Pipe()
    process.standardError = Pipe()

    do {
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        log("Normalization failed with exit code \(process.terminationStatus).")
        try? FileManager.default.removeItem(at: tmpURL)
        return
      }

      try? FileManager.default.removeItem(at: fileURL)
      try FileManager.default.moveItem(at: tmpURL, to: fileURL)
      log("Normalization complete: \(fileURL.lastPathComponent)")
    } catch {
      try? FileManager.default.removeItem(at: tmpURL)
      log("Normalization error: \(error.localizedDescription)")
    }
  }

  private func resolveFFmpegPath() -> URL? {
    let candidates = [
      "/opt/homebrew/bin/ffmpeg",
      "/usr/local/bin/ffmpeg",
      "/usr/bin/ffmpeg"
    ]
    for path in candidates where FileManager.default.fileExists(atPath: path) {
      return URL(fileURLWithPath: path)
    }
    return nil
  }

  func shutdown() {
    pollTimer?.invalidate()
    pollTimer = nil
    stopAudioRecording()
    releaseSingleInstanceLock()
    log("Shutdown complete.")
    exit(0)
  }

  private func acquireSingleInstanceLock() -> Bool {
    let lockPath = "/tmp/com.prabhjot.camera-audio-daemon.lock"
    lockFileDescriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    if lockFileDescriptor == -1 { return true }

    if flock(lockFileDescriptor, LOCK_EX | LOCK_NB) != 0 {
      close(lockFileDescriptor)
      lockFileDescriptor = -1
      return false
    }

    let pidString = "\(getpid())\n"
    _ = ftruncate(lockFileDescriptor, 0)
    _ = pidString.withCString { ptr in
      write(lockFileDescriptor, ptr, strlen(ptr))
    }
    return true
  }

  private func releaseSingleInstanceLock() {
    guard lockFileDescriptor != -1 else { return }
    flock(lockFileDescriptor, LOCK_UN)
    close(lockFileDescriptor)
    lockFileDescriptor = -1
  }
}

private var daemonRef: CameraAudioDaemon?
private var signalSources: [DispatchSourceSignal] = []

private func installSignalHandlers() {
  signal(SIGINT, SIG_IGN)
  signal(SIGTERM, SIG_IGN)

  let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
  sigint.setEventHandler {
    daemonRef?.shutdown()
  }
  sigint.resume()
  signalSources.append(sigint)

  let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
  sigterm.setEventHandler {
    daemonRef?.shutdown()
  }
  sigterm.resume()
  signalSources.append(sigterm)
}

let recordingPath = ProcessInfo.processInfo.environment["CAMERA_AUDIO_RECORDING_DIR"]
  ?? FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Desktop")
    .appendingPathComponent("career-ops")
    .appendingPathComponent("mac-camera-audio-daemon")
    .appendingPathComponent("Voice recordings")
    .path
let recordings = URL(fileURLWithPath: recordingPath)

let daemon = CameraAudioDaemon(outputDir: recordings)
daemonRef = daemon
installSignalHandlers()
daemon.start()
