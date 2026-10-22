import Foundation
import Combine

/// Manages autosaving and loading of Recent Wireframes on the iPhone's local persistent storage.
final class StorageManager: ObservableObject {
    static let shared = StorageManager()
    
    @Published private(set) var wireframes: [SavedWireframe] = []
    
    private let fileName = "SavedWireframes.json"
    
    private var storageURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(fileName)
    }
    
    private init() {
        loadAll()
    }
    
    func loadAll() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            wireframes = []
            return
        }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoded = try JSONDecoder().decode([SavedWireframe].self, from: data)
            wireframes = decoded.sorted(by: { $0.createdAt > $1.createdAt })
        } catch {
            print("StorageManager load error: \(error)")
            wireframes = []
        }
    }
    
    /// Autosaves a newly calculated wireframe (after the user enters the Customer Name) and generates its `.dxf` file immediately.
    @discardableResult
    func saveWireframe(_ wireframe: SavedWireframe) -> SavedWireframe {
        var list = wireframes
        if let existingIdx = list.firstIndex(where: { $0.id == wireframe.id }) {
            list[existingIdx] = wireframe
        } else {
            list.insert(wireframe, at: 0)
        }
        wireframes = list
        persist()
        
        // Also pre-generate the .dxf file so it's immediately ready for WhatsApp / Files
        _ = try? DXFGenerator.exportDXFFile(for: wireframe)
        return wireframe
    }
    
    func deleteWireframe(at offsets: IndexSet) {
        wireframes.remove(atOffsets: offsets)
        persist()
    }
    
    func deleteWireframe(_ item: SavedWireframe) {
        wireframes.removeAll { $0.id == item.id }
        persist()
    }
    
    private func persist() {
        do {
            let data = try JSONEncoder().encode(wireframes)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("StorageManager save error: \(error)")
        }
    }
}
