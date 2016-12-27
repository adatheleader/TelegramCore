import Foundation
#if os(macOS)
    import PostboxMac
    import SwiftSignalKitMac
    import MtProtoKitMac
#else
    import Postbox
    import SwiftSignalKit
    import MtProtoKitDynamic
#endif

final class AccountInitialState {
    let state: AuthorizedAccountState.State
    let peerIds: Set<PeerId>
    let messageIds: Set<MessageId>
    let channelStates: [PeerId: ChannelState]
    let peerNotificationSettings: [PeerId: PeerNotificationSettings]
    let peerIdsWithNewMessages: Set<PeerId>
    let locallyGeneratedMessageTimestamps: [PeerId: [(MessageId.Namespace, Int32)]]
    
    init(state: AuthorizedAccountState.State, peerIds: Set<PeerId>, messageIds: Set<MessageId>, peerIdsWithNewMessages: Set<PeerId>, channelStates: [PeerId: ChannelState], peerNotificationSettings: [PeerId: PeerNotificationSettings], locallyGeneratedMessageTimestamps: [PeerId: [(MessageId.Namespace, Int32)]]) {
        self.state = state
        self.peerIds = peerIds
        self.messageIds = messageIds
        self.channelStates = channelStates
        self.peerIdsWithNewMessages = peerIdsWithNewMessages
        self.peerNotificationSettings = peerNotificationSettings
        self.locallyGeneratedMessageTimestamps = locallyGeneratedMessageTimestamps
    }
}

enum AccountStateMutationOperation {
    case AddMessages([StoreMessage], AddMessagesLocation)
    case DeleteMessagesWithGlobalIds([Int32])
    case DeleteMessages([MessageId])
    case EditMessage(MessageId, StoreMessage)
    case UpdateMedia(MediaId, Media?)
    case ReadInbox(MessageId)
    case ReadOutbox(MessageId)
    case ResetReadState(PeerId, MessageId.Namespace, MessageId.Id, MessageId.Id, MessageId.Id, Int32)
    case UpdateState(AuthorizedAccountState.State)
    case UpdateChannelState(PeerId, ChannelState)
    case UpdatePeerNotificationSettings(PeerId, PeerNotificationSettings)
    case AddHole(MessageId)
    case MergeApiChats([Api.Chat])
    case UpdatePeer(PeerId, (Peer) -> Peer)
    case MergeApiUsers([Api.User])
    case MergePeerPresences([PeerId: PeerPresence])
}

struct AccountMutableState {
    let initialState: AccountInitialState
    let branchOperationIndex: Int
    
    var operations: [AccountStateMutationOperation] = []
    
    var state: AuthorizedAccountState.State
    var peers: [PeerId: Peer]
    var channelStates: [PeerId: ChannelState]
    var peerNotificationSettings: [PeerId: PeerNotificationSettings]
    var storedMessages: Set<MessageId>
    var readInboxMaxIds: [PeerId: MessageId]
    
    var storedMessagesByPeerIdAndTimestamp: [PeerId: Set<MessageIndex>]
    
    var insertedPeers: [PeerId: Peer] = [:]
    
    var preCachedResources: [(MediaResource, Data)] = []
    
    init(initialState: AccountInitialState, initialPeers: [PeerId: Peer], initialStoredMessages: Set<MessageId>, initialReadInboxMaxIds: [PeerId: MessageId], storedMessagesByPeerIdAndTimestamp: [PeerId: Set<MessageIndex>]) {
        self.initialState = initialState
        self.state = initialState.state
        self.peers = initialPeers
        self.storedMessages = initialStoredMessages
        self.readInboxMaxIds = initialReadInboxMaxIds
        self.channelStates = initialState.channelStates
        self.peerNotificationSettings = initialState.peerNotificationSettings
        self.storedMessagesByPeerIdAndTimestamp = storedMessagesByPeerIdAndTimestamp
        self.branchOperationIndex = 0
    }
    
    init(initialState: AccountInitialState, operations: [AccountStateMutationOperation], state: AuthorizedAccountState.State, peers: [PeerId: Peer], channelStates: [PeerId: ChannelState], peerNotificationSettings: [PeerId: PeerNotificationSettings], storedMessages: Set<MessageId>, readInboxMaxIds: [PeerId: MessageId], storedMessagesByPeerIdAndTimestamp: [PeerId: Set<MessageIndex>], branchOperationIndex: Int) {
        self.initialState = initialState
        self.operations = operations
        self.state = state
        self.peers = peers
        self.channelStates = channelStates
        self.storedMessages = storedMessages
        self.peerNotificationSettings = peerNotificationSettings
        self.readInboxMaxIds = readInboxMaxIds
        self.storedMessagesByPeerIdAndTimestamp = storedMessagesByPeerIdAndTimestamp
        self.branchOperationIndex = branchOperationIndex
    }
    
    func branch() -> AccountMutableState {
        return AccountMutableState(initialState: self.initialState, operations: self.operations, state: self.state, peers: self.peers, channelStates: self.channelStates, peerNotificationSettings: self.peerNotificationSettings, storedMessages: self.storedMessages, readInboxMaxIds: self.readInboxMaxIds, storedMessagesByPeerIdAndTimestamp: self.storedMessagesByPeerIdAndTimestamp, branchOperationIndex: self.operations.count)
    }
    
    mutating func merge(_ other: AccountMutableState) {
        for i in other.branchOperationIndex ..< other.operations.count {
            self.addOperation(other.operations[i])
        }
        for (_, peer) in other.insertedPeers {
            self.peers[peer.id] = peer
        }
        self.preCachedResources.append(contentsOf: other.preCachedResources)
    }
    
    mutating func addPreCachedResource(_ resource: MediaResource, data: Data) {
        self.preCachedResources.append((resource, data))
    }
    
    mutating func addMessages(_ messages: [StoreMessage], location: AddMessagesLocation) {
        self.addOperation(.AddMessages(messages, location))
    }
    
    mutating func deleteMessagesWithGlobalIds(_ globalIds: [Int32]) {
        self.addOperation(.DeleteMessagesWithGlobalIds(globalIds))
    }
    
    mutating func deleteMessages(_ messageIds: [MessageId]) {
        self.addOperation(.DeleteMessages(messageIds))
    }
    
    mutating func editMessage(_ id: MessageId, message: StoreMessage) {
        self.addOperation(.EditMessage(id, message))
    }
    
    mutating func updateMedia(_ id: MediaId, media: Media?) {
        self.addOperation(.UpdateMedia(id, media))
    }
    
    mutating func readInbox(_ messageId: MessageId) {
        self.addOperation(.ReadInbox(messageId))
    }
    
    mutating func readOutbox(_ messageId: MessageId) {
        self.addOperation(.ReadOutbox(messageId))
    }
    
    mutating func resetReadState(_ peerId: PeerId, namespace: MessageId.Namespace, maxIncomingReadId: MessageId.Id, maxOutgoingReadId: MessageId.Id, maxKnownId: MessageId.Id, count: Int32) {
        self.addOperation(.ResetReadState(peerId, namespace, maxIncomingReadId, maxOutgoingReadId, maxKnownId, count))
    }
    
    mutating func updateState(_ state: AuthorizedAccountState.State) {
        self.addOperation(.UpdateState(state))
    }
    
    mutating func updateChannelState(_ peerId: PeerId, state: ChannelState) {
        self.addOperation(.UpdateChannelState(peerId, state))
    }
    
    mutating func updatePeerNotificationSettings(_ peerId: PeerId, notificationSettings: PeerNotificationSettings) {
        self.addOperation(.UpdatePeerNotificationSettings(peerId, notificationSettings))
    }
    
    mutating func addHole(_ messageId: MessageId) {
        self.addOperation(.AddHole(messageId))
    }
    
    mutating func mergeChats(_ chats: [Api.Chat]) {
        self.addOperation(.MergeApiChats(chats))
    }
    
    mutating func updatePeer(_ id: PeerId, _ f: @escaping (Peer) -> Peer) {
        self.addOperation(.UpdatePeer(id, f))
    }
    
    mutating func mergeUsers(_ users: [Api.User]) {
        self.addOperation(.MergeApiUsers(users))
        
        var presences: [PeerId: PeerPresence] = [:]
        for user in users {
            switch user {
            case let .user(_, id, _, _, _, _, _, _, status, _, _, _):
                if let status = status {
                    presences[PeerId(namespace: Namespaces.Peer.CloudUser, id: id)] = TelegramUserPresence(apiStatus: status)
                }
                break
            case .userEmpty:
                break
            }
        }
        if !presences.isEmpty {
            self.addOperation(.MergePeerPresences(presences))
        }
    }
    
    mutating func mergePeerPresences(_ presences: [PeerId: PeerPresence]) {
        self.addOperation(.MergePeerPresences(presences))
    }
    
    mutating func addOperation(_ operation: AccountStateMutationOperation) {
        switch operation {
            case .AddHole, .DeleteMessages, .DeleteMessagesWithGlobalIds, .EditMessage, .UpdateMedia, .ReadOutbox, .MergePeerPresences:
                break
            case let .AddMessages(messages, _):
                for message in messages {
                    if case let .Id(id) = message.id {
                        self.storedMessages.insert(id)
                    }
                }
            case let .UpdateState(state):
                self.state = state
            case let .UpdateChannelState(peerId, channelState):
                self.channelStates[peerId] = channelState
            case let .UpdatePeerNotificationSettings(peerId, notificationSettings):
                self.peerNotificationSettings[peerId] = notificationSettings
            case let .MergeApiChats(chats):
                for chat in chats {
                    if let groupOrChannel = mergeGroupOrChannel(lhs: peers[chat.peerId], rhs: chat) {
                        peers[groupOrChannel.id] = groupOrChannel
                        insertedPeers[groupOrChannel.id] = groupOrChannel
                    }
                }
            case let .MergeApiUsers(users):
                for apiUser in users {
                    if let user = TelegramUser.merge(peers[apiUser.peerId] as? TelegramUser, rhs: apiUser) {
                        peers[user.id] = user
                        insertedPeers[user.id] = user
                    }
                }
            case let .UpdatePeer(id, f):
                if let peer = self.peers[id] {
                    let updatedPeer = f(peer)
                    peers[id] = updatedPeer
                    insertedPeers[id] = updatedPeer
                }
            case let .ReadInbox(messageId):
                let current = self.readInboxMaxIds[messageId.peerId]
                if current == nil || current! < messageId {
                    self.readInboxMaxIds[messageId.peerId] = messageId
                }
            //namespace: MessageId.Namespace, maxIncomingReadId: MessageId.Id, maxOutgoingReadId: MessageId.Id, maxKnownId: MessageId.Id, count: Int32
            case let .ResetReadState(peerId, namespace, maxIncomingReadId, _, _, _):
                let current = self.readInboxMaxIds[peerId]
                if namespace == Namespaces.Message.Cloud {
                    if current == nil || current!.id < maxIncomingReadId {
                        self.readInboxMaxIds[peerId] = MessageId(peerId: peerId, namespace: namespace, id: maxIncomingReadId)
                    }
                }
        }
        
        self.operations.append(operation)
    }
}

struct AccountFinalState {
    let state: AccountMutableState
    let shouldPoll: Bool
    let incomplete: Bool
}

struct AccountFinalStateEvents {
    let addedIncomingMessageIds: [MessageId]
    
    var isEmpty: Bool {
        return self.addedIncomingMessageIds.isEmpty
    }
    
    init() {
        self.addedIncomingMessageIds = []
    }
    
    init(addedIncomingMessageIds: [MessageId]) {
        self.addedIncomingMessageIds = addedIncomingMessageIds
    }
    
    init(state: AccountMutableState) {
        var addedIncomingMessageIds: [MessageId] = []
        for operation in state.operations {
            switch operation {
                case let .AddMessages(messages, location):
                    if case .UpperHistoryBlock = location {
                        for message in messages {
                            if case let .Id(id) = message.id, message.flags.contains(.Incoming) {
                                addedIncomingMessageIds.append(id)
                            }
                        }
                    }
                default:
                    break
            }
        }
        self.addedIncomingMessageIds = addedIncomingMessageIds
    }
    
    
    func union(with other: AccountFinalStateEvents) -> AccountFinalStateEvents {
        return AccountFinalStateEvents(addedIncomingMessageIds: self.addedIncomingMessageIds + other.addedIncomingMessageIds)
    }
}