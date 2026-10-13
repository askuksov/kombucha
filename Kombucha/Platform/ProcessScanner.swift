import Darwin

/// Every running executable's path, root's included.
struct ProcessScanner: ProcessListing {
    /// Every pid, kernel and other users' included.
    static func allPids() -> [pid_t] {
        // proc_listallpids counts pids, although its size argument is in bytes.
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let found = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard found > 0 else { return [] }
        return Array(pids.prefix(min(Int(found), pids.count)))
    }

    func executablePaths() -> [String] {
        // PROC_PIDPATHINFO_MAXSIZE is 4 * MAXPATHLEN; Swift does not import the macro.
        var path = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return Self.allPids().compactMap { pid in
            let length = path.withUnsafeMutableBytes { buffer in
                proc_pidpath(pid, buffer.baseAddress, UInt32(buffer.count))
            }
            return length > 0 ? String(decoding: path[..<Int(length)], as: UTF8.self) : nil
        }
    }
}
