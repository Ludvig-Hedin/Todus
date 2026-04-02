import Foundation
import Observation

// MARK: - API Response Types

struct MeetingItem: Identifiable, Decodable, Sendable {
    let id: String
    let title: String
    let meetUrl: String
    let startsAt: Date
    let endsAt: Date?
    let status: String
    let aiSummary: String?
    let actionItems: [MeetingActionItem]?
    let recallBotId: String?
    let errorMessage: String?
}

struct MeetingActionItem: Decodable, Sendable {
    let task: String
    let owner: String?
    let dueDate: String?
}

struct MeetingTranscriptSegment: Identifiable, Decodable, Sendable {
    let id: String
    let startTime: Int
    let endTime: Int?
    let speakerName: String
    let text: String
}

struct MeetingMediaItem: Decodable, Sendable {
    let id: String
    let mediaType: String
    let url: String
}

struct MeetingDetailResponse: Decodable {
    let id: String
    let title: String
    let meetUrl: String
    let startsAt: Date
    let endsAt: Date?
    let status: String
    let aiSummary: String?
    let actionItems: [MeetingActionItem]?
    let recallBotId: String?
    let errorMessage: String?
    let media: [MeetingMediaItem]?
    let transcript: [MeetingTranscriptSegment]?
}

private struct MeetingsListResponse: Decodable {
    let meetings: [MeetingItem]
    let total: Int
}

private struct SyncResponse: Decodable {
    let synced: Int
    let created: Int
    let updated: Int
}

private struct ScheduleBotResponse: Decodable {
    let success: Bool
    let botId: String
}

struct GenerateSummaryResponse: Decodable {
    let summary: String
    let actionItems: [MeetingActionItem]
}

private struct AskQuestionResponse: Decodable {
    let answer: String
}

private struct DeleteResponse: Decodable {
    let success: Bool
}

// MARK: - Service

@MainActor
@Observable
final class MeetingsService {
    private let apiClient: TodosAPIClient

    var meetings: [MeetingItem] = []
    var isLoading = false
    var isSyncing = false
    var loadError: String? = nil

    init(apiClient: TodosAPIClient) {
        self.apiClient = apiClient
    }

    func loadMeetings(status: String? = nil, search: String? = nil) async {
        isLoading = true
        defer { isLoading = false }

        struct Input: Encodable {
            let status: String?
            let search: String?
            let limit: Int
        }

        do {
            let response: MeetingsListResponse = try await apiClient.trpcQuery(
                "meet.listMeetings",
                input: Input(status: status, search: search, limit: 100)
            )
            meetings = response.meetings
            loadError = nil
        } catch {
            print("[MeetingsService] Failed to load meetings: \(error)")
            loadError = error.localizedDescription
        }
    }

    func getMeeting(id: String) async -> MeetingDetailResponse? {
        struct Input: Encodable { let meetingId: String }
        do {
            return try await apiClient.trpcQuery("meet.getMeeting", input: Input(meetingId: id))
        } catch {
            print("[MeetingsService] Failed to get meeting: \(error)")
            return nil
        }
    }

    func syncFromCalendar() async {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let _: SyncResponse = try await apiClient.trpcMutation("meet.syncFromCalendar")
            await loadMeetings()
        } catch {
            print("[MeetingsService] Failed to sync: \(error)")
        }
    }

    func scheduleBot(meetingId: String) async -> Bool {
        struct Input: Encodable { let meetingId: String }
        do {
            let _: ScheduleBotResponse = try await apiClient.trpcMutation(
                "meet.scheduleBot", input: Input(meetingId: meetingId)
            )
            await loadMeetings()
            return true
        } catch {
            print("[MeetingsService] Failed to schedule bot: \(error)")
            return false
        }
    }

    func generateSummary(meetingId: String) async -> GenerateSummaryResponse? {
        struct Input: Encodable { let meetingId: String }
        do {
            return try await apiClient.trpcMutation(
                "meet.generateSummary", input: Input(meetingId: meetingId)
            )
        } catch {
            print("[MeetingsService] Failed to generate summary: \(error)")
            return nil
        }
    }

    func askQuestion(meetingId: String, question: String) async -> String? {
        struct Input: Encodable { let meetingId: String; let question: String }
        do {
            let response: AskQuestionResponse = try await apiClient.trpcMutation(
                "meet.askQuestion", input: Input(meetingId: meetingId, question: question)
            )
            return response.answer
        } catch {
            print("[MeetingsService] Failed to ask: \(error)")
            return nil
        }
    }
}
