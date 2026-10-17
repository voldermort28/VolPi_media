import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Sửa kích thước mặc định to gấp đôi cho macOS (1440 x 900) và căn giữa màn hình
    if let screen = self.screen ?? NSScreen.main {
      let visible = screen.visibleFrame
      // Gấp đôi kích thước cũ (800x600 -> ~1440x900), vừa vặn và thẩm mỹ trên mọi kích thước màn hình
      let targetWidth = min(1440.0, visible.width * 0.92)
      let targetHeight = min(900.0, visible.height * 0.92)
      let x = visible.origin.x + (visible.width - targetWidth) / 2.0
      let y = visible.origin.y + (visible.height - targetHeight) / 2.0
      self.setFrame(NSRect(x: x, y: y, width: targetWidth, height: targetHeight), display: true)
    } else {
      self.setFrame(NSRect(x: 100, y: 100, width: 1440, height: 900), display: true)
    }

    // Đặt kích thước tối thiểu để không bị co hẹp giao diện
    self.minSize = NSSize(width: 960, height: 600)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
