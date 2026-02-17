//
//  SettingsAboutAndGeneralSections.swift
//  Quotio
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct GeneralSettingsTab: View {
    @AppStorage("autoStartProxy") private var autoStartProxy = false
    
    var body: some View {
        @Bindable var lang = LanguageManager.shared
        
        Form {
            Section {
                LaunchAtLoginToggle()
                
                Toggle("settings.autoStartProxy".localized(), isOn: $autoStartProxy)
            } header: {
                Label("settings.startup".localized(), systemImage: "power")
            }
            
            Section {
                Picker(selection: Binding(
                    get: { lang.currentLanguage },
                    set: { lang.setLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        HStack {
                            Text(language.flag)
                            Text(language.displayName)
                        }
                        .tag(language)
                    }
                } label: {
                    Label("settings.language".localized(), systemImage: "globe")
                }
            } header: {
                Label("settings.language".localized(), systemImage: "globe")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 48))
                .foregroundStyle(Color.semanticInfo)
            
            Text("Quotio")
                .font(.title)
                .fontWeight(.bold)
            
            Text("about.tagline".localized(fallback: "CLIProxyAPI GUI Wrapper"))
                .foregroundStyle(.secondary)
            
            Text("about.version".localized(fallback: "Version") + " 1.0")
                .font(.caption)
                .foregroundStyle(.tertiary)
            
            Link("about.links.cliproxyapi".localized(fallback: "GitHub: CLIProxyAPI"), destination: URL(string: "https://github.com/router-for-me/CLIProxyAPI")!)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - About Screen (New Full-Page Version)

struct AboutScreen: View {
    @State private var showCopiedToast = false
    @State private var isHoveringVersion = false
    @State private var updaterService = UpdaterService.shared
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Hero Section
                heroSection
                
                // Description
                descriptionSection
                
                // Updates Grid
                updatesSection
                
                Divider()
                    .frame(maxWidth: 500)
                
                // Links Grid
                linksSection
                
                Spacer(minLength: 40)
                
                // Footer
                footerSection
            }
            .frame(maxWidth: .infinity)
            .padding(32)
        }
        .background(Color.semanticSurfaceBase)
        .overlay {
            if showCopiedToast {
                versionCopyToast
                    .transition(.opacity)
            }
        }
        .onAppear {
            #if canImport(Sparkle)
            updaterService.initializeIfNeeded()
            #endif
        }
        .navigationTitle("nav.about".localized())
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        VStack(spacing: 24) {
            // App Icon with gradient glow
            ZStack {
                // Glow effect
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.semanticInfo.opacity(0.2),
                                Color.semanticAccentSecondary.opacity(0.1),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 160, height: 160)
                    .blur(radius: 40)
                
                // App Icon - uses observable currentAppIcon from UpdaterService
                if let appIcon = UpdaterService.shared.currentAppIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: Color.primary.opacity(0.15), radius: 20, x: 0, y: 8)
                }
            }
            
            // App Name & Tagline
            VStack(spacing: 8) {
                Text("Quotio")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("about.tagline".localized())
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            // Version Badges
            HStack(spacing: 12) {
                VersionBadge(
                    label: "about.version".localized(fallback: "Version"),
                    value: appVersion,
                    icon: "tag"
                )
                .onHover { hovering in
                    isHoveringVersion = hovering
                }
                
                VersionBadge(
                    label: "about.build".localized(fallback: "Build"),
                    value: buildNumber,
                    icon: "hammer.fill"
                )
            }
        }
        .padding(.top, 24)
    }
    
    // MARK: - Description Section
    
    private var descriptionSection: some View {
        Text("about.description".localized())
            .font(.body)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 500)
    }
    
    // MARK: - Updates Section
    
    private var updatesSection: some View {
        VStack(spacing: 12) {
            AboutUpdateCard()
            
            if OperatingModeManager.shared.isLocalProxyMode {
                AboutProxyUpdateCard()
            }
        }
        .frame(maxWidth: 500)
    }
    
    // MARK: - Links Section
    
    private var linksSection: some View {
        VStack(spacing: 16) {
            Text("about.links.title".localized(fallback: "Links"))
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                LinkCard(
                    title: "about.links.quotio".localized(fallback: "GitHub: Quotio"),
                    icon: "link",
                    color: Color.semanticInfo,
                    url: URL(string: "https://github.com/nguyenphutrong/quotio")!
                )
                
                LinkCard(
                    title: "about.links.cliproxyapi".localized(fallback: "GitHub: CLIProxyAPI"),
                    icon: "link",
                    color: Color.semanticAccentSecondary,
                    url: URL(string: "https://github.com/router-for-me/CLIProxyAPI")!
                )
                
                LinkCard(
                    title: "about.support".localized(),
                    icon: "heart.fill",
                    color: Color.semanticWarning,
                    url: URL(string: "https://www.quotio.dev/sponsors")!
                )
            }
        }
        .frame(maxWidth: 500)
    }
    
    // MARK: - Footer Section
    
    private var footerSection: some View {
        VStack(spacing: 8) {
            Text("about.madeWith".localized())
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.bottom, 16)
    }
    
    // MARK: - Version Copy Toast
    
    private var versionCopyToast: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.semanticSuccess)
                Text("about.version.copied".localized(fallback: "Version copied to clipboard"))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: Color.primary.opacity(0.1), radius: 10, x: 0, y: 4)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity)
    }
}
