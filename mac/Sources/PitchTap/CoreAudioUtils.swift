import CoreAudio
import Foundation

struct CoreAudioError: LocalizedError {
    let status: OSStatus
    let action: String

    var errorDescription: String? {
        let code = UInt32(bitPattern: status)
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        let fourCC = bytes.allSatisfy { $0 >= 32 && $0 < 127 } ? " '\(String(decoding: bytes, as: UTF8.self))'" : ""
        return "Couldn't \(action) (error \(status)\(fourCC))"
    }
}

func check(_ status: OSStatus, _ action: String) throws {
    guard status == noErr else { throw CoreAudioError(status: status, action: action) }
}

enum CA {
    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, initial: T) throws -> T {
        var addr = address(selector, scope: scope)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        try withUnsafeMutablePointer(to: &value) {
            try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0), "read audio property")
        }
        return value
    }

    static func readArray<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, of _: T.Type,
                             initial: T) throws -> [T] {
        var addr = address(selector)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size), "read audio property size")
        let count = Int(size) / MemoryLayout<T>.stride
        guard count > 0 else { return [] }
        var values = [T](repeating: initial, count: count)
        try values.withUnsafeMutableBufferPointer {
            try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0.baseAddress!), "read audio property list")
        }
        return Array(values.prefix(Int(size) / MemoryLayout<T>.stride))
    }

    static func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var addr = address(selector)
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try withUnsafeMutablePointer(to: &ref) {
            try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0), "read audio string")
        }
        guard let ref else { throw CoreAudioError(status: kAudioHardwareUnspecifiedError, action: "read audio string") }
        return ref.takeRetainedValue() as String
    }

    static func defaultOutputDevice() throws -> AudioDeviceID {
        try read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
                 initial: AudioDeviceID(kAudioObjectUnknown))
    }
}
