//
//  BusyBanner.swift
//  ContainerManager
//

import SwiftUI

/// A floating "still working" indicator for operations that run without a sheet.
///
/// Saving or loading an archive writes hundreds of megabytes through a file panel and
/// then returns to the list; with nothing on screen, a long wait is indistinguishable
/// from the action having failed to start.
struct BusyBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.callout)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator))
        .shadow(radius: 8, y: 2)
        .padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityLabel(text)
    }
}
