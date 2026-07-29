import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    let onStart: () -> Void
    let onOpenSample: (SampleRoom) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                header
                hero
                inspiration
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 42)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.greeting)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)
                Text("Canvas")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
            }
            Spacer()
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(AppTheme.accent)
                .accessibilityLabel("Profile")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 24) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [Color(hex: "D9D0C3"), Color(hex: "A8B09D")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                    Text("Imagine your room,\nbeautifully rethought.")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .tracking(-1.1)
                }
                .foregroundStyle(.white)
                .padding(26)

                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 110, height: 62)
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 74, height: 74)
                }
                .rotationEffect(.degrees(-8))
                .offset(x: 230, y: -84)
            }
            .frame(height: 310)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

            PrimaryButton(
                title: "Design a room",
                systemImage: "arrow.up.right",
                action: onStart
            )
        }
    }

    private var inspiration: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Explore spaces")
                    .font(.title3.weight(.bold))
                Spacer()
                Text("Sample scenes")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryInk)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(viewModel.featuredRooms) { room in
                        Button {
                            onOpenSample(room)
                        } label: {
                            VStack(alignment: .leading, spacing: 18) {
                                Image(systemName: room.systemImage)
                                    .font(.title2)
                                    .foregroundStyle(Color(hex: room.accentHex))
                                Spacer()
                                Text(room.name)
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.ink)
                                Text(room.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryInk)
                            }
                            .padding(20)
                            .frame(width: 210, height: 180, alignment: .leading)
                            .premiumCard(cornerRadius: 24)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        }
    }
}

