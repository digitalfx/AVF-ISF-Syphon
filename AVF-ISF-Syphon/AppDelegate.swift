import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    let appNapActivity = ProcessInfo.processInfo.beginActivity(options: .latencyCritical, reason: "Real time graphics output")

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }


}

