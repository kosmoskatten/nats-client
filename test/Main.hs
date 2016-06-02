module Main 
    ( main
    ) where

import Test.Framework (Test, defaultMain, testGroup)
import Test.Framework.Providers.HUnit (testCase)
import Test.Framework.Providers.QuickCheck2 (testProperty)

import Network.NatsTests ( asyncSubscribeSingleMsg
                         , syncSubscribeSingleMsg
                         , syncSubscribeSeveralMsgWithTmo
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
        [ testCase "Successfully subscribe and receive one async msgs"
                   asyncSubscribeSingleMsg
        , testCase "Successfully subscribe and receive one sync msgs"
                   syncSubscribeSingleMsg
        , testCase "Successfully subscribe and receive several sync msgs"
                   syncSubscribeSeveralMsgWithTmo
        ]
    ]
