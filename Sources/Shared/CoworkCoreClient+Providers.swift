import Foundation

extension CoworkCoreClient {
    /// Refreshes the model catalog for an existing provider row.
    func refreshProviderModels(id: String) async throws -> CoworkFetchModelsResponse {
        struct Empty: Encodable {}
        return try await request("POST", path: "api/providers/\(id)/models", body: Empty())
    }
}
