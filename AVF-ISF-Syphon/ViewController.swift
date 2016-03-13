import Cocoa
import AVFoundation

final class ViewController: NSViewController {
    
    
    var displayTimer: NSTimer?
    var displayLink: CVDisplayLink?
    
    var context: NSOpenGLContext!
    var buffer: VVBuffer!
    var isfScene: ISFGLScene!
    
    var player: AVPlayer?
    var videoOutput: AVPlayerItemVideoOutput!
    var texture = GLuint()
    var sceneSize = NSSize(width: 1280, height: 720)
    var syphonServer: SyphonServer?
    
    @IBOutlet weak var startNSTimerButton: NSButton!
    @IBOutlet weak var startCVDisplayLinkButton: NSButton!
    
    
    
    // MARK: Setup
    override func viewDidLoad() {
        super.viewDidLoad()
        
        context = NSOpenGLContext(format: GLScene.defaultPixelFormat(), shareContext: nil)
        context.makeCurrentContext()
        
        if texture == 0 { glGenTextures(1, &texture) }
        
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
        
        vvBufferFromTexture(texture)
        
        //	load an ISF file
        isfScene = ISFGLScene(sharedContext: context)
        isfScene.size = sceneSize
        isfScene.useFile(NSBundle.mainBundle().pathForResource("Glow.fs", ofType: "fs"))
        
        // setup inputs
        isfScene.setFilterInputImageBuffer(buffer)
        isfScene.setValue(ISFAttribVal(floatVal: Float(0.0)), forInputKey: "intensity")
        
        syphonServer = SyphonServer(name: "ISF Glow", context: context.CGLContextObj, options: nil)
    }
    
    func vvBufferFromTexture(texture: GLuint) {
        //	 alloc the VVBuffer (using the global/singleton buffer pool we created on app launch)		*/
        buffer = VVBuffer(pool: VVBufferPool.globalVVBufferPool())
        //	timestamp the buffer.  not strictly necessary, but useful if you need it.
        VVBufferPool.timestampThisBuffer(buffer)
        //	get the buffer descriptor.  this is a c struct that describes some of the basic buffer parameters.  these types are defined in VVBuffer.h, but they exist largely to track GL equivalents- so you can use those as well.
        let desc = buffer.descriptorPtr()
        desc.memory.type = .Tex	//	the buffer represents a GL texture
        desc.memory.target = GLuint(GL_TEXTURE_RECTANGLE_EXT)	//	determined when we created the initial texture (it's a 2D texture)
        desc.memory.internalFormat = .IF_RGBA8	//	''
        desc.memory.pixelFormat = .PF_RGBA	//	''
        desc.memory.pixelType = .PT_U_Int_8888_Rev	//	''
        desc.memory.cpuBackingType = .None	//	there's no CPU backing
        desc.memory.gpuBackingType = .External	//	there's a GPU backing, but it's external (the texture was created outside of VVBufferPool, so if we set this then VVBufferPool won't try to release the underlying texture)
        desc.memory.name = texture	//	determined when we created the initial texture
        desc.memory.texRangeFlag = false	//	reserved, set to NO for now
        desc.memory.texClientStorageFlag = false	//	''
        desc.memory.msAmount = 0	//	only used with renderbuffers doing multi-sample anti-aliasing.  ignored with textures, set to 0.
        desc.memory.localSurfaceID = 0	//	only used when working with associating textures with IOSurfaces- set to 0.
        //	set up the basic properties of the buffer
        buffer.preferDeletion = true	//	if we set this to YES then the buffer will be deleted when it's freed (instead of going into a pool).  technically, we don't need to do this: the GPU backing was defined as 'VVBufferGPUBack_External' earlier, which would automatically ensure that the buffer isn't pooled.  but this is an example- and the "preferDeletion" var on a VVBuffer can be used with *any* VVBuffer...
        buffer.setSize(NSSize(width: 1280, height: 720))	//	the "size" of a VVBuffer is the size (in pixels) of its underlying GL resource.
        buffer.srcRect = NSRect(origin: CGPoint(x: 0, y: 0), size: buffer.size)	//	the "srcRect" of a VVBuffer is the region of the VVBuffer that contains the image you want to work with.  always in "pixels".
        buffer.backingSize = buffer.size	//	the backing size isn't used for this specific example, but it's exactly what it sounds like.
        buffer.backingID = VVBufferBackID(rawValue: 100)!	//	set an arbitrary backing ID.  backing IDs aren't used by VVBufferPool at all- they exist purely for client usage (define your own vals and set them here to determine if a VVBuffer was created with a custom resource from the client)
    }
    
    
    
    // MARK: NSTimer Rendering
    @IBAction func startNSTimer(sender: AnyObject) {
        startNSTimerButton.enabled = false
        startCVDisplayLinkButton.enabled = false
        
        displayTimer = NSTimer.scheduledTimerWithTimeInterval(1 / 60, target: self, selector: "screenRefresh", userInfo: nil, repeats: true)
        player?.play()
    }
    
    func screenRefresh() {
        if cvRenderToTextureAtTime(CACurrentMediaTime()) {
            isfRenderToSyphon()
        }
    }
    
    // render to texture from AVPlayerItemVideoOutput
    func cvRenderToTextureAtTime(time: CFTimeInterval) -> Bool {
        let itemTime = videoOutput.itemTimeForHostTime(time)
        guard videoOutput.hasNewPixelBufferForItemTime(itemTime) else { return false }
        guard let pixelBuffer = videoOutput.copyPixelBufferForItemTime(itemTime, itemTimeForDisplay: nil) else { return false }
        guard let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return false }
        
        let size = NSSize(width: IOSurfaceGetWidth(surface), height: IOSurfaceGetHeight(surface))
        
        context.makeCurrentContext()
        
        glBindTexture(GLenum(GL_TEXTURE_RECTANGLE_EXT), texture)
        CGLTexImageIOSurface2D(context.CGLContextObj, GLenum(GL_TEXTURE_RECTANGLE_EXT), GLenum(GL_RGBA), GLsizei(size.width), GLsizei(size.height), GLenum(GL_BGRA), GLenum(GL_UNSIGNED_INT_8_8_8_8_REV), surface, 0)
        
        return true
    }
    
    
    
    // MARK: CVDisplayLink Rendering
    @IBAction func startCVDisplayLink(sender: AnyObject) {
        startNSTimerButton.enabled = false
        startCVDisplayLinkButton.enabled = false
        
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        CVDisplayLinkSetOutputCallback(displayLink!, { (displayLink, inNow, inOutputTime, flagsIn, flagsOut, displayLinkContext) -> CVReturn in
            // interpret displayLinkContext as this class to call functions
            autoreleasepool {
                unsafeBitCast(displayLinkContext, ViewController.self).screenRefreshForTime(inNow.memory)
//                unsafeBitCast(displayLinkContext, ViewController.self).cvRenderStraightToSyphon(inOutputTime.memory)
            }
            return kCVReturnSuccess
            }, UnsafeMutablePointer<Void>(unsafeAddressOf(self)))
        CVDisplayLinkStart(displayLink!)
        player?.play()
    }
    
    func screenRefreshForTime(timestamp: CVTimeStamp) {
        if cvRenderToTexture(timestamp) {
            isfRenderToSyphon()
        }
    }
    
    // render to texture from AVPlayerItemVideoOutput
    func cvRenderToTexture(timestamp: CVTimeStamp) -> Bool {
        let itemTime = videoOutput.itemTimeForCVTimeStamp(timestamp)
        guard videoOutput.hasNewPixelBufferForItemTime(itemTime) else { return false }
        guard let pixelBuffer = videoOutput.copyPixelBufferForItemTime(itemTime, itemTimeForDisplay: nil) else { return false }
        guard let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return false }
        
        let size = NSSize(width: IOSurfaceGetWidth(surface), height: IOSurfaceGetHeight(surface))
        
        context.makeCurrentContext()
        
        glBindTexture(GLenum(GL_TEXTURE_RECTANGLE_EXT), texture)
        CGLTexImageIOSurface2D(context.CGLContextObj, GLenum(GL_TEXTURE_RECTANGLE_EXT), GLenum(GL_RGBA), GLsizei(size.width), GLsizei(size.height), GLenum(GL_BGRA), GLenum(GL_UNSIGNED_INT_8_8_8_8_REV), surface, 0)
        
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
    
    
    
    // MARK: Alternative CVDisplayLink Rendering Methods
    // render to buffer from AVPlayerItemVideoOutput
    func cvRenderToBuffer(timestamp: CVTimeStamp) -> Bool {
        let itemTime = videoOutput.itemTimeForCVTimeStamp(timestamp)
        guard videoOutput.hasNewPixelBufferForItemTime(itemTime) else { NSLog("no buff"); return false }
        guard let pixelBuffer = videoOutput.copyPixelBufferForItemTime(itemTime, itemTimeForDisplay: nil) else { NSLog("no copy"); return false }
        guard let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { NSLog("surface error"); return false }
        
        let tex = VVBufferPool.globalVVBufferPool().allocBufferForIOSurfaceID(IOSurfaceGetID(surface))
        isfScene.setFilterInputImageBuffer(tex)
        
        return true
    }
    
    // render straight to syphon from AVPlayerItemVideoOutput
    func cvRenderStraightToSyphon(timestamp: CVTimeStamp) -> Bool {
        let itemTime = videoOutput.itemTimeForCVTimeStamp(timestamp)
        guard videoOutput.hasNewPixelBufferForItemTime(itemTime) else { NSLog("no buff"); return false }
        guard let pixelBuffer = videoOutput.copyPixelBufferForItemTime(itemTime, itemTimeForDisplay: nil) else { NSLog("no copy"); return false }
        guard let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { NSLog("surface error"); return false }
        
        let size = NSSize(width: IOSurfaceGetWidth(surface), height: IOSurfaceGetHeight(surface))
        
        context.makeCurrentContext()
        
        glBindTexture(GLenum(GL_TEXTURE_RECTANGLE_EXT), texture)
        CGLTexImageIOSurface2D(context.CGLContextObj, GLenum(GL_TEXTURE_RECTANGLE_EXT), GLenum(GL_RGBA), GLsizei(size.width), GLsizei(size.height), GLenum(GL_BGRA), GLenum(GL_UNSIGNED_INT_8_8_8_8_REV), surface, 0)
        
        syphonServer?.publishFrameTexture(texture, textureTarget: GLenum(GL_TEXTURE_RECTANGLE_EXT), imageRegion: NSRect(origin: CGPoint(x: 0, y: 0), size: sceneSize), textureDimensions: sceneSize, flipped: true)
        
        return true
    }
    
}