{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE TypeOperators #-}

module Ribosome.Msgpack.Encode(
  MsgpackEncode(..),
) where

import Data.Bifunctor (bimap)
import Data.ByteString (ByteString)
import Data.Int (Int64)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map (fromList, toList)
import Data.MessagePack (Object(..))
import GHC.Generics (
  C1,
  Constructor,
  D1,
  Generic,
  K1(..),
  M1(..),
  Rep,
  S1,
  Selector,
  conIsRecord,
  from,
  selName,
  (:*:)(..),
  )
import qualified Ribosome.Msgpack.Util as Util (assembleMap, string)

class MsgpackEncode a where
  toMsgpack :: a -> Object
  default toMsgpack :: (Generic a, GMsgpackEncode (Rep a)) => a -> Object
  toMsgpack = gMsgpackEncode . from

class GMsgpackEncode f where
  gMsgpackEncode :: f a -> Object

class MsgpackEncodeProd f where
  msgpackEncodeRecord :: f a -> [(String, Object)]
  msgpackEncodeProd :: f a -> [Object]

instance GMsgpackEncode f => GMsgpackEncode (D1 c f) where
  gMsgpackEncode = gMsgpackEncode . unM1

prodOrNewtype :: MsgpackEncodeProd f => f a -> Object
prodOrNewtype =
  wrap . msgpackEncodeProd
  where
    wrap [a] = a
    wrap as = ObjectArray as

instance (Constructor c, MsgpackEncodeProd f) => GMsgpackEncode (C1 c f) where
  gMsgpackEncode c =
    f $ unM1 c
    where
      f = if conIsRecord c then Util.assembleMap . msgpackEncodeRecord else prodOrNewtype

instance (MsgpackEncodeProd f, MsgpackEncodeProd g) => MsgpackEncodeProd (f :*: g) where
  msgpackEncodeRecord (f :*: g) = msgpackEncodeRecord f ++ msgpackEncodeRecord g
  msgpackEncodeProd (f :*: g) = msgpackEncodeProd f ++ msgpackEncodeProd g

instance (Selector s, GMsgpackEncode f) => MsgpackEncodeProd (S1 s f) where
  msgpackEncodeRecord s@(M1 f) = [(selName s, gMsgpackEncode f)]
  msgpackEncodeProd (M1 f) = [gMsgpackEncode f]

instance MsgpackEncode a => GMsgpackEncode (K1 i a) where
  gMsgpackEncode = toMsgpack . unK1

instance (Ord k, MsgpackEncode k, MsgpackEncode v) => MsgpackEncode (Map k v) where
  toMsgpack = ObjectMap . Map.fromList . fmap (bimap toMsgpack toMsgpack) . Map.toList

instance MsgpackEncode Int where
  toMsgpack = ObjectInt . fromIntegral

instance MsgpackEncode Int64 where
  toMsgpack = ObjectInt . fromIntegral

instance {-# OVERLAPPING #-} MsgpackEncode String where
  toMsgpack = Util.string

instance {-# OVERLAPPABLE #-} MsgpackEncode a => MsgpackEncode [a] where
  toMsgpack = ObjectArray . fmap toMsgpack

instance MsgpackEncode a => MsgpackEncode (Maybe a) where
  toMsgpack = maybe ObjectNil toMsgpack

instance MsgpackEncode Bool where
  toMsgpack = ObjectBool

instance MsgpackEncode () where
  toMsgpack _ = ObjectNil

instance MsgpackEncode Object where
  toMsgpack = id

instance MsgpackEncode ByteString where
  toMsgpack = ObjectString

instance (MsgpackEncode a, MsgpackEncode b) => MsgpackEncode (a, b) where
  toMsgpack (a, b) = ObjectArray [toMsgpack a, toMsgpack b]