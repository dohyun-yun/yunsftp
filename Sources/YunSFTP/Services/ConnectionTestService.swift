import Foundation
import Network

public struct ConnectionTestResult: Sendable {
    public let isSuccess: Bool
    public let resolvedIP: String?
    public let latencyMs: Double
    public let serverBanner: String?
    public let message: String
}

private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func testAndSet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if !flag {
            flag = true
            return true
        }
        return false
    }
}

public actor ConnectionTestService {
    public static let shared = ConnectionTestService()

    public func testConnection(host: String, port: Int, isSSH: Bool = true, timeoutSeconds: Double = 5.0) async -> ConnectionTestResult {
        guard !host.isEmpty, port > 0 && port <= 65535 else {
            return ConnectionTestResult(
                isSuccess: false,
                resolvedIP: nil,
                latencyMs: 0,
                serverBanner: nil,
                message: "Invalid host or port number"
            )
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // 1. Resolve host
        let hostEndpoint = NWEndpoint.Host(host)
        guard let portEndpoint = NWEndpoint.Port(rawValue: UInt16(port)) else {
            return ConnectionTestResult(
                isSuccess: false,
                resolvedIP: nil,
                latencyMs: 0,
                serverBanner: nil,
                message: "Invalid port number"
            )
        }

        let connection = NWConnection(host: hostEndpoint, port: portEndpoint, using: .tcp)
        let queue = DispatchQueue(label: "com.finsternis.yunsftp.connection-test")

        return await withCheckedContinuation { continuation in
            let resumedFlag = AtomicFlag()

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + timeoutSeconds)
            timer.setEventHandler {
                if resumedFlag.testAndSet() {
                    connection.cancel()
                    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
                    continuation.resume(returning: ConnectionTestResult(
                        isSuccess: false,
                        resolvedIP: nil,
                        latencyMs: elapsed,
                        serverBanner: nil,
                        message: "Connection timed out after \(Int(timeoutSeconds)) seconds."
                    ))
                }
            }
            timer.resume()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
                    let resolvedIP: String? = {
                        if let endpoint = connection.currentPath?.remoteEndpoint,
                           case let .hostPort(remoteHost, _) = endpoint {
                            return remoteHost.debugDescription
                        }
                        return nil
                    }()

                    if isSSH {
                        // Read initial SSH banner
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 256) { data, _, _, _ in
                            timer.cancel()
                            connection.cancel()
                            if resumedFlag.testAndSet() {
                                var banner: String? = nil
                                if let d = data, let str = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                                    banner = str.components(separatedBy: .newlines).first
                                }

                                let msg = banner != nil ?
                                    "Connected successfully! Server: \(banner!)" :
                                    "TCP port \(String(port)) is open and reachable."

                                continuation.resume(returning: ConnectionTestResult(
                                    isSuccess: true,
                                    resolvedIP: resolvedIP,
                                    latencyMs: elapsed,
                                    serverBanner: banner,
                                    message: msg
                                ))
                            }
                        }
                    } else {
                        timer.cancel()
                        connection.cancel()
                        if resumedFlag.testAndSet() {
                            continuation.resume(returning: ConnectionTestResult(
                                isSuccess: true,
                                resolvedIP: resolvedIP,
                                latencyMs: elapsed,
                                serverBanner: nil,
                                message: "TCP port \(String(port)) is open and reachable."
                            ))
                        }
                    }

                case .failed(let error):
                    timer.cancel()
                    connection.cancel()
                    if resumedFlag.testAndSet() {
                        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
                        let errorMsg: String
                        switch error {
                        case .posix(let code):
                            if code == .ECONNREFUSED {
                                errorMsg = "Connection refused on port \(String(port)). Server is not accepting connections."
                            } else if code == .ENETUNREACH || code == .EHOSTUNREACH {
                                errorMsg = "Host unreachable. Please check network connection."
                            } else {
                                errorMsg = error.localizedDescription
                            }
                        case .dns(let code):
                            errorMsg = "DNS lookup failed (code: \(code)). Host could not be resolved."
                        default:
                            errorMsg = error.localizedDescription
                        }

                        continuation.resume(returning: ConnectionTestResult(
                            isSuccess: false,
                            resolvedIP: nil,
                            latencyMs: elapsed,
                            serverBanner: nil,
                            message: errorMsg
                        ))
                    }

                case .cancelled:
                    break

                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }
}
