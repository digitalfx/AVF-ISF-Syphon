import Cocoa
import AVFoundation

final class ViewController: NSViewController {
    
    var displayLink: CVDisplayLink?
    var context: NSOpenGLContext!
    var globalBufferPool: VVBufferPool!
    
    var player: AVPlayer?
    var videoOutput: AVPlayerItemVideoOutput!
    var isfScene: ISFGLScene!
    var syphonServer: SyphonServer?
    
    @IBOutlet weak var startCVDisplayLinkButton: NSButton!
    
    
    // MARK: Setup
    override func viewDidLoad() {
        super.viewDidLoad()
        
        context = NSOpenGLContext(format: GLScene.defaultPixelFormat(), share: nil)
        
        player = AVPlayer(url: Bundle.main.url(forResource: "Animation", withExtension: "mov")!)
        player?.isMuted = true
        
        let bufferAttributes: [String: Any] = [
            String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_32BGRA),
            String(kCVPixelBufferIOSurfacePropertiesKey): [String: AnyObject](),
            String(kCVPixelBufferOpenGLCompatibilityKey): true
        ]
        
        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: bufferAttributes)
        videoOutput.suppressesPlayerRendering = true
        player?.currentItem?.add(videoOutput)
        
        
        //	create the global buffer pool from the shared context
        VVBufferPool.createGlobalVVBufferPool(withSharedContext: context)
        //	...other stuff in the VVBufferPool framework- like the views, the buffer copier, etc- will
        //	automatically use the global buffer pool's shared context to set themselves up to function with the pool.
        
        // keep a reference to the global buffer pool cast as a VVBufferPool 
        globalBufferPool = VVBufferPool.globalVVBufferPool() as? VVBufferPool
        
        //	load an ISF file
        isfScene = ISFGLScene(sharedContext: context)
        isfScene.size = NSSize(width: 1280, height: 720)
        isfScene.useFile(Bundle.main.path(forResource: "Glow.fs", ofType: "fs"))
        
        // setup inputs
        isfScene.setValue(ISFAttribVal(floatVal: Float(0.0)), forInputKey: "intensity")
        
        syphonServer = SyphonServer(name: "ISF Glow", context: context.cglContextObj, options: nil)
    }
    
    
    // MARK: CVDisplayLink Rendering
    @IBAction func startCVDisplayLink(_ sender: AnyObject) {
        startCVDisplayLinkButton.isEnabled = false
        
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        CVDisplayLinkSetOutputCallback(displayLink!, { (displayLink, inNow, inOutputTime, flagsIn, flagsOut, displayLinkContext) -> CVReturn in
            autoreleasepool {
                // interpret displayLinkContext as this class to call functions
                unsafeBitCast(displayLinkContext, to: ViewController.self).screenRefreshForTime(inOutputTime.pointee)
            }
            return kCVReturnSuccess
            }, Unmanaged.passUnretained(self).toOpaque())
        
        CVDisplayLinkStart(displayLink!)
        player?.play()
    }
    
    func screenRefreshForTime(_ timestamp: CVTimeStamp) {
        if cvRenderToBuffer(timestamp) {
            isfRenderToSyphon()
        }
    }
    
    // render to buffer from AVPlayerItemVideoOutput
    func cvRenderToBuffer(_ timestamp: CVTimeStamp) -> Bool {
        let itemTime = videoOutput.itemTime(for: timestamp)
        guard videoOutput.hasNewPixelBuffer(forItemTime: itemTime) else { NSLog("no buffer"); return false }
        guard let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else { NSLog("no copy"); return false }
        guard let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { NSLog("surface error"); return false }
        
        let tex = globalBufferPool.allocBuffer(forIOSurfaceID: IOSurfaceGetID(surface))
        isfScene.setFilterInputImageBuffer(tex)
        
        return true
    }
    
    // render current contents of texture through isf shader and publish to syphon server
    func isfRenderToSyphon() {
        //	tell the ISF scene to render a buffer (this renders to a GL texture)
        if let newTex = isfScene.allocAndRenderABuffer() {
        syphonServer?.publishFrameTexture(newTex.name, textureTarget: newTex.target, imageRegion: NSRect(origin: CGPoint(x: 0, y: 0), size: newTex.size), textureDimensions: newTex.size, flipped: true)
        
        }
        //	tell the buffer pool to do its housekeeping (releases any "old" resources in the pool that have been sticking around for a while)
        globalBufferPool.housekeeping()
    }
    
    
    // MARK: Update
    @IBAction func rewind(_ sender: AnyObject) {
        player?.seek(to: CMTime.zero)
        player?.play()
    }
    
    @IBAction func sliderDidChange(_ sender: NSSlider) {
        isfScene.setValue(ISFAttribVal(floatVal: sender.floatValue), forInputKey: "intensity")
    }
    
}
