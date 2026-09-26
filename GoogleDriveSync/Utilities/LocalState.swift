//
//  LocalState.swift
//  GoogleDriveSync
//
//  Created by Pair Programming on 2026-09-25.
//

import SwiftUI

/// A clean property wrapper providing dynamic local state compatible with macOS Command Line Tools
/// without requiring Xcode-bundled SwiftUIMacros.
@propertyWrapper
struct LocalState<Value>: DynamicProperty {
    @StateObject private var storage: Storage
    
    final class Storage: ObservableObject {
        @Published var value: Value
        init(_ value: Value) {
            self.value = value
        }
    }
    
    init(wrappedValue: Value) {
        _storage = StateObject(wrappedValue: Storage(wrappedValue))
    }
    
    var wrappedValue: Value {
        get { storage.value }
        nonmutating set { storage.value = newValue }
    }
    
    var projectedValue: Binding<Value> {
        Binding(
            get: { self.storage.value },
            set: { self.storage.value = $0 }
        )
    }
}
