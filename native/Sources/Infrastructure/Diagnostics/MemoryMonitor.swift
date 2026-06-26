import Foundation

/// 读取本进程真实物理内存占用（macOS 的 phys_footprint，与活动监视器“内存”列一致），
/// 用于主界面与状态栏的内存监测显示与超限提醒。
/// 说明：ASR / VAD 模型平时保持热加载，保证下一句语音输入不承担重载延迟。
/// 这里记录并展示“当前 · 峰值”，避免只看当前值时误判长期运行状态。
enum MemoryMonitor {
    /// 动态预警阈值下限：低内存机器至少到 2GB 才触发，避免回到 1GB 附近反复 flush/reload。
    static let minimumWarnThresholdMB = 2 * 1024
    /// 动态预警阈值上限：高内存机器最多按 20GB 触发，作为异常兜底硬上限。
    static let maximumWarnThresholdMB = 20 * 1024
    private static let maximumHighThresholdMB = 24 * 1024

    /// 本机物理内存（MB）。
    static var totalPhysicalMemoryMB: Int {
        Int(ProcessInfo.processInfo.physicalMemory / UInt64(1024 * 1024))
    }

    /// 预警阈值（MB）：min(20GB, max(2GB, 本机物理内存 * 25%))。
    static var warnThresholdMB: Int {
        min(maximumWarnThresholdMB, max(minimumWarnThresholdMB, totalPhysicalMemoryMB / 4))
    }

    /// 高占用阈值（MB）：跟随动态预警阈值上浮约 20%，最高不超过 24GB。
    static var highThresholdMB: Int {
        min(maximumHighThresholdMB, max(warnThresholdMB + 512, Int(Double(warnThresholdMB) * 1.2)))
    }

    enum Level {
        case normal
        case warn
        case high
    }

    private static var peakMB = 0

    /// 当前进程物理内存占用（字节）。失败返回 0。
    static func currentFootprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return info.phys_footprint
    }

    /// 读取当前占用（MB），同时更新本会话峰值。
    static var currentFootprintMB: Int {
        let megabytes = Int(currentFootprintBytes() / (1024 * 1024))
        if megabytes > peakMB { peakMB = megabytes }
        return megabytes
    }

    /// 本会话观测到的峰值（MB）。启动后随采样更新。
    static var peakFootprintMB: Int { peakMB }

    static func level(forMB megabytes: Int) -> Level {
        if megabytes >= highThresholdMB { return .high }
        if megabytes >= warnThresholdMB { return .warn }
        return .normal
    }
}
