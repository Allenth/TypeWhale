import AppKit
import AVFAudio
import Foundation
import UniformTypeIdentifiers

final class ASRBenchmarkViewController:NSViewController {
    private let coordinator:ASRBenchmarkCoordinator, descriptors:[ASRModelDescriptor],rootURL:URL
    private lazy var recorder=AudioRecorder(outputURLProvider:{[rootURL] in rootURL.appendingPathComponent("sample-\(UUID().uuidString).wav")})
    private let sampleStatus=NSTextField(labelWithString:"请录制或导入一段固定测试音频")
    let temporaryHotwords=NSTextField(string:"")
    private let rows=NSStackView();private var results:[ASRCandidateID:ASRBenchmarkResult]=[:];private var rowViews:[ASRCandidateID:NSView]=[:]
    private var currentSample:URL?;private var sound:NSSound?
    var onClear:(()->Void)?
    init(coordinator:ASRBenchmarkCoordinator,descriptors:[ASRModelDescriptor],rootURL:URL){self.coordinator=coordinator;self.descriptors=descriptors;self.rootURL=rootURL;super.init(nibName:nil,bundle:nil)}
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override func loadView(){
        let root=NSView();root.translatesAutoresizingMaskIntoConstraints=false
        let record=button("录制",#selector(recordOrStop));let importButton=button("导入音频",#selector(importAudio));let play=button("播放",#selector(playSample));let all=button("测试全部",#selector(runAll));let cancel=button("取消",#selector(cancelBenchmark));let clear=button("清除结果",#selector(clearResults))
        temporaryHotwords.placeholderString="临时热词，用逗号或换行分隔（仅本次测速）";temporaryHotwords.setAccessibilityLabel("测速临时热词")
        let controls=NSStackView(views:[record,importButton,play,all,cancel,clear]);controls.orientation = .horizontal;controls.spacing=8
        rows.orientation = .vertical;rows.alignment = .leading;rows.spacing=8
        let scroll=NSScrollView();scroll.documentView=rows;scroll.hasVerticalScroller=true;scroll.drawsBackground=false
        let stack=NSStackView(views:[sampleStatus,controls,temporaryHotwords,scroll]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=10;stack.translatesAutoresizingMaskIntoConstraints=false
        root.addSubview(stack);NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:18),stack.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-18),stack.topAnchor.constraint(equalTo:root.topAnchor,constant:18),stack.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-18),controls.widthAnchor.constraint(equalTo:stack.widthAnchor),temporaryHotwords.widthAnchor.constraint(equalTo:stack.widthAnchor),scroll.widthAnchor.constraint(equalTo:stack.widthAnchor),scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:420),rows.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor)])
        view=root;rebuildRows(running:nil)
    }
    private func button(_ title:String,_ action:Selector)->NSButton{let b=NSButton(title:title,target:self,action:action);b.bezelStyle = .rounded;return b}
    private func rebuildRows(running:ASRCandidateID?){rows.arrangedSubviews.forEach{$0.removeFromSuperview()};rowViews.removeAll();for (index,d) in descriptors.enumerated(){let p=ASRBenchmarkRowPresentation(descriptor:d,result:results[d.id],isRunning:running==d.id);let title=NSTextField(labelWithString:p.title);title.font = .systemFont(ofSize:13,weight:.semibold);let meta=NSTextField(labelWithString:"\(p.readinessText) · \(p.hotwordBadge) · \(p.timingText)");meta.font = .systemFont(ofSize:11);meta.textColor = .secondaryLabelColor;let output=NSTextField(wrappingLabelWithString:p.resultText);output.maximumNumberOfLines=2;let run=button("测试",#selector(runOne(_:)));run.tag=index;run.isEnabled=p.canRun;let ab=button("热词 A/B",#selector(runAB(_:)));ab.tag=index;ab.isEnabled=p.canRun && d.hotwordStrategy != .unsupported;let actions=NSStackView(views:[run,ab]);actions.orientation = .horizontal;let text=NSStackView(views:[title,meta,output]);text.orientation = .vertical;text.alignment = .leading;text.spacing=3;let row=NSStackView(views:[text,NSView(),actions]);row.orientation = .horizontal;row.alignment = .centerY;row.spacing=10;row.wantsLayer=true;row.layer?.cornerRadius=8;row.layer?.borderWidth=1;row.layer?.borderColor=NSColor.separatorColor.cgColor;row.edgeInsets=NSEdgeInsets(top:9,left:10,bottom:9,right:10);row.widthAnchor.constraint(equalTo:rows.widthAnchor).isActive=true;text.setContentHuggingPriority(.defaultLow,for:.horizontal);rows.addArrangedSubview(row);rowViews[d.id]=row}}
    private var words:[String]{temporaryHotwords.stringValue.components(separatedBy:CharacterSet(charactersIn:",，\n")).map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}.filter{!$0.isEmpty}}
    @objc func recordOrStop(_ sender:NSButton){do{if recorder.isRecording{if let (url,duration)=try recorder.stop(){acceptSample(url,duration:duration)};sender.title="录制"}else{try FileManager.default.createDirectory(at:rootURL,withIntermediateDirectories:true);try recorder.start(taskID:UUID(),realtimeEnabled:false,inputDeviceID:nil);sender.title="停止录制";sampleStatus.stringValue="正在录制测试音频…"}}catch{sampleStatus.stringValue=error.localizedDescription}}
    @objc func importAudio(){let panel=NSOpenPanel();panel.allowedContentTypes=[.audio];panel.allowsMultipleSelection=false;guard panel.runModal() == .OK,let source=panel.url else{return};let target=rootURL.appendingPathComponent("import-\(UUID().uuidString).wav");do{try FileManager.default.createDirectory(at:rootURL,withIntermediateDirectories:true);let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/afconvert");p.arguments=[source.path,"-f","WAVE","-d","LEF32@16000","-c","1",target.path];try p.run();p.waitUntilExit();guard p.terminationStatus == 0 else{throw NSError(domain:"ASRBenchmark",code:1,userInfo:[NSLocalizedDescriptionKey:"音频转换失败"])};let audio=try AVAudioFile(forReading:target);acceptSample(target,duration:Double(audio.length)/audio.fileFormat.sampleRate)}catch{sampleStatus.stringValue=error.localizedDescription}}
    private func acceptSample(_ url:URL,duration:Double){currentSample=url;coordinator.setSample(id:url.deletingPathExtension().lastPathComponent,url:url,duration:duration);sampleStatus.stringValue=String(format:"测试音频 %.1f 秒 · %@",duration,url.lastPathComponent)}
    @objc func playSample(){guard let url=currentSample else{return};sound=NSSound(contentsOf:url,byReference:true);sound?.play()}
    @objc func runOne(_ sender:NSButton){run(descriptors[sender.tag],hotwords:words,completion:{})}
    @objc func runAB(_ sender:NSButton){let d=descriptors[sender.tag];run(d,hotwords:[]){[weak self] in guard let self else{return};self.run(d,hotwords:self.words,completion:{})}}
    private func run(_ d:ASRModelDescriptor,hotwords:[String],completion:@escaping()->Void){rebuildRows(running:d.id);coordinator.run(candidate:d,hotwords:hotwords){[weak self] (result:Result<ASRBenchmarkResult,Error>) in DispatchQueue.main.async { guard let self else{return};if case .success(let value)=result{self.results[d.id]=value}else if case .failure(let error)=result{self.sampleStatus.stringValue=error.localizedDescription};self.rebuildRows(running:nil);completion() }}}
    @objc func runAll(){runSequential(Array(descriptors.filter{$0.readiness == .ready}))}
    private func runSequential(_ remaining:[ASRModelDescriptor]){guard let first=remaining.first else{return};run(first,hotwords:words){[weak self] in self?.runSequential(Array(remaining.dropFirst()))}}
    @objc func cancelBenchmark(){coordinator.cancel();rebuildRows(running:nil);sampleStatus.stringValue="已取消测速"}
    @objc func clearResults(){results.removeAll();currentSample=nil;onClear?();rebuildRows(running:nil);sampleStatus.stringValue="结果已清除"}
}
