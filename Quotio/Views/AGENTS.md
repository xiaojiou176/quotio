# Views Layer

33 files: 17 Components + 7 Screens + 1 Onboarding + supporting views.

## 0) Purpose / Stack / Navigation / Verification

- Purpose: own Quotio UI presentation layer for components, screens, and onboarding experiences.
- Stack: SwiftUI + Swift 6 + macOS 15+.
- Directory navigation:
  - Reusable components: `Components/`
  - Page-level views: `Screens/`
  - Onboarding flow: `Onboarding/`
- Minimal verification commands:
  - `./scripts/test.sh`
  - `xcodebuild -project Quotio.xcodeproj -scheme Quotio -configuration Debug build`

## Structure

```
Views/
├── Components/     # Reusable UI building blocks (17 files)
├── Screens/        # Full-page views (7 files)
└── Onboarding/     # Initial setup flow (1 file)
```

## Where to Look

| Task | Location | Reuse |
|------|----------|-------|
| Provider display | `ProviderIcon.swift` | Icon with fallback |
| Account row | `AccountRow.swift` | Status, menu toggle, delete |
| Quota display | `QuotaCard.swift` | Progress bar, breakdown |
| Agent status | `AgentCard.swift` | Status badge, configure action |
| Button styling | `QuotioButtonStyles.swift` | Focus ring handling |
| New screen | `Screens/` + add to `NavigationPage` enum |

## Key Components

| Component | Purpose | Props |
|-----------|---------|-------|
| `ProviderIcon` | Provider logo with fallback | `provider`, `size` |
| `AccountRow` | Account display with actions | `account`, `onDelete` |
| `QuotaCard` | Quota progress and stats | `provider`, `quota` |
| `AgentCard` | CLI agent status card | `agent`, `status` |
| `ProviderDisclosureGroup` | Collapsible provider section | `provider`, `accounts` |
| `ProxyRequiredView` | "Start proxy" placeholder | - |

## Conventions

### View Structure
```swift
struct MyScreen: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @State private var localState = false
    
    // MARK: - Computed Properties
    private var isReady: Bool { ... }
    
    // MARK: - Body
    var body: some View {
        VStack { ... }
            .task { await loadData() }
    }
    
    // MARK: - Subviews
    private var headerSection: some View { ... }
    
    // MARK: - Actions
    private func loadData() async { ... }
}
```

### State Injection
```swift
// ViewModel via Environment
@Environment(QuotaViewModel.self) private var viewModel

// For two-way binding
@Bindable var vm = viewModel

// Local UI state
@State private var isExpanded = false

// User preferences
@AppStorage("showDetails") private var showDetails = true
```

### Async Patterns
```swift
// Lifecycle async
.task { await viewModel.loadData() }

// Button action
Button("Refresh") {
    Task { await viewModel.refresh() }
}

// With loading state
.task {
    isLoading = true
    defer { isLoading = false }
    await viewModel.loadData()
}
```

### Modals and Sheets
```swift
@State private var showSheet = false

.sheet(isPresented: $showSheet) {
    ConfigSheet(provider: selected)
}

// Confirmation dialog
.confirmationDialog("Delete?", isPresented: $showConfirm) {
    Button("Delete", role: .destructive) { delete() }
}
```

### Localization
```swift
Text("nav.dashboard".localized())
Text("quota.remaining".localized(remaining, total))
```

## Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Screen | `*Screen` | `DashboardScreen`, `ProvidersScreen` |
| Component | Descriptive noun | `AccountRow`, `ProviderIcon` |
| Onboarding | `*View` | `ModePickerView` |
| Sheet | `*Sheet` | `AgentConfigSheet`, `CustomProviderSheet` |
| Popover | `*Popover` | `AddProviderPopover` |

## Navigation

Uses `NavigationSplitView` with sidebar:
- Sidebar items defined in `NavigationPage` enum (Models/)
- Screens rendered based on `viewModel.currentPage`
- Modals via `.sheet()` for secondary flows

## Accessibility

- Use `.accessibilityLabel()` for icons
- Provide `.help()` for complex controls
- Enable text selection where appropriate
- Use semantic colors from asset catalog

## Governance Addendum (System 3+4)

### Lazy Load

1. Read this file, then local `CLAUDE.md`.
2. Load only affected views and direct state source in `../ViewModels/`.

### Search Before Writing

```bash
rg -n "keyword|viewName|componentName" .
rg --files . | rg "keyword|Screen|Card|View|Row"
```

If not reusing an existing implementation, include this in the delivery report:
```text
[Reuse Decision]
- Search keywords:
- Reused path (if any):
- Reason for not reusing (if any):
```

### Secret Boundary and Gate

- UI layer must not hardcode or display real credentials.
- Real secrets are allowed only from root `.env` or process ENV.
- Before commit, run:

```bash
bash ../../../scripts/secret-governance-check.sh
bash ../../../.githooks/pre-commit
```
