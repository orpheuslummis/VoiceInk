//
//  RecordingShortcutModeHandlerTests.swift
//  VoiceInkTests
//
//  Unit tests for the recording activation state machine: Toggle, Push-to-Talk,
//  Hybrid, and the "lock to hands-free" promotion used by both the keyboard
//  shortcut and the middle-mouse trigger.
//

import Testing
@testable import VoiceInk

@MainActor
private final class FakeRecorder {
    var recording = false
    var toggleCount = 0
    func toggle() {
        recording.toggle()
        toggleCount += 1
    }
}

@MainActor
private func makeHandler(_ fake: FakeRecorder) -> RecordingShortcutModeHandler {
    RecordingShortcutModeHandler(
        canHandleShortcutAction: { true },
        isRecorderVisible: { fake.recording },
        recordingState: { fake.recording ? .recording : .idle },
        toggleRecorderPanel: { _ in fake.toggle() },
        cancelRecording: { }
    )
}

@MainActor
struct RecordingShortcutModeHandlerTests {

    @Test func pushToTalkStartsOnDownStopsOnUp() async {
        let fake = FakeRecorder()
        let handler = makeHandler(fake)

        await handler.handleKeyDown(action: .primaryRecording, eventTime: 0, mode: .pushToTalk)
        #expect(fake.recording == true)

        await handler.handleKeyUp(action: .primaryRecording, eventTime: 0.2, mode: .pushToTalk)
        #expect(fake.recording == false)
        #expect(fake.toggleCount == 2)
    }

    @Test func toggleKeepsRecordingAfterRelease() async {
        let fake = FakeRecorder()
        let handler = makeHandler(fake)

        await handler.handleKeyDown(action: .primaryRecording, eventTime: 0, mode: .toggle)
        #expect(fake.recording == true)

        await handler.handleKeyUp(action: .primaryRecording, eventTime: 0.1, mode: .toggle)
        #expect(fake.recording == true)     // hands-free: stays recording after release
        #expect(fake.toggleCount == 1)
    }

    @Test func hybridQuickTapStaysRecording() async {
        let fake = FakeRecorder()
        let handler = makeHandler(fake)

        await handler.handleKeyDown(action: .primaryRecording, eventTime: 0, mode: .hybrid)
        // released well under the 0.5s hybrid threshold -> behaves like a toggle
        await handler.handleKeyUp(action: .primaryRecording, eventTime: 0.1, mode: .hybrid)
        #expect(fake.recording == true)
        #expect(fake.toggleCount == 1)
    }

    @Test func hybridLongHoldStopsOnRelease() async {
        let fake = FakeRecorder()
        let handler = makeHandler(fake)

        await handler.handleKeyDown(action: .primaryRecording, eventTime: 0, mode: .hybrid)
        // held past the 0.5s threshold -> push-to-talk, stops on release
        await handler.handleKeyUp(action: .primaryRecording, eventTime: 1.0, mode: .hybrid)
        #expect(fake.recording == false)
        #expect(fake.toggleCount == 2)
    }

    @Test func promoteToHandsFreeKeepsRecordingAfterPushToTalkRelease() async {
        let fake = FakeRecorder()
        let handler = makeHandler(fake)

        await handler.handleKeyDown(action: .primaryRecording, eventTime: 0, mode: .pushToTalk)
        #expect(fake.recording == true)

        handler.promoteToHandsFree()    // e.g. user tapped Space mid-hold
        // releasing the push-to-talk trigger must NOT stop recording now
        await handler.handleKeyUp(action: .primaryRecording, eventTime: 1.0, mode: .pushToTalk)
        #expect(fake.recording == true)
        #expect(fake.toggleCount == 1)
    }

    @Test func promoteIsIgnoredWhenNotHolding() async {
        let fake = FakeRecorder()
        let handler = makeHandler(fake)

        // no active press -> promotion is a no-op (guards on isShortcutPressed)
        handler.promoteToHandsFree()
        #expect(fake.recording == false)
        #expect(fake.toggleCount == 0)
    }
}
