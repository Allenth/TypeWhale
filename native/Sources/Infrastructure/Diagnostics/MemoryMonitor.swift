import Foundation

/// 读取本进程真实物理内存占用（macOS 的 phys_footprint，与活动监视器“内存”列一致），
/// 用于主界面与状态栏的内存监测显示与超限提醒。
/// 说明：模型在不录音时会被卸载，空闲态约 100MB；录音时模型载入会涨到数百 MB，
/// 因此同时记录并展示“当前 · 峰值”，避免只看当前值时误以为占用很低。
enum MemoryMonitor {
    /// 预警阈值（MB）：超过即在界面上标橙并提醒。按用户要求设为 1GB。
    static let warnThresholdMB = 1024
    /// 高占用阈值（MB）：超过即标红。
    static let highThresholdMB = 1536

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
