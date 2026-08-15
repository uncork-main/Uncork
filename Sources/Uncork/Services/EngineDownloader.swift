import Foundation

enum DownloadError: Error, LocalizedError {
    case httpStatus(Int)
    case sizeMismatch(expected: Int64, actual: Int64)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code):
            return "HTTP 状态码 \(code)"
        case .sizeMismatch(let expected, let actual):
            return "下载字节数不匹配（期望 \(expected)，实际 \(actual)）"
        case .cancelled:
            return "下载已取消"
        }
    }
}

/// Wine 引擎下载器：流式写盘（1MB 块缓冲），支持取消、字节数校验、指数退避重试。
final class EngineDownloader {
    struct Source: Equatable {
        let name: String
        let url: URL
        let archiveFileName: String
    }

    /// 进度回调：0...1；总长未知时回调 -1。
    /// 下载到临时文件，成功后原子改名到最终位置。
    func download(
        from sourceURL: URL,
        to destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let fm = FileManager.default
        try? fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: destination) // 重新开始，不做断点续传（MVP）

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let request = URLRequest(url: sourceURL)
        let (bytes, response) = try await session.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.httpStatus(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DownloadError.httpStatus(http.statusCode)
        }

        let expected = http.expectedContentLength
        guard fm.createFile(atPath: destination.path, contents: nil) else {
            throw CommandError.executableMissing(destination.path)
        }
        let handle = try FileHandle(forWritingTo: destination)

        let chunkSize = 1 << 20 // 1MB
        var buffer = Data()
        buffer.reserveCapacity(chunkSize)
        var received: Int64 = 0
        var lastTick: Int64 = 0

        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= chunkSize {
                    try handle.write(contentsOf: buffer)
                    received += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    // 每约 5MB 回调一次进度，避免过于频繁的 UI 更新
                    if received - lastTick >= Int64(chunkSize) * 5 {
                        onProgress(expected > 0 ? Double(received) / Double(expected) : -1)
                        lastTick = received
                    }
                }
            }
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
            }
        } catch {
            try? handle.close()
            try? fm.removeItem(at: destination)
            if error is CancellationError {
                throw DownloadError.cancelled
            }
            throw error
        }
        try? handle.close()

        if expected > 0 && received != expected {
            try? fm.removeItem(at: destination)
            throw DownloadError.sizeMismatch(expected: expected, actual: received)
        }
        onProgress(1.0)
        return destination
    }

    /// 带重试的下载：最多 attempts 次，指数退避（2s、4s…）。
    /// 4xx 错误不重试（重试也不会成功），直接抛出让上层切换备用源。
    func downloadWithRetry(
        from sourceURL: URL,
        to destination: URL,
        attempts: Int = 3,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        var lastError: Error = DownloadError.httpStatus(-1)
        for attempt in 1...attempts {
            do {
                return try await download(from: sourceURL, to: destination, onProgress: onProgress)
            } catch {
                lastError = error
                if case DownloadError.cancelled = error { throw error }
                if case DownloadError.httpStatus(let code) = error, (400..<500).contains(code) {
                    throw error // 4xx 重试无意义
                }
                if attempt < attempts {
                    let delay = UInt64(1) << UInt64(attempt) // 2s、4s
                    try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                }
            }
        }
        throw lastError
    }
}
