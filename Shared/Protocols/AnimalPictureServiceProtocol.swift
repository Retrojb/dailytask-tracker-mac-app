import Foundation

struct AnimalImage {
    let url: URL
    let imageData: Data
}

protocol AnimalPictureServiceProtocol {
    func fetchRandomAnimalImage() async throws -> AnimalImage
}
