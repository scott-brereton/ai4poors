// ForegroundAppDetector.swift
// Ai4Poors - Detect the frontmost iOS app using private APIs
//
// Uses SpringBoardServices (SBSCopyFrontmostApplicationDisplayIdentifier)
// and LSApplicationWorkspace for app name resolution.
// These are private APIs — works on sideloaded builds only.
// Falls back gracefully to nil if the APIs are unavailable.

import Foundation

enum ForegroundAppDetector {

    /// Attempt to get the bundle ID of the frontmost app.
    /// Returns nil if detection fails (restricted sandbox, API unavailable, etc.)
    static func frontmostAppBundleID() -> String? {
        // Approach 1: SBSCopyFrontmostApplicationDisplayIdentifier
        if let bundleID = sbsCopyFrontmost() {
            return bundleID
        }

        // Approach 2: SBFrontmostApplicationDisplayIdentifier (older API)
        if let bundleID = sbsFrontmostViaPort() {
            return bundleID
        }

        return nil
    }

    /// Get the localized display name for a bundle ID via LSApplicationWorkspace.
    static func appName(for bundleID: String) -> String? {
        guard let cls = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type else { return nil }
        let defaultWSSel = NSSelectorFromString("defaultWorkspace")
        guard cls.responds(to: defaultWSSel) else { return nil }
        guard let workspace = cls.perform(defaultWSSel)?.takeUnretainedValue() as? NSObject else { return nil }

        let proxySel = NSSelectorFromString("applicationProxyForIdentifier:")
        guard workspace.responds(to: proxySel) else { return nil }
        guard let proxy = workspace.perform(proxySel, with: bundleID)?.takeUnretainedValue() as? NSObject else { return nil }

        let nameSel = NSSelectorFromString("localizedName")
        guard proxy.responds(to: nameSel) else { return nil }
        guard let name = proxy.perform(nameSel)?.takeUnretainedValue() as? String else { return nil }

        return name
    }

    /// Detect frontmost app and resolve its display name in one call.
    static func currentApp() -> (bundleID: String, name: String?)? {
        guard let bundleID = frontmostAppBundleID() else { return nil }
        let name = appName(for: bundleID)
        return (bundleID, name)
    }

    // MARK: - Cached Framework Handle

    /// Cache the dlopen handle — loading/unloading on every 10s call is wasteful.
    /// The handle is never closed; it lives for the process lifetime.
    private static let sbsHandle: UnsafeMutableRawPointer? = {
        let path = "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices"
        return dlopen(path, RTLD_LAZY)
    }()

    // MARK: - Private API Wrappers

    /// SBSCopyFrontmostApplicationDisplayIdentifier — newer, single-arg API
    private static func sbsCopyFrontmost() -> String? {
        guard let handle = sbsHandle else { return nil }

        guard let sym = dlsym(handle, "SBSCopyFrontmostApplicationDisplayIdentifier") else { return nil }

        typealias Func = @convention(c) (UnsafeMutablePointer<Unmanaged<CFString>?>) -> Int32
        let fn = unsafeBitCast(sym, to: Func.self)

        var result: Unmanaged<CFString>?
        let status = fn(&result)

        guard status == 0, let cfStr = result?.takeRetainedValue() else { return nil }
        let bundleID = cfStr as String
        return bundleID.isEmpty ? nil : bundleID
    }

    /// SBFrontmostApplicationDisplayIdentifier — older, port-based API
    private static func sbsFrontmostViaPort() -> String? {
        guard let handle = sbsHandle else { return nil }

        // Get SpringBoard mach port
        guard let portSym = dlsym(handle, "SBSSpringBoardServerPort") else { return nil }
        typealias PortFunc = @convention(c) () -> mach_port_t
        let getPort = unsafeBitCast(portSym, to: PortFunc.self)
        let port = getPort()
        guard port != 0 else { return nil }

        // Get frontmost app identifier
        guard let frontSym = dlsym(handle, "SBFrontmostApplicationDisplayIdentifier") else { return nil }
        typealias FrontFunc = @convention(c) (mach_port_t, UnsafeMutablePointer<CChar>) -> Void
        let getFront = unsafeBitCast(frontSym, to: FrontFunc.self)

        var buffer = [CChar](repeating: 0, count: 256)
        getFront(port, &buffer)

        let bundleID = String(cString: buffer)
        return bundleID.isEmpty ? nil : bundleID
    }
}
