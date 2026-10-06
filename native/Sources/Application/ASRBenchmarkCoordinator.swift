import Foundation

final class ASRBenchmarkCoordinator: @unchecked Sendable {
    enum State: Equatable { case empty, ready(sampleID:String), running(ASRCandidateID), completed(ASRCandidateID), failed(ASRCandidateID,String), cancelled }
    private struct Sample { let id:String;let url:URL;let duration:Double }
    private let runner:LocalASRRunning
    private let persist:(ASRBenchmarkResult)throws->Void
    private let queue=DispatchQueue(label:"com.waykingah.typewhale.asr-benchmark-session",qos:.userInitiated)
    private let lock=NSLock();private var sample:Sample?;private var generation=UUID()
    private(set)var state:State = .empty
    var onStateChange:((State)->Void)?

    init(runner:LocalASRRunning,persist:@escaping(ASRBenchmarkResult)throws->Void){self.runner=runner;self.persist=persist}
    func setSample(id:String,url:URL,duration:Double){lock.lock();generation=UUID();sample = .init(id:id,url:url,duration:duration);state = .ready(sampleID:id);let value=state;lock.unlock();onStateChange?(value)}
    func run(candidate:ASRModelDescriptor,hotwords:[String],completion:@escaping(Result<ASRBenchmarkResult,Error>)->Void){
        lock.lock();guard let sample else{lock.unlock();completion(.failure(error("请先录制或导入测试音频")));return};let token=generation;state = .running(candidate.id);let value=state;lock.unlock();onStateChange?(value)
        queue.async{[weak self] in guard let self else{return}
            self.runner.transcribe(candidate:candidate,audioURL:sample.url,hotwords:hotwords){first in
                switch first{case .failure(let e):self.finishFailure(candidate.id,error:e,token:token,completion:completion);case .success(let cold):
                    self.runner.transcribe(candidate:candidate,audioURL:sample.url,hotwords:hotwords){warm in
                        switch warm{case .failure(let e):self.finishFailure(candidate.id,error:e,token:token,completion:completion);case .success(let hot):
                            let result=ASRBenchmarkResult(id:UUID(),sampleID:sample.id,candidateID:candidate.id,hotwordSnapshot:hotwords,text:hot.text,coldLoadSeconds:cold.loadSeconds,firstInferenceSeconds:cold.inferenceSeconds,warmInferenceSeconds:hot.inferenceSeconds,audioDurationSeconds:sample.duration,peakRSSMB:max(cold.peakRSSMB,hot.peakRSSMB),createdAt:Date())
                            self.runner.unload{do{guard self.isCurrent(token)else{completion(.failure(self.error("测速已取消")));return};try self.persist(result);self.update(.completed(candidate.id));completion(.success(result))}catch{self.update(.failed(candidate.id,error.localizedDescription));completion(.failure(error))}}
                        }
                    }
                }
            }
        }
    }
    func cancel(){lock.lock();generation=UUID();state = .cancelled;let value=state;lock.unlock();runner.unload{};onStateChange?(value)}
    private func finishFailure(_ id:ASRCandidateID,error:Error,token:UUID,completion:@escaping(Result<ASRBenchmarkResult,Error>)->Void){runner.unload{};if isCurrent(token){update(.failed(id,error.localizedDescription))};completion(.failure(error))}
    private func isCurrent(_ token:UUID)->Bool{lock.lock();defer{lock.unlock()};return generation==token}
    private func update(_ value:State){lock.lock();state=value;lock.unlock();onStateChange?(value)}
    private func error(_ message:String)->NSError{NSError(domain:"com.waykingah.typewhale.asr-benchmark",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
}
