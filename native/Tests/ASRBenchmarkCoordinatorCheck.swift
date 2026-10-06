import Foundation
private final class FakeRunner:LocalASRRunning {
    var events:[String]=[]; var calls=0
    func probe(_ d:ASRModelDescriptor)->ASRReadiness{d.readiness}
    func warmUp(candidate:ASRModelDescriptor,hotwords:[String],completion:@escaping(Result<Double,Error>)->Void){completion(.success(0))}
    func transcribe(candidate:ASRModelDescriptor,audioURL:URL,hotwords:[String],completion:@escaping(Result<ASREngineResult,Error>)->Void){calls += 1;events.append("run:\(candidate.id.rawValue)");completion(.success(.init(text:"TypeWhale 结果",engine:"fake",loadSeconds:calls==1 ? 1:0,inferenceSeconds:calls==1 ? 2:0.5,peakRSSMB:123)))}
    func cancel(runID:UUID){}
    func unload(completion:@escaping()->Void){events.append("unload");completion()}
}
@main struct ASRBenchmarkCoordinatorCheck {
    static func main(){let runner=FakeRunner();let descriptor=ASRModelDescriptor(id:.senseVoiceInt8,displayName:"Sense",engine:.sherpa,modelDirectory:URL(fileURLWithPath:"/tmp"),requiredRelativePaths:[],hotwordStrategy:.unsupported,readiness:.ready,productionReady:true);let coordinator=ASRBenchmarkCoordinator(runner:runner,persist:{_ in});coordinator.setSample(id:"s",url:URL(fileURLWithPath:"/tmp/a.wav"),duration:2);let s=DispatchSemaphore(value:0);coordinator.run(candidate:descriptor,hotwords:["TypeWhale"]){result in guard case .success(let value)=result else{preconditionFailure("\(result)")};precondition(value.coldLoadSeconds==1 && value.firstInferenceSeconds==2 && value.warmInferenceSeconds==0.5 && value.realTimeFactor==0.25);s.signal()};precondition(s.wait(timeout:.now()+2) == .success);precondition(runner.events==["run:sensevoice-int8","run:sensevoice-int8","unload"]);print("ASRBenchmarkCoordinatorCheck passed")}
}
