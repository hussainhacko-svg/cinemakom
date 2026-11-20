import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let night = NSColor(srgbRed: 0x15 / 255.0, green: 0x10 / 255.0, blue: 0x0C / 255.0, alpha: 1.0)
    self.appearance = NSAppearance(named: .darkAqua)
    self.backgroundColor = night
    flutterViewController.backgroundColor = night
    self.contentViewController = flutterViewController
    self.minSize = NSSize(width: 400, height: 500)
    self.setContentSize(NSSize(width: 1280, height: 720))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
