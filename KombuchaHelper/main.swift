import Foundation
import HelperCore
import HelperProtocol
import SMCKit
import os

let startupLog = Logger(subsystem: HelperIdentity.machServiceName, category: "startup")

guard let executablePath = Bundle.main.executablePath else {
    startupLog.error("my executable path is unknown")
    exit(EX_SOFTWARE)
}
// First, while the file on disk is the code that runs.
let identity = CodeIdentity(executablePath: executablePath)

if !identity.knowsStartupCode {
    startupLog.error("cannot read my own code identity: I will retire at the first connection")
}

guard
    let requirementText = Bundle.main.object(forInfoDictionaryKey: HelperIdentity.clientRequirementKey) as? String,
    CallerVerifier.compile(requirementText) != nil
else {
    startupLog.error("the client requirement is missing or does not compile")
    exit(EX_SOFTWARE)
}

let chargeSwitch: ChargeSwitch
do {
    chargeSwitch = try ChargeSwitch.arm()
    startupLog.info("armed")
} catch {
    startupLog.error("not armed: \(String(describing: error), privacy: .public)")
    exit(EX_UNAVAILABLE)
}

// A Mac without the adapter key keeps limiting the charge; setAdapter answers failed there.
let adapterSwitch: AdapterSwitch?
do {
    adapterSwitch = try AdapterSwitch.arm()
    startupLog.info("adapter switch armed")
} catch {
    startupLog.notice("adapter switch not armed: \(String(describing: error), privacy: .public)")
    adapterSwitch = nil
}

let service = HelperService(writer: chargeSwitch, adapter: adapterSwitch)
// Before the first client: an adapter left off by a crash, a kill or a restart goes back on.
service.restoreAdapterAtStart()

guard let delegate = ListenerDelegate(requirementText: requirementText, identity: identity, service: service) else {
    startupLog.error("the client requirement does not compile")
    exit(EX_SOFTWARE)
}

let watch: ExecutableWatch?
do throws(ExecutableWatch.OpenFailure) {
    watch = try ExecutableWatch(path: executablePath, queue: DispatchQueue(label: "\(HelperIdentity.machServiceName).watch")) { [service] in
        service.retire(because: "my executable changed")
    }
} catch {
    startupLog.error("cannot watch my executable: \(error.reason, privacy: .public)")
    watch = nil
}

let sleepWatch = SleepWatch(queue: DispatchQueue(label: "\(HelperIdentity.machServiceName).sleep"),
                            onWillSleep: { [service] in service.systemWillSleep() },
                            onWake: { [service] in service.systemDidWake() })
if !sleepWatch.start() {
    startupLog.error("cannot watch system sleep")
}

// launchd sends SIGTERM when the job is removed or the Mac shuts down.
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler { [service] in
    service.stop(because: "launchd asked me to stop")
}
termination.resume()

let listener = NSXPCListener(machServiceName: HelperIdentity.machServiceName)
listener.delegate = delegate
listener.resume()
// NSXPCListener holds its delegate weakly, and the watches and the signal source fire only while they live.
withExtendedLifetime((delegate, watch, sleepWatch, termination)) { dispatchMain() }
