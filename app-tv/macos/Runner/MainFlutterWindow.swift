import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Cho phép thu nhỏ cửa sổ linh hoạt về kích thước nhỏ gọn
    self.minSize = NSSize(width: 480, height: 320)

    // Ghi nhớ kích thước và vị trí cửa sổ từ lần mở trước của người dùng
    let autosaveName = "VolPiMediaMainWindow"
    self.setFrameAutosaveName(autosaveName)

    if !self.setFrameUsingName(autosaveName) {
      // Khi mở lần đầu chưa có cấu hình cũ: Mặc định mở kích thước chuẩn (1440 x 900) và căn giữa màn hình
      if let screen = self.screen ?? NSScreen.main {
        let visible = screen.visibleFrame
        let targetWidth = min(1440.0, visible.width * 0.92)
        let targetHeight = min(900.0, visible.height * 0.92)
        let x = visible.origin.x + (visible.width - targetWidth) / 2.0
        let y = visible.origin.y + (visible.height - targetHeight) / 2.0
        self.setFrame(NSRect(x: x, y: y, width: targetWidth, height: targetHeight), display: true)
      } else {
        self.setFrame(NSRect(x: 100, y: 100, width: 1440, height: 900), display: true)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
