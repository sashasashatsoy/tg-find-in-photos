import UIKit

struct Peer: Equatable {
    let id: Int
    let name: String
    let shortName: String
    let colorIndex: Int

    var initials: String {
        let parts = name.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first.map(String.init) }.joined()
    }

    static let me = Peer(id: 1, name: "Alex", shortName: "Alex", colorIndex: 5)
    static let maria = Peer(id: 2, name: "Anita", shortName: "Anita", colorIndex: 6)
}

struct Reaction: Equatable {
    var emoji: String
    var peers: [Peer]
    var count: Int { peers.count }
    var chosenByMe: Bool { peers.contains(Peer.me) }
}

struct Message: Equatable {
    let id: Int
    var authorId: Int
    var text: String
    var date: Date
    var isEdited: Bool = false
    var isRead: Bool = true
    var replyToId: Int?
    var reactions: [Reaction] = []
    /// Key of a `PhotoAsset` for photo messages.
    var photo: String? = nil

    var isOutgoing: Bool { authorId == Peer.me.id }
    var photoAsset: PhotoAsset? { photo.flatMap(PhotoAsset.named) }
}

/// Local, in-memory "server". Messages are stored oldest → newest.
final class ChatStore {
    private(set) var messages: [Message]
    let peer: Peer
    private var nextId: Int

    init(peer: Peer, messages: [Message]) {
        self.peer = peer
        self.messages = messages
        self.nextId = (messages.map(\.id).max() ?? 0) + 1
    }

    func message(id: Int) -> Message? { messages.first { $0.id == id } }

    @discardableResult
    func send(text: String, from author: Peer, replyTo: Int?) -> Message {
        let message = Message(id: nextId, authorId: author.id, text: text, date: Date(), isRead: author.id != Peer.me.id, replyToId: replyTo)
        nextId += 1
        messages.append(message)
        return message
    }

    func edit(id: Int, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text = text
        messages[index].isEdited = true
    }

    func delete(id: Int) {
        messages.removeAll { $0.id == id }
    }

    func markOutgoingRead() {
        for i in messages.indices where messages[i].isOutgoing {
            messages[i].isRead = true
        }
    }

    func toggleReaction(id: Int, emoji: String, by peer: Peer) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        var reactions = messages[index].reactions
        if let existing = reactions.firstIndex(where: { $0.emoji == emoji }) {
            if reactions[existing].peers.contains(peer) {
                reactions[existing].peers.removeAll { $0 == peer }
                if reactions[existing].peers.isEmpty { reactions.remove(at: existing) }
            } else {
                // A peer can keep a single reaction in this prototype, as with non-premium users.
                reactions = reactions.compactMap { reaction in
                    var reaction = reaction
                    reaction.peers.removeAll { $0 == peer }
                    return reaction.peers.isEmpty ? nil : reaction
                }
                if let again = reactions.firstIndex(where: { $0.emoji == emoji }) {
                    reactions[again].peers.append(peer)
                } else {
                    reactions.append(Reaction(emoji: emoji, peers: [peer]))
                }
            }
        } else {
            reactions = reactions.compactMap { reaction in
                var reaction = reaction
                reaction.peers.removeAll { $0 == peer }
                return reaction.peers.isEmpty ? nil : reaction
            }
            reactions.append(Reaction(emoji: emoji, peers: [peer]))
        }
        messages[index].reactions = reactions
    }

    static func makeDemo() -> ChatStore {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        func at(_ day: Date, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        let me = Peer.me.id
        let her = Peer.maria.id
        var id = 1
        func m(_ author: Int, _ text: String, _ date: Date, edited: Bool = false, reply: Int? = nil, reactions: [Reaction] = []) -> Message {
            defer { id += 1 }
            return Message(id: id, authorId: author, text: text, date: date, isEdited: edited, isRead: true, replyToId: reply, reactions: reactions)
        }
        // Promo story for the burn-to-delete feature: Alex's 2 AM texts, Anita's threat,
        // and a brand-new way to make both disappear. Ids matter for PromoDirector.
        let messages: [Message] = [
            m(her, "How was the date?? Details. Now 👀", at(yesterday, 21, 30)),
            m(me, "Long story. Tomorrow", at(yesterday, 21, 46)),
            m(her, "You can't just leave me like this", at(yesterday, 21, 47), reactions: [Reaction(emoji: "😁", peers: [Peer.me])]),
            m(her, "Hellooo?", at(yesterday, 23, 58)),
            m(me, "u up?", at(today, 2, 13)),
            m(me, "i think i'm becoming a morning person", at(today, 2, 14)),
            m(me, "also i miss my ex's dog. not my ex. the dog", at(today, 2, 15)),
            m(me, "nvm going to bed 😴", at(today, 2, 16)),
            m(her, "WOW. Good morning, morning person ☀️", at(today, 9, 41)),
            m(her, "Screenshotting all of this for the group chat 😂", at(today, 9, 41)),
            m(me, "Bold move. You know Telegram can burn messages now?", at(today, 9, 44)),
            m(me, "Watch 🔥", at(today, 9, 44))
        ]
        return ChatStore(peer: Peer.maria, messages: messages)
    }
}

extension ChatStore {
    /// History for the "describe a photo" search: months of chat with photos scattered through
    /// it, and today Анита asks for the one with Уголёк on the windowsill.
    static func makeRecallDemo() -> ChatStore {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func day(_ daysAgo: Int) -> Date { calendar.date(byAdding: .day, value: -daysAgo, to: today)! }
        func at(_ day: Date, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        let me = Peer.me.id
        let her = Peer.maria.id
        var id = 1
        func m(_ author: Int, _ text: String, _ date: Date, photo: String? = nil, reactions: [Reaction] = []) -> Message {
            defer { id += 1 }
            return Message(id: id, authorId: author, text: text, date: date, isRead: true, reactions: reactions, photo: photo)
        }
        let july = day(136), august = day(115), september = day(83), lateSeptember = day(65)
        let october = day(42), midOctober = day(36), lateOctober = day(28), november = day(16), lastWeek = day(5)
        let messages: [Message] = [
            m(her, "Finally at the sea!! 🌊", at(july, 20, 14)),
            m(her, "", at(july, 20, 15), photo: "sea_sunset"),
            m(me, "So jealous. Bring me back some sunshine", at(july, 20, 31)),
            m(me, "", at(august, 13, 2), photo: "mountains"),
            m(me, "Day 3 of the hike. We made it to the lake", at(august, 13, 3)),
            m(her, "Wow, is that Altai?", at(august, 13, 20)),
            m(me, "Yep. The only signal is up on the pass 📶", at(august, 13, 22)),
            m(her, "Guess who lives with me now", at(september, 19, 40)),
            m(her, "", at(september, 19, 41), photo: "cat_window"),
            m(me, "NO WAY. Is that Lena's kitten?", at(september, 19, 44)),
            m(her, "Yes! His name is Ember 🖤", at(september, 19, 45), reactions: [Reaction(emoji: "❤️", peers: [Peer.me])]),
            m(her, "He sits on the windowsill all evening guarding my roses", at(september, 19, 46)),
            m(me, "Tell him roses are not a snack", at(september, 19, 50)),
            m(me, "", at(lateSeptember, 21, 12), photo: "coffee_window"),
            m(me, "Coffee on the windowsill, deadline at dawn", at(lateSeptember, 21, 12)),
            m(her, "Hang in there! Crunch time here too", at(lateSeptember, 21, 30)),
            m(her, "", at(october, 18, 5), photo: "ginger_kitten"),
            m(her, "Mom got a kitten too. Meet Peach 🍑", at(october, 18, 6)),
            m(me, "Peach is clearly filing a complaint, judging by that paw 😄", at(october, 18, 15)),
            m(me, "", at(midOctober, 12, 30), photo: "fluffy_cat"),
            m(me, "The neighbor's cat comes to sunbathe on our balcony", at(midOctober, 12, 31)),
            m(her, "So fluffy!", at(midOctober, 12, 40)),
            m(me, "", at(lateOctober, 16, 40), photo: "dog_beach"),
            m(me, "Met this guy on the beach. His owner let me pet him", at(lateOctober, 16, 41)),
            m(her, "Gorgeous! What's his name?", at(lateOctober, 16, 55)),
            m(me, "The Count. Very serious dog", at(lateOctober, 16, 57)),
            m(her, "", at(november, 11, 20), photo: "plants_window"),
            m(her, "Bought succulents while Ember was asleep", at(november, 11, 21)),
            m(me, "He will find them. He always finds them", at(november, 11, 40)),
            m(her, "", at(lastWeek, 21, 3), photo: "black_kitten"),
            m(her, "Looking at me like nobody's fed him in a week", at(lastWeek, 21, 4), reactions: [Reaction(emoji: "😁", peers: [Peer.me])]),
            m(me, "Classic Ember", at(lastWeek, 21, 10)),
            m(her, "Remember that photo of Ember, our tiny black cat, on the windowsill his very first day?", at(today, 10, 2)),
            m(her, "Want to show Mom but there are like 400 cat pics in here 🙈", at(today, 10, 2)),
            m(me, "Hold my coffee. I'll just describe it ✨", at(today, 10, 5))
        ]
        return ChatStore(peer: Peer.maria, messages: messages)
    }
}

enum DateFormatting {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let dayHeader: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMMM d"
        return f
    }()

    static func header(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return dayHeader.string(from: date)
    }
}
