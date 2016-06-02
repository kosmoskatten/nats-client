module Main 
    ( main
    ) where

import Test.Framework (Test, defaultMain, testGroup)
import Test.Framework.Providers.HUnit (testCase)
import Test.Framework.Providers.QuickCheck2 (testProperty)

import Network.NatsTests ( asyncSubscribeSingleMsg
                         , syncSubscribeSingleMsg
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
        [ testCase "Successfully subscribe and receive one async message"
                   asyncSubscribeSingleMsg
        , testCase "Successfully subscribe and receive one sync message"
                   syncSubscribeSingleMsg
        ]
    ]
