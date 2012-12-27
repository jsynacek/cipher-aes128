{-# LANGUAGE ForeignFunctionInterface, EmptyDataDecls #-}
module Crypto.Cipher.Internal.AES128
        ( AESKey(..), RawKey(..)
        , generateKey
        , encrypt
        , decrypt
        ) where

import Foreign.Ptr
import Foreign.ForeignPtr
import Foreign.Storable
import Data.Word
import Data.Bits (shiftL, (.|.))

-- AES Bindings
data AESKeyStruct
type AESKeyPtr = Ptr AESKeyStruct
data RawKey = RKey { lowK,highK :: {-# UNPACK #-} !Word64 }
data AESKey = AESKey { rawKey      :: !RawKey
                     , expandedKey :: ForeignPtr AESKeyStruct }

foreign import ccall unsafe "aes/aes.h generate_key128"
        c_generate_key128 :: AESKeyPtr -> Ptr Word8 -> IO ()

foreign import ccall unsafe "aes/aes.h allocate_key128"
        c_allocate_key128 :: IO AESKeyPtr

foreign import ccall unsafe "aes/aes.h &free_key128"
        c_free_key128 :: FunPtr (AESKeyPtr -> IO ())

foreign import ccall unsafe "aes/aes.h encrypt_ecb"
        c_encrypt_ecb :: AESKeyPtr -> Ptr Word8 -> Ptr Word8 -> Word32 -> IO ()

foreign import ccall "aes/aes.h decrypt_ecb"
        c_decrypt_ecb :: AESKeyPtr -> Ptr Word8 -> Ptr Word8 -> Word32 -> IO ()

blkSzC :: Word32
blkSzC = 16

-- Given a 16 byte buffer, allocate and return an AESKey
generateKey :: Ptr Word64 -> IO AESKey
generateKey keyPtr  = do
    k <- c_allocate_key128
    c_generate_key128 k (castPtr keyPtr)
    raw <- do
            a <- peekLE (castPtr keyPtr)
            let keyPtr2 = (castPtr keyPtr) `plusPtr` sizeOf a
            b <- peekLE keyPtr2
            return (RKey a b)
    fmap (AESKey raw) (newForeignPtr c_free_key128 k)
 where
     peekLE p = do
        a1 <- peekElemOff p 0
        a2 <- peekElemOff p 1
        a3 <- peekElemOff p 2
        a4 <- peekElemOff p 3
        a5 <- peekElemOff p 4
        a6 <- peekElemOff p 5
        a7 <- peekElemOff p 6
        a8 <- peekElemOff p 7
        let a = (a1 `shiftL` 56) .|. (a2 `shiftL` 48) .|. (a3 `shiftL` 40) .|.
                (a4 `shiftL` 32) .|. (a5 `shiftL` 24) .|. (a6 `shiftL` 16) .|.
                (a7 `shiftL` 8)  .|. a8
        return a
{-# INLINE generateKey #-}

-- An encrypt function that can handle up to blks < maxBound `div` 16 :: Word32
-- simultaneous blocks.
encrypt :: AESKey -> Ptr Word8 -> Ptr Word8 -> Int -> IO ()
encrypt (AESKey _ k) dst src blks = withForeignPtr k $ \p -> c_encrypt_ecb p dst src (fromIntegral blks)
{-# INLINE encrypt #-}

decrypt :: AESKey -> Ptr Word8 -> Ptr Word8 -> Int -> IO ()
decrypt (AESKey _ k) dst src blks
  | blks > fromIntegral (maxBound `div` blkSzC :: Word32) = error "Can not decrypt so many blocks at once"
  | otherwise = withForeignPtr k $ \p -> c_decrypt_ecb p dst src (fromIntegral blks)

