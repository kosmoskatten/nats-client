{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric  #-}
module Network.Nats.Subscriber
    ( Subscriber (..)
    , Subscribers
    , NatsMsg (..)
    , JsonMsg (..)
    , MsgQueue (..)
    , SubscriptionId (..)
    , newSubscriptionId
    , empty
    , addSubscriber
    , deleteSubscriber
    , lookupSubscriber
    ) where

import Control.Concurrent.STM (TQueue)
import Control.DeepSeq (NFData)
import Data.Hashable (Hashable (..))
import Data.HashMap.Strict (HashMap)
import GHC.Generics (Generic)
import System.Random (randomRIO)

import qualified Data.HashMap.Strict as HM

import Network.Nats.Types (Topic, Payload)

-- | The different kind of Subscribers.
data Subscriber
    = AsyncSubscriber !(NatsMsg -> IO ())
      -- ^ An asynchronous subscriber where the message is delivered to
      -- an action in a newly created thread.

    | QueueSubscriber !(TQueue NatsMsg)
      -- ^ A synchronous subscriber where the message is delivered to
      -- a concurrent queue.

-- | A HashMap with all registered Subscribers.
type Subscribers = HashMap SubscriptionId Subscriber

-- | A NATS message as presented to the user.
data NatsMsg = NatsMsg !Topic !SubscriptionId !(Maybe Topic) !Payload
    deriving (Eq, Ord, Show)

-- | A NATS message with the payload converted to JSON.
data JsonMsg a = JsonMsg !Topic !SubscriptionId !(Maybe Topic) !(Maybe a)
    deriving (Eq, Ord, Show)

-- | A concurrent queue of pending messages.
newtype MsgQueue = MsgQueue (TQueue NatsMsg)

-- | An identity for a subscription. Generated by random generator when
-- a subscription is made.
newtype SubscriptionId = Sid Int
    deriving (Eq, Generic, NFData, Ord, Show)

-- | SubscriptionId instance for Hashable. Will be used as key
-- in HashMap.
instance Hashable SubscriptionId where
    hash (Sid n)              = hash n
    hashWithSalt salt (Sid n) = hashWithSalt salt n

-- | Generate a new, random, SubscriptionId.
newSubscriptionId :: IO SubscriptionId
newSubscriptionId = Sid <$> randomRIO (1, maxBound)

-- | Create an empty Subscribers HashMap.
empty :: Subscribers
empty = HM.empty

-- | Add a new Subscriber to the HashMap.
addSubscriber :: SubscriptionId -> Subscriber -> Subscribers -> Subscribers
addSubscriber = HM.insert

-- | Delete a Subscriber from the HashMap.
deleteSubscriber :: SubscriptionId -> Subscribers -> Subscribers
deleteSubscriber = HM.delete

-- | Lookup a Subscriber from the Hashmap.
lookupSubscriber :: SubscriptionId -> Subscribers -> Maybe Subscriber
lookupSubscriber = HM.lookup
