import AppKit
final class ASRBenchmarkWindowController:NSWindowController {
    init(content:ASRBenchmarkViewController){let window=NSWindow(contentRect:NSRect(x:0,y:0,width:920,height:680),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false);window.title="ASR 模型测速";window.contentViewController=content;window.center();window.setFrameAutosaveName("ASRBenchmarkWindow");super.init(window:window)}
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
}
