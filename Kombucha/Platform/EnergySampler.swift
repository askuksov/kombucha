import Darwin
import KombuchaCore

/// Cumulative energy of every process macOS lets this user read (`ri_energy_nj`). Root's and other users'
/// processes refuse and are left out; about a third of the pids on a typical Mac.
struct EnergySampler {
    func sample() -> EnergyReading {
        var samples: [EnergySample] = []
        // PROC_PIDPATHINFO_MAXSIZE is 4 * MAXPATHLEN; Swift does not import the macro.
        var path = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in ProcessScanner.allPids() where pid > 0 {
            var usage = rusage_info_v6()
            let status = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
                }
            }
            guard status == 0 else { continue }
            let length = path.withUnsafeMutableBytes { buffer in
                proc_pidpath(pid, buffer.baseAddress, UInt32(buffer.count))
            }
            guard length > 0 else { continue }
            samples.append(EnergySample(pid: pid,
                                        executablePath: String(decoding: path[..<Int(length)], as: UTF8.self),
                                        energyNanojoules: usage.ri_energy_nj))
        }
        // Taken after the scan, so the interval between two readings is the one the counters really span.
        let seconds = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9
        return EnergyReading(samples: samples, seconds: seconds)
    }
}
