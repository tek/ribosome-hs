module Ribosome.Nvim.Api.Data where

import Data.MessagePack (Object(ObjectExt))
import Prelude
import Ribosome.Msgpack.Decode (MsgpackDecode(..))
import Ribosome.Msgpack.Encode (MsgpackEncode(..))

import Ribosome.Nvim.Api.GenerateData (generateData)

generateData
