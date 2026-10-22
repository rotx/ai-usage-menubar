import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var store: UsageStore
    @Bindable var preferences: AppPreferences
    @Bindable var launchAtLogin: LaunchAtLoginController
    @Bindable var updateController: UpdateController
    var showDashboard: @MainActor () -> Void = {}
    @Environment(\.menuBarPanelMaximumHeight) private var maximumPanelHeight
    @State private var isReorderingProviders = false
    @State private var draggedProvider: ProviderID?
    @State private var dragStartIndex: Int?
    @State private var dragTranslation: CGFloat = 0
    @State private var rowStride: CGFloat = 0

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 16) {
                header
                AdaptiveScrollView(maximumHeight: max(120, maximumPanelHeight - 120)) {
                    VStack(alignment: .leading, spacing: 16) {
                        providersSection
                        generalSection
                    }
                }
                footer
            }
        }
        .padding(20)
        .frame(width: MenuBarPanelRoute.settings.width, alignment: .top)
        .onAppear {
            store.setTrackedProviders(preferences.trackedProviderIDs)
            store.setRefreshInterval(preferences.refreshInterval)
            launchAtLogin.synchronize()
        }
        .onChange(of: preferences.refreshInterval) { _, interval in
            store.setRefreshInterval(interval)
        }
        .onChange(of: preferences.automaticallyChecksForUpdates) { _, enabled in
            updateController.setAutomaticallyChecksForUpdates(enabled)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: showDashboard) {
                Label("Usage", systemImage: "chevron.left")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help("Back to usage")
            .accessibilityHint("Shows the usage dashboard")

            Text("Settings")
                .font(.title3.weight(.semibold))

            Spacer()
        }
    }

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Providers",
                systemImage: "switch.2",
                detail: "Choose what to track and what appears in the menu bar."
            )

            providerRows
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
    }

    private var providerRows: some View {
        let order = preferences.providerOrder
        return VStack(spacing: 0) {
            ProviderSettingsHeader(
                isReordering: isReorderingProviders,
                toggleReorder: toggleProviderReorder
            )

            if isReorderingProviders {
                Text("Drag to reorder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)
            }

            Divider()

            ForEach(order, id: \.self) { provider in
                let descriptor = provider.descriptor
                let availableItems = store.availableMenuBarItems(for: provider)
                ProviderSettingsRow(
                    descriptor: descriptor,
                    state: store.states[provider],
                    isTracking: preferences.isTracking(provider),
                    isVisible:
                        store.states[provider]?.isToolInstalled != false &&
                        preferences.isProviderShownInMenuBar(provider),
                    selectedMetrics: Set(
                        preferences.selectedMenuBarMetrics(for: provider)
                    ),
                    availableItems: availableItems,
                    isReordering: isReorderingProviders,
                    isDragged: draggedProvider == provider,
                    dragOffset: dragOffset(for: provider),
                    dragChanged: { translation in
                        updateProviderDrag(provider, translation: translation)
                    },
                    dragEnded: endProviderDrag,
                    moveBy: { offset in
                        preferences.moveProvider(provider, by: offset)
                    },
                    setTracking: { enabled in
                        preferences.setTracking(enabled, for: provider)
                        store.setTrackedProviders(preferences.trackedProviderIDs)
                    },
                    setVisible: { enabled in
                        preferences.setMenuBarVisibility(
                            enabled,
                            for: provider,
                            availableItems: availableItems
                        )
                    },
                    setMetric: { item, enabled in
                        preferences.setMenuBarMetric(
                            enabled,
                            item: item,
                            availableItems: availableItems
                        )
                    }
                )
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ProviderRowStrideKey.self,
                            value: proxy.size.height + 1
                        )
                    }
                }

                if provider != order.last {
                    Divider()
                }
            }
        }
        .coordinateSpace(name: ProviderReorderSpace.name)
        .onPreferenceChange(ProviderRowStrideKey.self) { rowStride = $0 }
    }

    private func toggleProviderReorder() {
        isReorderingProviders.toggle()
        if !isReorderingProviders {
            endProviderDrag()
        }
    }

    private func updateProviderDrag(_ provider: ProviderID, translation: CGFloat) {
        if draggedProvider != provider {
            draggedProvider = provider
            dragStartIndex = preferences.providerOrder.firstIndex(of: provider)
        }
        dragTranslation = translation
        guard let start = dragStartIndex else { return }
        let target = ProviderReorderMath.targetIndex(
            start: start,
            translation: translation,
            stride: rowStride,
            count: preferences.providerOrder.count
        )
        guard let current = preferences.providerOrder.firstIndex(of: provider),
              current != target else {
            return
        }
        preferences.moveProvider(provider, by: target - current)
    }

    private func endProviderDrag() {
        draggedProvider = nil
        dragStartIndex = nil
        dragTranslation = 0
    }

    private func dragOffset(for provider: ProviderID) -> CGFloat {
        guard draggedProvider == provider,
              let start = dragStartIndex,
              let current = preferences.providerOrder.firstIndex(of: provider),
              rowStride > 1 else {
            return 0
        }
        let raw = dragTranslation - CGFloat(current - start) * rowStride
        return min(max(raw, -rowStride), rowStride)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("General")
                .font(.headline)

            Grid(
                alignment: .leading,
                horizontalSpacing: 18,
                verticalSpacing: 11
            ) {
                GridRow {
                    Text("Numbers")
                        .foregroundStyle(.secondary)

                    Picker("Numbers", selection: $preferences.usageDisplayMode) {
                        ForEach(UsageDisplayMode.allCases) { mode in
                            Text(mode.title)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 130)
                }

                GridRow(alignment: .top) {
                    Text("Menu bar limits")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Picker("Menu bar limits", selection: $preferences.menuBarLimitDisplay) {
                            ForEach(MenuBarLimitDisplay.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180, alignment: .leading)
                        Text("Auto shows the selected session or weekly limit with the most usage. Side by side and Stacked show both. Other metrics follow your selections.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                GridRow {
                    Text("Percent signs")
                        .foregroundStyle(.secondary)
                    Toggle("Show % in menu bar", isOn: $preferences.showsMenuBarPercentSign)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                GridRow {
                    Text("Limit labels")
                        .foregroundStyle(.secondary)
                    Toggle("Show S / W in menu bar", isOn: $preferences.showsMenuBarSessionWeeklyLabels)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                GridRow {
                    Text("Refresh")
                        .foregroundStyle(.secondary)

                    Picker("Refresh", selection: $preferences.refreshInterval) {
                        ForEach(RefreshIntervalOption.allCases) { option in
                            Text(option.title)
                                .tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180, alignment: .leading)
                }

                GridRow(alignment: .top) {
                    Text("Startup")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(
                            "Launch at Login",
                            isOn: Binding(
                                get: { launchAtLogin.isEnabled },
                                set: { launchAtLogin.setEnabled($0) }
                            )
                        )
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        if launchAtLogin.requiresApproval {
                            Text("Approval needed in System Settings")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if let error = launchAtLogin.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .padding(.leading, 12)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                "Automatic update checks",
                isOn: $preferences.automaticallyChecksForUpdates
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("Checks at launch and once a day. Check for Updates… still works when this is off.")

            HStack(spacing: 12) {
                Button("Check for Updates…") {
                    updateController.checkForUpdates()
                }
                .disabled(updateController.isChecking)

                if updateController.isChecking {
                    ProgressView()
                        .controlSize(.small)
                }

                Link("Star on GitHub", destination: AppLinks.repository)

                Spacer()

                Button("Quit AI Usage") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .controlSize(.small)
        .padding(.top, 2)
    }

    private func sectionHeader(
        title: String,
        systemImage: String,
        detail: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private enum ProviderReorderSpace {
    static let name = "providerReorder"
}

private struct ProviderRowStrideKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ProviderSettingsHeader: View {
    let isReordering: Bool
    let toggleReorder: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if isReordering {
                Color.clear
                    .frame(width: ProviderSettingsRow.reorderHandleWidth)
                    .accessibilityHidden(true)
            }
            Text("Provider")
                .frame(width: 130, alignment: .leading)
            Text("Track")
                .frame(width: 44)
            Label("Menu Bar", systemImage: "menubar.rectangle")
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: toggleReorder) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isReordering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isReordering ? Color.primary.opacity(0.12) : .clear)
            }
            .accessibilityLabel("Reorder providers")
            .accessibilityValue(isReordering ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
            .help(
                isReordering
                    ? "Drag a provider by its handle. Click again when finished."
                    : "Reorder providers"
            )
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
    }
}

private struct ProviderSettingsRow: View {
    let descriptor: ProviderDescriptor
    let state: ProviderState?
    let isTracking: Bool
    let isVisible: Bool
    let selectedMetrics: Set<MenuBarMetricID>
    let availableItems: [MenuBarItemID]
    let isReordering: Bool
    let isDragged: Bool
    let dragOffset: CGFloat
    let dragChanged: (CGFloat) -> Void
    let dragEnded: () -> Void
    let moveBy: (Int) -> Void
    let setTracking: (Bool) -> Void
    let setVisible: (Bool) -> Void
    let setMetric: (MenuBarItemID, Bool) -> Void

    static let reorderHandleWidth: CGFloat = 22

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if isReordering {
                reorderHandle
            }

            HStack(spacing: 8) {
                ProviderIcon(provider: descriptor.id, size: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.displayName)
                        .font(.body.weight(.medium))

                    if isTracking {
                        ProviderStatusView(state: state)
                    } else {
                        Label("Off", systemImage: "pause.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 130, alignment: .leading)

            Toggle(
                "Track \(descriptor.displayName)",
                isOn: Binding(
                    get: { isTracking },
                    set: { enabled in setTracking(enabled) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .frame(width: 44)
            .accessibilityLabel("Track \(descriptor.displayName)")

            HStack(spacing: 8) {
                Toggle(
                    "Show \(descriptor.displayName) in Menu Bar",
                    isOn: Binding(
                        get: { isVisible },
                        set: { enabled in setVisible(enabled) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .frame(width: 44)
                .disabled(!isTracking || (!isVisible && !canEnableMenuBar))
                .help(
                    isVisible
                        ? "Hide \(descriptor.displayName) from the menu bar"
                        : "Show \(descriptor.displayName) in the menu bar"
                )

                Divider()
                    .frame(height: 20)

                menuBarMetrics
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
        .background {
            if isDragged {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            }
        }
        .offset(y: dragOffset)
        .zIndex(isDragged ? 1 : 0)
        .accessibilityElement(children: .contain)
        .modifier(ProviderReorderActions(enabled: isReordering, moveBy: moveBy))
    }

    private var reorderHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: Self.reorderHandleWidth, height: 28)
            .contentShape(Rectangle())
            .accessibilityLabel("Drag \(descriptor.displayName)")
            .help("Drag to move \(descriptor.displayName)")
            .onHover { hovering in
                if hovering {
                    NSCursor.openHand.set()
                } else if !isDragged {
                    NSCursor.arrow.set()
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(ProviderReorderSpace.name))
                    .onChanged { value in
                        NSCursor.closedHand.set()
                        dragChanged(value.translation.height)
                    }
                    .onEnded { _ in
                        NSCursor.arrow.set()
                        dragEnded()
                    }
            )
    }

    @ViewBuilder
    private var menuBarMetrics: some View {
        if availableItems.isEmpty {
            Text(emptyMetricsMessage)
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 8) {
                ForEach(availableItems) { item in
                    Toggle(
                        item.metric.title,
                        isOn: Binding(
                            get: {
                                selectedMetrics.contains(item.metric)
                            },
                            set: { enabled in
                                setMetric(item, enabled)
                            }
                        )
                    )
                    .font(.caption)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .disabled(!isTracking || !isVisible)
                    .help(
                        enabledMetricHelp(
                            item.metric,
                            isSelected:
                                selectedMetrics.contains(item.metric)
                        )
                    )
                }
            }
        }
    }

    private var canEnableMenuBar: Bool {
        state?.isToolInstalled != false &&
            (!selectedMetrics.isEmpty || !availableItems.isEmpty)
    }

    private var emptyMetricsMessage: String {
        if state?.isToolInstalled == false {
            return "Not installed"
        }
        if state?.isRefreshing == true {
            return "Loading available metrics…"
        }
        if state?.failure?.kind == .authentication {
            return "Log in to choose metrics"
        }
        return "No usage metrics returned"
    }

    private func enabledMetricHelp(
        _ metric: MenuBarMetricID,
        isSelected: Bool
    ) -> String {
        isSelected
            ? "Hide \(metric.title) for \(descriptor.displayName)"
            : "Show \(metric.title) for \(descriptor.displayName)"
    }
}

private struct ProviderReorderActions: ViewModifier {
    let enabled: Bool
    let moveBy: (Int) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .accessibilityAction(named: Text("Move up")) { moveBy(-1) }
                .accessibilityAction(named: Text("Move down")) { moveBy(1) }
        } else {
            content
        }
    }
}

private struct ProviderStatusView: View {
    let state: ProviderState?

    var body: some View {
        let presentation = ProviderStatusPresentation(state: state)

        Label(presentation.text, systemImage: presentation.systemImage)
            .font(.caption)
            .foregroundStyle(presentation.color)
            .labelStyle(.titleAndIcon)
            .accessibilityLabel(presentation.text)
            .help(state?.failure?.message ?? presentation.text)
    }
}

private struct ProviderStatusPresentation {
    let text: String
    let systemImage: String
    let color: Color

    init(state: ProviderState?) {
        guard let state else {
            text = "Checking…"
            systemImage = "clock"
            color = .secondary
            return
        }

        if state.isToolInstalled == false {
            text = "Not installed"
            systemImage = "minus.circle"
            color = .secondary
            return
        }

        if let failure = state.failure {
            switch failure.kind {
            case .authentication:
                text = "Not logged in"
                systemImage = "person.crop.circle.badge.exclamationmark"
                color = .orange
            case .rateLimited:
                text = "Rate limited"
                systemImage = "hourglass"
                color = .orange
            case .storage:
                text = "Credential access failed"
                systemImage = "lock.trianglebadge.exclamationmark"
                color = .orange
            case .transient, .invalidResponse:
                text = state.snapshot == nil
                    ? "Temporarily unavailable"
                    : "Showing last update"
                systemImage = "exclamationmark.triangle"
                color = .orange
            }
            return
        }

        if state.snapshot != nil {
            text = "Connected"
            systemImage = "checkmark.circle.fill"
            color = .green
        } else {
            text = state.isRefreshing ? "Checking…" : "Waiting for usage"
            systemImage = "clock"
            color = .secondary
        }
    }
}
