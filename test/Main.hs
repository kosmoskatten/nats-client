module Main 
    ( main
    ) where

import Test.Framework (Test, defaultMain, testGroup)
import Test.Framework.Providers.HUnit (testCase)
import Test.Framework.Providers.QuickCheck2 (testProperty)

import Network.NatsTests ( asyncSubscribeSingleMsg
                         , asyncSubscribeSingleJsonMsg
                         , syncSubscribeSingleMsg
                         , syncSubscribeSingleJsonMsg
                         , syncSubscribeSeveralMsgWithTmo
                         , syncSubscribeSeveralJsonMsgWithTmo
                         , unsubscribe
                         )
import Network.Nats.MessageProps (encodeDecodeMessage)

main :: IO ()
main = defaultMain testSuite

testSuite ::  [Test]
testSuite =
    [ testGroup "Message property tests"
        [ testProperty "Encoding and decoding of Message"
                       encodeDecodeMessage
        ]
    , testGroup "Client tests (using real server)"
        [ testCase "Successfully subscribe and receive one async msg"
                   asyncSubscribeSingleMsg
        , testCase "Successfully subscribe and receive one async JSON msg"
                   asyncSubscribeSingleJsonMsg
        , testCase "Successfully subscribe and receive one sync msg"
                   syncSubscribeSingleMsg
        , testCase "Successfully subscribe and receive one sync JSON msg"
                   syncSubscribeSingleJsonMsg
        , testCase "Successfully subscribe and receive several sync msg"
                   syncSubscribeSeveralMsgWithTmo
        , testCase "Successfully subscribe and receive several JSON msg"
                   syncSubscribeSeveralJsonMsgWithTmo
        , testCase "Successfully unsubscribe from a topic"
                   unsubscribe
        ]
    ]
