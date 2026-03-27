import Foundation

enum BackendClientError: Error, LocalizedError {
    case backendNotConfigured
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .backendNotConfigured:
            return "Supabase backend is not configured."
        case .invalidResponse:
            return "The backend returned an invalid response."
        }
    }
}

struct SupabaseEdgeFunctionClient: Sendable {
    private let configuration: AppConfiguration
    private let session: URLSession

    init(configuration: AppConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func invoke<Request: Encodable, Response: Decodable>(
        path: String,
        body: Request,
        responseType: Response.Type = Response.self
    ) async throws -> Response {
        guard
            let baseURL = configuration.supabaseURL,
            !configuration.supabaseAnonKey.isEmpty
        else {
            throw BackendClientError.backendNotConfigured
        }

        let url = baseURL
            .appending(path: "functions")
            .appending(path: "v1")
            .appending(path: path)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(configuration.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder.taskAppEncoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw BackendClientError.invalidResponse
        }

        if Response.self == EmptyResponse.self, data.isEmpty {
            return EmptyResponse() as! Response
        }

        return try JSONDecoder.taskAppDecoder.decode(Response.self, from: data)
    }
}

// Note: EmptyResponse is also defined in TodosAPIClient — use that one for new code.
private struct SupabaseEmptyResponse: Codable, Sendable {}

enum JSONEncoderFactory {}

extension JSONEncoder {
    static var taskAppEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var taskAppDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
