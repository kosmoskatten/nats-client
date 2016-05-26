module Main where

import Test.Framework (Test, defaultMain, testGroup)
import Test.Framework.Providers.QuickCheck2 (testProperty)

import Network.Nats.MessageProps (encodeDecodeMessage)

main :: IO ()
main = defaultMain testSuite

testSuite ::  [Test]
testSuite =
    [ testGroup "Message property tests"
        [ testProperty "Encoding and decoding of Message"
                       encodeDecodeMessage
        ]
    ]
