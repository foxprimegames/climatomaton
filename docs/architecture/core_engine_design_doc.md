You have a sharp eye. There is absolutely no reason for that connection to exist, and logically, it doesn't.

That was a formatting error in my ASCII diagram. I drew a stray vertical line `│` down the right side of the diagram that inadvertently linked the top broker all the way down to the `OutboxIPCWorker`.

As stated in the text definition for the `OutboxIPCWorker`: *"Operates completely independently of the internal broker's topics."* It should not be subscribed to `bot/inbound_traffic`, nor should it be connected to the `InternalEventBroker` at all. Its only trigger is the host OS filesystem.

Here is the corrected diagram with that confusing visual typo removed, accurately reflecting the true isolation of the outbox worker:

```text
[Discord Network]
       │ (WebSocket)
       ▼
┌──────────────────────────────┐
│   DiscordGatewayConnector    │
└──────────────┬───────────────┘
               │ (Publish)
               ▼ Topic: bot/inbound_traffic
 🔔  [InternalEventBroker] 🔔
       │               │
       │ (Subscribe)   │ (Subscribe)                  
       ▼               ▼                              
┌──────────────┐┌──────────────┐                      
│ProposalFilter││CommandIngest │                      
│    Engine    ││   Wrapper    │                      
└──────┬───────┘└──────┬───────┘                      
       │               │                              
       │ (Publish)     │ (Publish)                    
       │ engine/       │ engine/                      
       │ proposals     │ commands                     
       ▼               ▼                              
 🔔  [InternalEventBroker] 🔔                         
               │                                      
               │ (Subscribe - Prefetch 1)             
               ▼                                      
┌──────────────────────────────┐                      
│      TransactionManager      │                      
└──────────────┬───────────────┘                      
               │ (Publish) Topic: engine/state_mutation
               ▼                                      
 🔔  [InternalEventBroker] 🔔                         
               │                                      
               ▼ (Subscribe)                                  
┌──────────────────────────────┐              ┌──────────────────────────────┐
│    NotificationDiskWriter    │              │        OutboxIPCWorker       │
└──────────────┬───────────────┘              └──────────────┬───────────────┘
               │ (Atomic Write)                              │ (Poll)
               ▼                                             ▼
       [Shared Volume: outbox/] ◄────────────────────────────┘
               │
               ▼ (Stateless POST)
        [Discord REST API]

```

Good catch. The data object boundaries and isolated lifecycles remain exactly as described in the text, and the visual now actually matches the architecture.
