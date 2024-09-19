{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Cardano.Wallet.UI.Deposit.Html.Pages.Wallet
where

import Prelude

import Cardano.Address.Derivation
    ( XPub
    , xpubToBytes
    )
import Cardano.Wallet.Deposit.IO
    ( WalletPublicIdentity (..)
    )
import Cardano.Wallet.Deposit.REST
    ( ErrDatabase
    )
import Cardano.Wallet.UI.Common.API
    ( Visible (..)
    )
import Cardano.Wallet.UI.Common.Html.Htmx
    ( hxDelete_
    , hxSwap_
    )
import Cardano.Wallet.UI.Common.Html.Lib
    ( dataBsDismiss_
    , linkText
    )
import Cardano.Wallet.UI.Common.Html.Modal
    ( ModalData (..)
    , mkModal
    , mkModalButton
    )
import Cardano.Wallet.UI.Common.Html.Pages.Lib
    ( copyButton
    , record
    , simpleField
    , sseH
    )
import Cardano.Wallet.UI.Common.Html.Pages.Wallet
    ( PostWalletConfig (..)
    , newWalletFromMnemonicH
    , newWalletFromXPubH
    )
import Cardano.Wallet.UI.Deposit.API
    ( walletDeleteLink
    , walletDeleteModalLink
    , walletLink
    , walletMnemonicLink
    , walletPostMnemonicLink
    , walletPostXPubLink
    )
import Cardano.Wallet.UI.Type
    ( WHtml
    , WalletType (..)
    , runWHtml
    )
import Control.Exception
    ( SomeException
    )
import Data.ByteArray.Encoding
    ( Base (..)
    , convertToBase
    )
import Data.ByteString
    ( ByteString
    )
import Data.Text
    ( Text
    )
import Data.Text.Class
    ( ToText (..)
    )
import Lucid
    ( Html
    , HtmlT
    , ToHtml (..)
    , button_
    , class_
    , div_
    , hidden_
    , hr_
    , id_
    , p_
    , section_
    )

import qualified Data.ByteString.Char8 as B8
import qualified Data.ByteString.Lazy.Char8 as BL

data WalletPresent
    = WalletPresent WalletPublicIdentity
    | WalletAbsent
    | WalletFailedToInitialize ErrDatabase
    | WalletVanished SomeException
    | WalletInitializing
    | WalletClosing

instance Show WalletPresent where
    show (WalletPresent x) = "WalletPresent: " <> show x
    show WalletAbsent = "WalletAbsent"
    show (WalletFailedToInitialize _) = "WalletFailedToInitialize"
    show (WalletVanished _) = "WalletVanished"
    show WalletInitializing = "WalletInitializing"
    show WalletClosing = "WalletClosing"

walletH :: WHtml ()
walletH = sseH walletLink "wallet" ["wallet"]

base64 :: ByteString -> ByteString
base64 = convertToBase Base64

pubKeyH :: Monad m => XPub -> HtmlT m ()
pubKeyH xpub = div_ [class_ "row"] $ do
    div_ [id_ "public_key", hidden_ "false"] $ toHtml xpubByteString
    div_ [class_ "col-6"] $ toHtml $ headAndTail 4 $ B8.dropEnd 2 xpubByteString
    div_ [class_ "col-6"]
        $ copyButton "public_key"
  where
    xpubByteString = base64 $ xpubToBytes xpub

headAndTail :: Int -> ByteString -> ByteString
headAndTail n t = B8.take n t <> ".." <> B8.takeEnd n t

deleteWalletButtonH :: Html ()
deleteWalletButtonH =
    mkModalButton
        walletDeleteModalLink
        [class_ "btn btn-danger"]
        "Delete Wallet"

deleteWalletModalH :: Html ()
deleteWalletModalH =
    mkModal
        $ ModalData
            { modalTitle = "Delete Wallet"
            , modalBody = p_ "Are you sure you want to delete this wallet?"
            , modalFooter = do
                button_
                    [ class_ "btn btn-danger"
                    , hxDelete_ $ linkText walletDeleteLink
                    , dataBsDismiss_ "modal"
                    , hxSwap_ "none"
                    ]
                    "Delete Wallet"
                button_
                    [ class_ "btn btn-secondary"
                    , dataBsDismiss_ "modal"
                    ]
                    "Close"
            }

walletElementH :: (BL.ByteString -> Html ()) -> WalletPresent -> Html ()
walletElementH alert = \case
    WalletPresent (WalletPublicIdentity xpub customers) -> do
        record $ do
            simpleField "Public Key" $ pubKeyH xpub
            simpleField "Customer Discovery" $ toHtml $ toText customers
        div_ [class_ "row"] $ do
            div_ [class_ "col"] $ do
                deleteWalletButtonH
            div_ [id_ "delete-result"] mempty
    WalletAbsent -> runWHtml Deposit $ do
        section_
            $ newWalletFromMnemonicH walletMnemonicLink
            $ PostWalletConfig
                { walletDataLink = walletPostMnemonicLink
                , passwordVisibility = Just Hidden
                , responseTarget = "#post-response"
                }
        hr_ mempty
        section_
            $ newWalletFromXPubH
            $ PostWalletConfig
                { walletDataLink = walletPostXPubLink
                , passwordVisibility = Just Hidden
                , responseTarget = "#post-response"
                }
        div_ [id_ "post-response"] mempty
    WalletFailedToInitialize err ->
        alert
            $ "Failed to initialize wallet"
                <> BL.pack (show err)
    WalletVanished e -> alert $ "Wallet vanished " <> BL.pack (show e)
    WalletInitializing -> alert "Wallet is initializing"
    WalletClosing -> alert "Wallet is closing"

data BadgeStyle
    = Primary
    | Secondary
    | Success
    | Danger
    | Warning
    | Info
    | Light
    | Dark

renderBadgeStyle :: BadgeStyle -> Text
renderBadgeStyle = \case
    Primary -> "primary"
    Secondary -> "secondary"
    Success -> "success"
    Danger -> "danger"
    Warning -> "warning"
    Info -> "info"
    Light -> "light"
    Dark -> "dark"
