import Cocoa
import AVFoundation

final class ViewController: NSViewController {
    
    var displayLink: CVDisplayLink?
    var context: NSOpenGLContext!
    
    var player: AVPlayer?
    var videoOutput: AVPlayerItemVideoOutput!
    var isfScene: ISFGLScene!
    var syphonServer: SyphonServer?
    
    @IBOutlet weak var startCVDisplayLinkButton: NSButton!
    
    
    // MARK: Setup
    override func viewDidLoad() {
        super.viewDidLoad()
        
        context = NSOpenGLContext(format: GLScene.defaultPixelFormat(), shareContext: nil)
        
        player = AVPlayer(URL: NSBundle.mainBundle().URLForResource("Animation", withExtension: "mov")!)
        player?.muted = true
        
        let bufferAttributes: [String: AnyObject] = [
            String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_32BGRA),
            String(kCVPixelBufferIOSurfacePropertiesKey): [String: AnyObject](),
            String(kCVPixelBufferOpenGLCompatibilityKey): true
        ]
        
        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: bufferAttributes)
        videoOutput.suppressesPlayerRendering = true
        player?.currentItem?.addOutput(videoOutput)
        
        
        //	create the global buffer pool from the shared context
        VVBufferPool.createGlobalVVBufferPoolWithSharedContext(context)
        //	...other stuff in the VVBufferPool framework- like the views, the buffer copier, etc- will
        //	automatically use the global buffer pool's shared context to set themselves up to function with the pool.
        
        //	load an ISF file
        isfScene = ISFGLScene(sharedContext: context)
        isfScene.size = NSSize(width: 1280, height: 720)
        isfScene.useFile(NSBundle.mainBundle().pathForResource("Glow.fs", ofType: "fs"))
        
        // setup inputs
        isfScene.setValue(ISFAttribVal(floatVal: Float(0.0)), forInputKey: "intensity")
        
        syphonServer = SyphonServer(name: "ISF Glow", context: context.CGLContextObj, options: nil)
    }
    
    
    // MARK: CVDisplayLink Rendering
    @IBAction func startCVDisplayLink(sender: AnyObject) {
        startCVDisplayLinkButton.enabled = false
        
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        CVDisplayLinkSetOutputCallback(displayLink!, { (displayLink, inNow, inOutputTime, flagsIn, flagsOut, displayLinkContext) -> CVReturn in
            autoreleasepool {
                // interpret displayLinkContext as this class to call functions
                unsafeBitCast(displayLinkContext, ViewController.self).screenRefreshForTime(inOutputTime.memory)
            }
            return kCVReturnSuccess
            }, UnsafeMutablePointer<Void>(unsafeAddressOf(self)))
        
        CVDisplayLinkStart(displayLink!)
        player?.play()
    }
    
    func screenRefreshForTime(timestamp: CVTimeStamp) {
        if cvRenderToBuffer(timestamp) {
            isfRenderToSyphon()
        }
    }
    
    // render to buffer from AVPlayerItemVideoOutput
    func cvRenderToBuffer(timestamp: CVTimeStamp) -> Bool {
        let itemTime = videoOutput.itemTimeForCVTimeStamp(timestamp)
        guard videoOutput.hasNewPixelBufferForItemTime(itemTime) else { NSLog("no buffer"); return false }
        guard let pixelBuffer = videoOutput.copyPixelBufferForItemTime(itemTime, itemTimeForDisplay: nil) else { NSLog("no copy"); return false }
        guard let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { NSLog("surface error"); return false }
        
        let tex = VVBufferPool.globalVVBufferPool().allocBufferForIOSurfaceID(IOSurfaceGetID(surface))
        isfScene.setFilterInputImageBuffer(tex)
        
        return true
    }
    
    // render current contents of texture through isf shader and publish to syphon server
    func isfRenderToSyphon() {
        //	tell the ISF scene to render a buffer (this renders to a GL texture)
        let newTex = isfScene.allocAndRenderABuffer()
        
        syphonServer?.publishFrameTexture(newTex.name, textureTarget: newTex.target, imageRegion: NSRect(origin: CGPoint(x: 0, y: 0), size: newTex.size), textureDimensions: newTex.size, flipped: true)
        
        //	tell the buffer pool to do its housekeeping (releases any "old" resources in the pool that have been sticking around for a while)
        VVBufferPool.globalVVBufferPool().housekeeping()
    }
    
    
    // MARK: Update
    @IBAction func rewind(sender: AnyObject) {
        player?.seekToTime(kCMTimeZero)
        player?.play()
    }
    
    @IBAction func sliderDidChange(sender: NSSlider) {
        isfScene.setValue(ISFAttribVal(floatVal: sender.floatValue), forInputKey: "intensity")
    }
    
}