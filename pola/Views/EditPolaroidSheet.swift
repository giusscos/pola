import SwiftUI

struct EditPolaroidSheet: View {
    @Bindable var entry: PolaroidEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Short note...", text: $entry.caption)
                } header: {
                    Text("Caption (front strip)")
                }

                Section {
                    ZStack(alignment: .topLeading) {
                        if entry.backText.isEmpty {
                            Text("Write something on the back...")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $entry.backText)
                            .frame(minHeight: 90)
                            .scrollContentBackground(.hidden)
                    }
                } header: {
                    Text("Back of polaroid")
                }

                if entry.coordinate != nil {
                    Section {
                        Toggle("Show map on back", isOn: $entry.showMap)
                    } header: {
                        Text("Map")
                    } footer: {
                        Text("Disable to show your note instead of the map.")
                    }
                }
            }
            .navigationTitle("Edit Polaroid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
