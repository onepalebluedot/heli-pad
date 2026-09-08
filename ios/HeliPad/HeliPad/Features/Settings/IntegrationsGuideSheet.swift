import SwiftUI

public struct IntegrationsGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Int = 0

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            HeliIcon("sparkles", size: 18)
                                .foregroundColor(HeliColors.forestGreen)
                            Text("Services & API Setup")
                                .font(HeliTypography.eyebrow(11))
                                .foregroundColor(HeliColors.forestGreen)
                                .tracking(1.2)
                        }
                        Text("Connect External Services")
                            .font(.system(size: 24, weight: .bold, design: .serif))
                            .foregroundColor(HeliColors.greenInk)
                        Text("HeliPad works offline out-of-the-box, but connecting Google Maps and Neon Postgres unlocks real-time cloud capabilities.")
                            .font(HeliTypography.body(13.5))
                            .foregroundColor(HeliColors.mutedGray)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HeliColors.cardWarmWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    // Tab Picker
                    Picker("Service", selection: $selectedTab) {
                        Text("Google Maps").tag(0)
                        Text("Neon Cloud").tag(1)
                        Text("Weather").tag(2)
                    }
                    .pickerStyle(.segmented)

                    // Tab Content
                    if selectedTab == 0 {
                        googleMapsGuide
                    } else if selectedTab == 1 {
                        neonDatabaseGuide
                    } else {
                        weatherGuide
                    }
                }
                .padding(20)
            }
            .background(HeliColors.canvasIvory)
            .navigationTitle("Setup Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(HeliTypography.buttonLabel(15))
                    .foregroundColor(HeliColors.forestGreen)
                }
            }
        }
    }

    // MARK: - Google Maps Guide
    private var googleMapsGuide: some View {
        VStack(alignment: .leading, spacing: 18) {
            guideSectionHeader(
                icon: "location.north.fill",
                title: "Google Maps Platform",
                subtitle: "Powers venue autocomplete suggestions, address lookup, and real-time traffic drive times."
            )

            calloutNote(
                icon: "shield.check.fill",
                title: "Graceful Fallback Included",
                text: "If no Google API key is provided, HeliPad automatically falls back to Apple MapKit local search and directions. No credit card or Google account is mandatory."
            )

            VStack(alignment: .leading, spacing: 14) {
                Text("Step-by-Step Instructions")
                    .font(HeliTypography.railTitle(15))
                    .foregroundColor(HeliColors.greenInk)

                stepRow(
                    step: 1,
                    title: "Open Google Cloud Console",
                    desc: "Visit console.cloud.google.com and sign in with your Google account."
                )

                stepRow(
                    step: 2,
                    title: "Create a New Project",
                    desc: "Click the project selector at the top and select 'New Project'. Name it 'HeliPad' or 'HeliPad-Family'."
                )

                stepRow(
                    step: 3,
                    title: "Enable Required APIs",
                    desc: "Go to 'APIs & Services' > 'Library' and enable the following three APIs:\n• Places API (or Places API New)\n• Distance Matrix API\n• Geocoding API"
                )

                stepRow(
                    step: 4,
                    title: "Generate an API Key",
                    desc: "Navigate to 'APIs & Services' > 'Credentials'. Click '+ CREATE CREDENTIALS' > 'API key'. Copy your new key."
                )

                stepRow(
                    step: 5,
                    title: "(Recommended) Restrict the Key",
                    desc: "Under 'API restrictions', select 'Restrict key' and choose Places API, Distance Matrix API, and Geocoding API to prevent unexpected usage."
                )

                stepRow(
                    step: 6,
                    title: "Paste into HeliPad Settings",
                    desc: "Return to HeliPad Settings > Integrations & Cloud > Google Maps API Key, paste your key, and tap 'Test Places & Route'."
                )
            }
        }
    }

    // MARK: - Neon Database Guide
    private var neonDatabaseGuide: some View {
        VStack(alignment: .leading, spacing: 18) {
            guideSectionHeader(
                icon: "cylinder",
                title: "Neon Serverless Postgres",
                subtitle: "Syncs your household schedule, routines, locations, and caregiver assignments in real time."
            )

            calloutNote(
                icon: "lock.shield.fill",
                title: "Free Serverless Tier",
                text: "Neon provides a generous free tier (up to 0.5 GB storage with instant branching), perfect for family schedule sync with zero maintenance."
            )

            VStack(alignment: .leading, spacing: 14) {
                Text("Step-by-Step Instructions")
                    .font(HeliTypography.railTitle(15))
                    .foregroundColor(HeliColors.greenInk)

                stepRow(
                    step: 1,
                    title: "Sign Up at Neon",
                    desc: "Visit neon.tech and sign up with GitHub, Google, or email."
                )

                stepRow(
                    step: 2,
                    title: "Create a Project",
                    desc: "Click 'Create Project'. Choose a name (e.g. 'helipad-family') and select a region closest to your home."
                )

                stepRow(
                    step: 3,
                    title: "Copy the Connection String",
                    desc: "On your project dashboard, find 'Connection Details'. Ensure 'Pooled connection' is enabled and copy the connection URL. It looks like:\npostgresql://user:pass@ep-xyz.us-east-2.aws.neon.tech/neondb?sslmode=require"
                )

                stepRow(
                    step: 4,
                    title: "Paste into HeliPad",
                    desc: "Paste the URL into HeliPad Settings > Integrations & Cloud > Neon Connection String."
                )

                stepRow(
                    step: 5,
                    title: "Tap 'Test Connection'",
                    desc: "Use Test Connection, then enable sync for your own database. On another device, enter the same household ID and use Download cloud household first. For data saved by the earlier app, enter primary as the household ID and download it. Connection passwords stay in this device’s Keychain."
                )
            }
        }
    }

    // MARK: - Weather Guide
    private var weatherGuide: some View {
        VStack(alignment: .leading, spacing: 18) {
            guideSectionHeader(
                icon: "sun.max.fill",
                title: "Open-Meteo Weather",
                subtitle: "Supplies daily temperature range and weather conditions on your Go masthead."
            )

            calloutNote(
                icon: "sparkles",
                title: "Zero API Key Required",
                text: "Open-Meteo is an open-source meteorological API that is free for non-commercial use with no API key, registration, or credit card needed!"
            )

            VStack(alignment: .leading, spacing: 14) {
                Text("How HeliPad Uses It")
                    .font(HeliTypography.railTitle(15))
                    .foregroundColor(HeliColors.greenInk)

                stepRow(
                    step: 1,
                    title: "Location Detection",
                    desc: "HeliPad uses your device's current location (or default household coordinates) to determine latitude and longitude."
                )

                stepRow(
                    step: 2,
                    title: "Live Forecast Query",
                    desc: "When you launch the app, HeliPad fetches today's high and low temperature range and WMO weather codes over secure HTTPS."
                )

                stepRow(
                    step: 3,
                    title: "Automatic Caching & Battery Conservation",
                    desc: "Weather responses are cached to conserve network data and battery life, avoiding constant background pings. You can also refresh manually anytime in Settings."
                )
            }
        }
    }

    // MARK: - Helper Views

    private func guideSectionHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(HeliColors.forestGreen)
                Text(title)
                    .font(HeliTypography.railTitle(17))
                    .foregroundColor(HeliColors.greenInk)
            }
            Text(subtitle)
                .font(HeliTypography.body(13))
                .foregroundColor(HeliColors.mutedGray)
        }
    }

    private func calloutNote(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(HeliColors.forestGreen)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(HeliColors.forestGreen)
                Text(text)
                    .font(HeliTypography.body(12.5))
                    .foregroundColor(HeliColors.greenInk)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeliColors.forestTint)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stepRow(step: Int, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(step)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(HeliColors.forestGreen)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(HeliColors.greenInk)
                Text(desc)
                    .font(HeliTypography.body(12.5))
                    .foregroundColor(HeliColors.mutedGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(HeliColors.sageRule.opacity(0.5), lineWidth: 0.8)
        )
    }
}
