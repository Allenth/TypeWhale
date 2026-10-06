import Foundation

private func checkPostRollMustBeAvailable() {
    let planner = RealtimeBoundaryCorrectionPlanner(
        preRollSeconds: 4,
        postRollSeconds: 4
    )
    let plan = planner.plan(
        boundaryTime: 18,
        availableAudioStart: 10,
        availableAudioEnd: 21.9,
        kind: .conflictRecovery
    )
    precondition(plan == nil, "boundary correction must wait until post-roll audio is available")
}

private func checkFullWindowWhenAvailable() {
    let planner = RealtimeBoundaryCorrectionPlanner(
        preRollSeconds: 4,
        postRollSeconds: 4
    )
    let plan = planner.plan(
        boundaryTime: 18,
        availableAudioStart: 10,
        availableAudioEnd: 24,
        kind: .hardLimit
    )
    precondition(plan == RealtimeBoundaryCorrectionPlan(
        boundaryTime: 18,
        audioStartTime: 14,
        audioEndTime: 22,
        kind: .hardLimit
    ))
}

private func checkStartClampsToAvailableAudio() {
    let planner = RealtimeBoundaryCorrectionPlanner(
        preRollSeconds: 4,
        postRollSeconds: 4
    )
    let plan = planner.plan(
        boundaryTime: 3,
        availableAudioStart: 0,
        availableAudioEnd: 8,
        kind: .voicePause
    )
    precondition(plan == RealtimeBoundaryCorrectionPlan(
        boundaryTime: 3,
        audioStartTime: 0,
        audioEndTime: 7,
        kind: .voicePause
    ))
}

checkPostRollMustBeAvailable()
checkFullWindowWhenAvailable()
checkStartClampsToAvailableAudio()

print("RealtimeBoundaryCorrectionPlannerCheck passed")
