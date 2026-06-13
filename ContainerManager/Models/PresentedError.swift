//
//  PresentedError.swift
//  ContainerManager
//

import ContainerizationError
import Foundation
import SwiftUI

/// An error unwrapped into a title and message suitable for an alert.
struct PresentedError: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    init(title: String, error: any Error) {
        self.title = title
        self.message = Self.describe(error)
    }

    /// Extracts the most readable message an error has to offer.
    static func describe(_ error: any Error) -> String {
        if let containerError = error as? ContainerizationError {
            // The client wraps the underlying failure, which carries the useful message.
            if let cause = containerError.cause as? ContainerizationError {
                return "\(containerError.message): \(cause.message)"
            }
            return containerError.message
        }
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return String(describing: error)
    }
}

extension View {
    /// Presents an alert whenever the bound error becomes non-nil.
    func errorAlert(_ error: Binding<PresentedError?>) -> some View {
        alert(
            error.wrappedValue?.title ?? "Error",
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { if !$0 { error.wrappedValue = nil } }
            ),
            presenting: error.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { presented in
            Text(presented.message)
        }
    }
}
