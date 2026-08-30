import SwiftUI
import AppKit

// MARK: - Step Machine

enum OnboardingStep: Hashable {
    case welcome, microphone, accessibility, engine, enhancement, hotkey
    case appExclusions
    case demoText, demoHUD, demoFreeMode, demoPrivacy
    case finished
}

struct OnboardingView: View {
    @State private var step: OnboardingStep = .welcome
    let onFinish: () -> Void
    let onOpenSettings: () -> Void
    var onDemoStepsReached: () -> Void = {}

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                OnboardingWelcomeView { advance(to: .microphone) }
                    .transition(.opacity)

            case .microphone:
                OnboardingPermissionView(
                    icon: Image(systemName: "mic.fill"),
                    title: "Enable Microphone Access",
                    description: "OpenFlow Voice listens while you hold the push-to-talk key and transcribes what you say. Microphone access is only used during active dictation — never in the background.",
                    privacyNote: "Audio is processed on-device and never recorded or stored.",
                    allowLabel: "Allow Access",
                    onAllow: {
                        Task {
                            _ = await Permissions.requestMicrophone()
                            advance(to: .accessibility)
                        }
                    },
                    onSkip: { advance(to: .accessibility) }
                )
                .transition(.opacity)

            case .accessibility:
                OnboardingPermissionView(
                    icon: Image(systemName: "hand.raised.fill"),
                    title: "Enable Accessibility Access",
                    description: "Accessibility access lets OpenFlow Voice type your words directly into any app — exactly like a keyboard. Without it, transcribed text cannot be inserted.\n\nClick Open Settings, find OpenFlow Voice in the list, and toggle it on.",
                    privacyNote: "Accessibility is used only to type text. No other app data is read or shared.",
                    allowLabel: "Open Settings",
                    onAllow: {
                        Permissions.openAccessibilitySettings()
                        advance(to: .engine)
                    },
                    onSkip: { advance(to: .engine) }
                )
                .transition(.opacity)

            case .engine:
                OnboardingEngineView { advance(to: .enhancement) }
                    .transition(.opacity)

            case .enhancement:
                OnboardingEnhancementView { advance(to: .hotkey) }
                    .transition(.opacity)

            case .hotkey:
                OnboardingHotkeyView { key in
                    let isOption = key == .leftOption || key == .rightOption
                    let next: OnboardingStep = isOption && !OnboardingAppExclusionsView.installedOptionKeyApps().isEmpty
                        ? .appExclusions : .demoText
                    advance(to: next)
                }
                .transition(.opacity)

            case .appExclusions:
                OnboardingAppExclusionsView { advance(to: .demoText) }
                    .transition(.opacity)

            case .demoText:
                OnboardingDemoView(
                    icon: Image(systemName: "text.cursor"),
                    title: "Try it out",
                    description: "Click into the field below, hold \(Settings.shared.pushToTalkKey.displayName) and say something.\n\nYour words appear as you speak.",
                    buttonLabel: "Next",
                    showTextField: true
                ) { advance(to: .demoHUD) }
                .transition(.opacity)

            case .demoHUD:
                OnboardingDemoView(
                    icon: Image(systemName: "bubble.left"),
                    title: "No text field? No problem.",
                    description: "Hold \(Settings.shared.pushToTalkKey.displayName) anywhere without a text field focused. A small HUD appears with what you said — copy it to the clipboard, or it auto-dismisses after a few seconds.",
                    buttonLabel: "Next"
                ) {
                    advance(to: .demoFreeMode)
                }
                .transition(.opacity)

            case .demoFreeMode:
                OnboardingDemoView(
                    icon: Image(systemName: "hand.tap"),
                    title: "Hands-Free Mode",
                    description: "Double-tap \(Settings.shared.pushToTalkKey.displayName) to start dictating without holding the key. Tap once more when you're done.\n\nTap, pause briefly, then tap again — it's a deliberate double-tap, not a rapid double-click.",
                    buttonLabel: "Next"
                ) {
                    let next: OnboardingStep = Settings.shared.enhancementMode == .cloud ? .demoPrivacy : .finished
                    advance(to: next)
                }
                .transition(.opacity)

            case .demoPrivacy:
                OnboardingDemoView(
                    icon: Image(systemName: "lock.shield"),
                    title: "Smart Privacy",
                    description: "Click the field below and say \"My password is 1234\". OpenFlow Voice detects sensitive information before it leaves your Mac and asks whether to send it for enhancement — or switch to on-device AI instead.",
                    buttonLabel: "Got It",
                    showTextField: true
                ) { advance(to: .finished) }
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(
                    keyName: Settings.shared.pushToTalkKey.displayName,
                    onFinish: onFinish,
                    onOpenSettings: onOpenSettings
                )
                .transition(.opacity)
            }
        }
    }

    private func advance(to next: OnboardingStep) {
        if next == .demoText { onDemoStepsReached() }
        withAnimation(.easeInOut(duration: 0.45)) {
            step = next
        }
    }
}

// MARK: - Welcome

private struct OnboardingWelcomeView: View {
    let onGetStarted: () -> Void
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.10))
                .frame(width: 220, height: 220)
                .blur(radius: 40)
                .scaleEffect(pulse ? 1.2 : 0.85)
                .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: pulse)

            VStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 72, weight: .ultraLight))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
                    .padding(.bottom, 4)

                Text("OpenFlow Voice")
                    .font(.system(.largeTitle, design: .default).weight(.semibold))

                Text("Welcome")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 28)

                Button("Get Started", action: onGetStarted)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingBackground())
        .onAppear { pulse = true }
    }
}

// MARK: - Permission View

private struct OnboardingPermissionView: View {
    let icon: Image
    let title: String
    let description: String
    let privacyNote: String?
    let allowLabel: String
    let onAllow: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            icon
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 50)
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 24)

            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)

            if let note = privacyNote {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.tertiary)
                        .font(.footnote)
                        .padding(.top, 1)
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 36)
                .padding(.top, 20)
            }

            Spacer()
            Spacer()

            HStack(spacing: 12) {
                Button("Not Now", action: onSkip)
                    .buttonStyle(.bordered)
                Button(allowLabel, action: onAllow)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingBackground())
    }
}

// MARK: - Engine Picker

private struct OnboardingEngineView: View {
    @State private var selected: SpeechEngineChoice = Settings.shared.engine
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Transcription Engine")
                .font(.title2.weight(.semibold))
                .padding(.top, 36)
                .padding(.bottom, 8)

            Text("Choose how your speech is transcribed. You can change this anytime in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
                .padding(.bottom, 24)

            VStack(spacing: 10) {
                OnboardingOptionCard(
                    title: "Apple Speech",
                    subtitle: "Streams text as you speak. No download required.",
                    pros: ["Live text while dictating", "Works immediately"],
                    cons: ["Lower accuracy on technical terms"],
                    isSelected: selected == .apple
                ) { selected = .apple }

                OnboardingOptionCard(
                    title: "Parakeet",
                    subtitle: "Neural Engine batch model. Higher accuracy.",
                    pros: ["More accurate", "Neural Engine optimized"],
                    cons: ["~470 MB one-time download", "Text appears after you stop"],
                    isSelected: selected == .parakeet
                ) { selected = .parakeet }
            }
            .padding(.horizontal, 20)

            Spacer()

            Button("Continue") {
                Settings.shared.engine = selected
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingBackground())
    }
}

// MARK: - Enhancement Picker

private struct OnboardingEnhancementView: View {
    @State private var mode: EnhancementMode = Settings.shared.enhancementMode
    @State private var provider: CloudProviderChoice = Settings.shared.cloudProvider
    @State private var apiKey = ""
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Text("Enhancement")
                        .font(.title2.weight(.semibold))
                        .padding(.top, 36)
                        .padding(.bottom, 8)

                    Text("Optionally polish your transcript with AI after each dictation.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 24)

                    VStack(spacing: 10) {
                        OnboardingOptionCard(
                            title: "Off",
                            subtitle: "Raw transcript. Fastest and fully private.",
                            pros: [],
                            cons: [],
                            isSelected: mode == .off
                        ) { mode = .off }

                        OnboardingOptionCard(
                            title: "On-device AI",
                            subtitle: "Apple Intelligence improves grammar and clarity. Private, no account needed.",
                            pros: ["Fully private", "No API key required"],
                            cons: ["Requires Apple Intelligence"],
                            isSelected: mode == .local
                        ) { mode = .local }

                        OnboardingOptionCard(
                            title: "Cloud AI",
                            subtitle: "Highest quality. Sends text to a cloud API for enhancement.",
                            pros: ["Best formatting quality"],
                            cons: ["Requires an API key", "Text sent to cloud"],
                            isSelected: mode == .cloud
                        ) { mode = .cloud }
                    }
                    .padding(.horizontal, 20)

                    if mode == .cloud {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Provider")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Picker("Provider", selection: $provider) {
                                    ForEach(CloudProviderChoice.allCases, id: \.self) { p in
                                        Text(p.displayName).tag(p)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }

                            ApiKeyField(provider: provider, text: $apiKey)
                        }
                        .padding(16)
                        .background(.background.secondary, in: .rect(cornerRadius: 12))
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .onAppear {
                            apiKey = KeychainStore.load(forKey: provider.keychainKey) ?? ""
                        }
                        .onChange(of: provider) { _, p in
                            apiKey = KeychainStore.load(forKey: p.keychainKey) ?? ""
                        }
                    }

                    Spacer().frame(height: 24)
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            Button("Continue") {
                Settings.shared.enhancementMode = mode
                if mode == .cloud {
                    Settings.shared.cloudProvider = provider
                    if !apiKey.isEmpty {
                        KeychainStore.save(apiKey, forKey: provider.keychainKey)
                    }
                }
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingBackground())
        .animation(.easeInOut(duration: 0.25), value: mode)
    }
}

// MARK: - Hotkey Capture

private struct OnboardingHotkeyView: View {
    @State private var selected: PushToTalkKey = Settings.shared.pushToTalkKey
    @State private var isListening = false
    @State private var hasSelected = false
    @State private var eventMonitor: Any?
    let onContinue: (PushToTalkKey) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "keyboard")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 24)

            Text("Choose Your Shortcut")
                .font(.title2.weight(.semibold))
                .padding(.bottom, 10)

            Text("Press any modifier key. Hold it while you speak to dictate.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.bottom, 44)

            Button { startListening() } label: {
                Text(isListening ? "Press a key…" : selected.displayName)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(isListening ? .secondary : Color.accentColor)
                    .frame(width: 160, height: 76)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isListening ? Color.primary.opacity(0.03) : Color.accentColor.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isListening ? Color.accentColor : Color.accentColor.opacity(0.5),
                                lineWidth: isListening ? 2 : 1.5
                            )
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isListening)

            Text(isListening ? "Listening…" : "Tap the box to change")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 12)

            Spacer()
            Spacer()

            Button("Continue") {
                Settings.shared.pushToTalkKey = selected
                stopListening()
                HotkeyMonitor.shared.start(key: selected)
                onContinue(selected)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!hasSelected)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingBackground())
        .onAppear { startListening() }
        .onDisappear { stopListening() }
    }

    private func startListening() {
        stopListening()
        // Stop the CGEventTap so it can't consume modifier events before they
        // reach the NSEvent local monitor (Left Option is consumed otherwise).
        HotkeyMonitor.shared.stop()
        isListening = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let code = Int64(event.keyCode)
            if let matched = PushToTalkKey.allCases.first(where: { $0.keyCode == code }) {
                selected = matched
                hasSelected = true
                stopListening()
            }
            return event
        }
    }

    private func stopListening() {
        isListening = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// MARK: - Finish

private struct OnboardingFinishView: View {
    let keyName: String
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 60, weight: .ultraLight))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 20)

            Text("You're All Set!")
                .font(.largeTitle.weight(.bold))
                .padding(.bottom, 12)

            Text("Hold \(keyName) to dictate anywhere.\nYour words appear instantly in whatever you're typing.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
            Spacer()

            VStack(spacing: 12) {
                Button {
                    onOpenSettings()
                } label: {
                    Label("Customize in Settings", systemImage: "gear")
                }
                .controlSize(.large)

                Button("Start Dictating", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingBackground())
    }
}

// MARK: - Demo Instruction View

private struct OnboardingDemoView: View {
    let icon: Image
    let title: String
    let description: String
    let buttonLabel: String
    var showTextField: Bool = false
    let onContinue: () -> Void

    @State private var demoInput = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            icon
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 48)
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 24)

            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)

            if showTextField {
                TextField("Click here, then hold \(Settings.shared.pushToTalkKey.displayName) and speak…", text: $demoInput)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 36)
                    .padding(.top, 20)
            }

            Spacer()
            Spacer()

            Button(buttonLabel, action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingBackground())
    }
}

// MARK: - Shared Components

private struct OnboardingBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct OnboardingOptionCard: View {
    let title: String
    let subtitle: String
    let pros: [String]
    let cons: [String]
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !pros.isEmpty || !cons.isEmpty {
                        Divider().padding(.vertical, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(pros, id: \.self) { OnboardingCardBullet(text: $0, positive: true) }
                            ForEach(cons, id: \.self) { OnboardingCardBullet(text: $0, positive: false) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - App Exclusions

private struct AppEntry: Identifiable {
    let id = UUID()
    let name: String
    let bundleID: String
    let icon: NSImage
}

private struct OnboardingAppExclusionsView: View {
    let onContinue: () -> Void

    @State private var apps: [AppEntry] = []
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 36)
                .padding(.bottom, 20)

            Text("Protect App Shortcuts")
                .font(.title2.weight(.semibold))
                .padding(.bottom, 8)

            Text("These apps use ⌥ for their own shortcuts. When one of them is frontmost, your push-to-talk key passes through normally.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
                .padding(.bottom, 12)

            HStack {
                Spacer()
                Button(selected.count == apps.count ? "Deselect All" : "Select All") {
                    if selected.count == apps.count {
                        selected.removeAll()
                    } else {
                        selected = Set(apps.map(\.bundleID))
                    }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 4)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(apps) { app in
                        Toggle(isOn: Binding(
                            get: { selected.contains(app.bundleID) },
                            set: { on in
                                if on { selected.insert(app.bundleID) }
                                else { selected.remove(app.bundleID) }
                            }
                        )) {
                            HStack(spacing: 10) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text(app.name)
                                    .font(.body)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 7)

                        if app.id != apps.last?.id {
                            Divider().padding(.horizontal, 28)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button(selected.isEmpty ? "Continue" : "Add \(selected.count) App\(selected.count == 1 ? "" : "s")") {
                for bundleID in selected where !Settings.shared.excludedBundleIDs.contains(bundleID) {
                    Settings.shared.excludedBundleIDs.append(bundleID)
                }
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingBackground())
        .onAppear {
            apps = Self.installedOptionKeyApps()
            selected = Set(apps.map(\.bundleID))
        }
    }

    @MainActor
    static func installedOptionKeyApps() -> [AppEntry] {
        let candidates: [(String, String)] = [
            ("Adobe Photoshop",         "com.adobe.Photoshop"),
            ("Adobe Illustrator",       "com.adobe.Illustrator"),
            ("Adobe InDesign",          "com.adobe.InDesign"),
            ("Adobe Premiere Pro",      "com.adobe.PremierePro"),
            ("Adobe After Effects",     "com.adobe.AfterEffects"),
            ("Adobe Lightroom Classic", "com.adobe.LightroomClassicCC7"),
            ("Affinity Photo",          "com.seriflabs.affinityphoto"),
            ("Affinity Designer",       "com.seriflabs.affinitydesigner2"),
            ("Affinity Publisher",      "com.seriflabs.affinitypublisher2"),
            ("Sketch",                  "com.bohemiancoding.sketch3"),
            ("Figma",                   "com.figma.Desktop"),
            ("Pixelmator Pro",          "com.pixelmatorteam.pixelmator.x"),
            ("Final Cut Pro",           "com.apple.FinalCut"),
            ("Logic Pro",               "com.apple.logic10"),
            ("DaVinci Resolve",         "com.blackmagic-design.DaVinciResolve"),
            ("Blender",                 "org.blenderfoundation.blender"),
            ("OmniGraffle",             "com.omnigroup.OmniGraffle7"),
            ("Xcode",                   "com.apple.dt.Xcode"),
            ("BBEdit",                  "com.barebones.bbedit"),
            ("Sublime Text",            "com.sublimetext.4"),
            ("Visual Studio Code",      "com.microsoft.VSCode"),
            ("iTerm2",                  "com.googlecode.iterm2"),
            ("Terminal",                "com.apple.Terminal"),
            ("Finder",                  "com.apple.finder"),
            ("Safari",                  "com.apple.Safari"),
            ("Slack",                   "com.tinyspeck.slackmacgap"),
            ("Keynote",                 "com.apple.iWork.Keynote"),
            ("Pages",                   "com.apple.iWork.Pages"),
            ("Numbers",                 "com.apple.iWork.Numbers"),
            ("Preview",                 "com.apple.Preview"),
            ("Mail",                    "com.apple.mail"),
            ("Calendar",                "com.apple.iCal"),
            ("Notes",                   "com.apple.Notes"),
        ]
        return candidates.compactMap { name, bundleID in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return AppEntry(name: name, bundleID: bundleID, icon: icon)
        }
    }
}

// MARK: -

private struct OnboardingCardBullet: View {
    let text: String
    let positive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: positive ? "checkmark" : "minus")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(positive ? Color.green : Color.secondary)
                .frame(width: 12, height: 12, alignment: .center)
                .padding(.top, 1.5)
            Text(text)
                .font(.caption)
                .foregroundStyle(positive ? Color.primary : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
