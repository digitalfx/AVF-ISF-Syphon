import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    let appNapActivity = NSProcessInfo.processInfo().beginActivityWithOptions(.LatencyCritical, reason: "Real time graphics output")

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        // Insert code here to initialize your application
    }

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }


}

