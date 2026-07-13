import Carbon.HIToolbox
import Foundation

// RegisterEventHotKey によるグローバルホットキー。
// EventTap と異なり Input Monitoring 権限が不要。
// ID(文字列)単位で登録し、ハンドラを保ったままキーの差し替えができる。
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private struct Registration {
        var ref: EventHotKeyRef?
        let numericId: UInt32
        let handler: () -> Void
        var keyCode: UInt32
        var modifiers: UInt32
    }

    private var registrations: [String: Registration] = [:]
    private var idsByNumericId: [UInt32: String] = [:]
    private var nextNumericId: UInt32 = 1
    private var eventHandlerInstalled = false

    // "AFZM" (AutoFlash for ZMK)
    private let signature = OSType(0x4146_5A4D)

    private init() {}

    @discardableResult
    func register(
        id: String, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void
    ) -> Bool {
        installEventHandlerIfNeeded()

        if let existing = registrations[id], let ref = existing.ref {
            UnregisterEventHotKey(ref)
        }
        let numericId = registrations[id]?.numericId ?? allocateNumericId()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: numericId)
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else {
            registrations[id] = nil
            idsByNumericId[numericId] = nil
            return false
        }

        registrations[id] = Registration(
            ref: ref, numericId: numericId, handler: handler,
            keyCode: keyCode, modifiers: modifiers)
        idsByNumericId[numericId] = id
        return true
    }

    // 既存ハンドラを保ったままキーだけ差し替える。失敗時は元のキーに戻して false を返す。
    func updateKey(id: String, keyCode: UInt32, modifiers: UInt32) -> Bool {
        guard var registration = registrations[id] else { return false }

        if let ref = registration.ref {
            UnregisterEventHotKey(ref)
            registration.ref = nil
        }

        let hotKeyID = EventHotKeyID(signature: signature, id: registration.numericId)
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &newRef)

        if status == noErr {
            registration.ref = newRef
            registration.keyCode = keyCode
            registration.modifiers = modifiers
            registrations[id] = registration
            return true
        }

        // 失敗: 元のキーで再登録して状態を戻す
        var oldRef: EventHotKeyRef?
        if RegisterEventHotKey(
            registration.keyCode, registration.modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &oldRef) == noErr
        {
            registration.ref = oldRef
        }
        registrations[id] = registration
        return false
    }

    // レコーダーでのキー入力中に既存ホットキーが発火しないよう一時停止する
    func pauseAll() {
        for (id, var registration) in registrations {
            if let ref = registration.ref {
                UnregisterEventHotKey(ref)
                registration.ref = nil
                registrations[id] = registration
            }
        }
    }

    func resumeAll() {
        for (id, var registration) in registrations where registration.ref == nil {
            let hotKeyID = EventHotKeyID(signature: signature, id: registration.numericId)
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(
                registration.keyCode, registration.modifiers, hotKeyID,
                GetApplicationEventTarget(), 0, &ref) == noErr
            {
                registration.ref = ref
                registrations[id] = registration
            }
        }
    }

    private func allocateNumericId() -> UInt32 {
        let id = nextNumericId
        nextNumericId += 1
        return id
    }

    private func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData)
                    .takeUnretainedValue()
                DispatchQueue.main.async {
                    guard let id = center.idsByNumericId[hotKeyID.id] else { return }
                    center.registrations[id]?.handler()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
        eventHandlerInstalled = true
    }
}
