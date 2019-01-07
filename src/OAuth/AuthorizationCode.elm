module OAuth.AuthorizationCode exposing
    ( Authorization, AuthorizationResult(..), AuthorizationSuccess, AuthorizationError, parseCode, makeAuthUrl
    , parseCodeWith
    , Authentication, Credentials, AuthenticationSuccess, AuthenticationError, RequestParts, makeTokenRequest
    , Parsers, defaultParsers, defaultCodeParser, defaultErrorParser, defaultAuthorizationSuccessParser, defaultAuthorizationErrorParser
    , defaultAuthenticationSuccessDecoder, defaultAuthenticationErrorDecoder, defaultExpiresInDecoder, defaultScopeDecoder, lenientScopeDecoder, defaultTokenDecoder, defaultRefreshTokenDecoder, defaultErrorDecoder, defaultErrorDescriptionDecoder, defaultErrorUriDecoder
    )

{-| The authorization code grant type is used to obtain both access
tokens and refresh tokens and is optimized for confidential clients.
Since this is a redirection-based flow, the client must be capable of
interacting with the resource owner's user-agent (typically a web
browser) and capable of receiving incoming requests (via redirection)
from the authorization server.

This is a 3-step process:

  - The client asks for an authorization to the OAuth provider: the user is redirected.
  - The provider redirects the user back and the client parses the request query parameters from the url.
  - The client authenticate itself using the authorization code found in the previous step.

After those steps, the client owns an `access_token` that can be used to authorize any subsequent
request.


## Authorize

@docs Authorization, AuthorizationResult, AuthorizationSuccess, AuthorizationError, parseCode, makeAuthUrl


## Authorize (advanced)

@docs parseCodeWith


## Authenticate

@docs Authentication, Credentials, AuthenticationSuccess, AuthenticationError, RequestParts, makeTokenRequest


## Query Parsers

@docs Parsers, defaultParsers, defaultCodeParser, defaultErrorParser, defaultAuthorizationSuccessParser, defaultAuthorizationErrorParser


## Json Decoders

@docs defaultAuthenticationSuccessDecoder, defaultAuthenticationErrorDecoder, defaultExpiresInDecoder, defaultScopeDecoder, lenientScopeDecoder, defaultTokenDecoder, defaultRefreshTokenDecoder, defaultErrorDecoder, defaultErrorDescriptionDecoder, defaultErrorUriDecoder

-}

import Http
import Internal as Internal exposing (..)
import Json.Decode as Json
import OAuth exposing (ErrorCode, Token, errorCodeFromString)
import Url exposing (Url)
import Url.Builder as Builder
import Url.Parser as Url exposing ((<?>))
import Url.Parser.Query as Query



--
-- Authorize
--


{-| Request configuration for an authorization (Authorization Code & Implicit flows)
-}
type alias Authorization =
    { clientId : String
    , url : Url
    , redirectUri : Url
    , scope : List String
    , state : Maybe String
    }


{-| Describes an OAuth error as a result of an authorization request failure

  - error (_REQUIRED_):
    A single ASCII error code.

  - errorDescription (_OPTIONAL_)
    Human-readable ASCII text providing additional information, used to assist the client developer in
    understanding the error that occurred. Values for the `errorDescription` parameter MUST NOT
    include characters outside the set `%x20-21 / %x23-5B / %x5D-7E`.

  - errorUri (_OPTIONAL_):
    A URI identifying a human-readable web page with information about the error, used to
    provide the client developer with additional information about the error. Values for the
    `errorUri` parameter MUST conform to the URI-reference syntax and thus MUST NOT include
    characters outside the set `%x21 / %x23-5B / %x5D-7E`.

  - state (_REQUIRED if `state` was present in the authorization request_):
    The exact value received from the client

-}
type alias AuthorizationError =
    { error : ErrorCode
    , errorDescription : Maybe String
    , errorUri : Maybe String
    , state : Maybe String
    }


{-| The response obtained as a result of an authorization

  - code (_REQUIRED_):
    The authorization code generated by the authorization server. The authorization code MUST expire
    shortly after it is issued to mitigate the risk of leaks. A maximum authorization code lifetime of
    10 minutes is RECOMMENDED. The client MUST NOT use the authorization code more than once. If an
    authorization code is used more than once, the authorization server MUST deny the request and
    SHOULD revoke (when possible) all tokens previously issued based on that authorization code. The
    authorization code is bound to the client identifier and redirection URI.

  - state (_REQUIRED if `state` was present in the authorization request_):
    The exact value received from the client

-}
type alias AuthorizationSuccess =
    { code : String
    , state : Maybe String
    }


{-| Describes errors coming from attempting to parse a url after an OAuth redirection

  - Empty: means there were nothing (related to OAuth 2.0) to parse
  - Error: a successfully parsed OAuth 2.0 error
  - Success: a successfully parsed the response

-}
type AuthorizationResult
    = Empty
    | Error AuthorizationError
    | Success AuthorizationSuccess


{-| Redirects the resource owner (user) to the resource provider server using the specified
authorization flow.
-}
makeAuthUrl : Authorization -> Url
makeAuthUrl =
    Internal.makeAuthUrl Internal.Code


{-| Parse the location looking for a parameters set by the resource provider server after
redirecting the resource owner (user).

Returns `AuthorizationResult Empty` when there's nothing

-}
parseCode : Url -> AuthorizationResult
parseCode =
    parseCodeWith defaultParsers



--
-- Authorize (Advanced)
--


{-| See 'parseToken', but gives you the ability to provide your own custom parsers.
-}
parseCodeWith : Parsers -> Url -> AuthorizationResult
parseCodeWith { codeParser, errorParser, authorizationSuccessParser, authorizationErrorParser } url_ =
    let
        url =
            { url_ | path = "/" }
    in
    case Url.parse (Url.top <?> Query.map2 Tuple.pair codeParser errorParser) url of
        Just ( Just code, _ ) ->
            parseUrlQuery url Empty (Query.map Success <| authorizationSuccessParser code)

        Just ( _, Just error ) ->
            parseUrlQuery url Empty (Query.map Error <| authorizationErrorParser error)

        _ ->
            Empty



--
-- Query Parsers
--


{-| Parsers used in the 'parseCode' function.

  - codeParser: Looks for an 'code' string
  - errorParser: Looks for an 'error' to build a corresponding `ErrorCode`
  - authorizationSuccessParser: Selected when the `tokenParser` succeeded to parse the remaining parts
  - authorizationErrorParser: Selected when the `errorParser` succeeded to parse the remaining parts

-}
type alias Parsers =
    { codeParser : Query.Parser (Maybe String)
    , errorParser : Query.Parser (Maybe ErrorCode)
    , authorizationSuccessParser : String -> Query.Parser AuthorizationSuccess
    , authorizationErrorParser : ErrorCode -> Query.Parser AuthorizationError
    }


{-| Default parsers according to RFC-6749
-}
defaultParsers : Parsers
defaultParsers =
    { codeParser = defaultCodeParser
    , errorParser = defaultErrorParser
    , authorizationSuccessParser = defaultAuthorizationSuccessParser
    , authorizationErrorParser = defaultAuthorizationErrorParser
    }


{-| Default 'code' parser according to RFC-6749
-}
defaultCodeParser : Query.Parser (Maybe String)
defaultCodeParser =
    Query.string "code"


{-| Default 'error' parser according to RFC-6749
-}
defaultErrorParser : Query.Parser (Maybe ErrorCode)
defaultErrorParser =
    errorParser errorCodeFromString


{-| Default response success parser according to RFC-6749
-}
defaultAuthorizationSuccessParser : String -> Query.Parser AuthorizationSuccess
defaultAuthorizationSuccessParser code =
    Query.map (AuthorizationSuccess code)
        stateParser


{-| Default response error parser according to RFC-6749
-}
defaultAuthorizationErrorParser : ErrorCode -> Query.Parser AuthorizationError
defaultAuthorizationErrorParser =
    authorizationErrorParser



--
-- Authenticate
--


{-| Request configuration for an AuthorizationCode authentication

    let authentication =
          { credentials =
              -- Only the clientId is required. Specify a secret
              -- if a Basic OAuth is required by the resource
              -- provider
              { clientId = "<my-client-id>"
              , secret = Nothing
              }
          -- Authorization code from the authorization result
          , code = "<authorization-code>"
          -- Token endpoint of the resource provider
          , url = "<token-endpoint>"
          -- Redirect Uri to your webserver
          , redirectUri = "<my-web-server>"
          }

-}
type alias Authentication =
    { credentials : Credentials
    , code : String
    , redirectUri : Url
    , url : Url
    }


{-| The response obtained as a result of an authentication (implicit or not)

  - token (_REQUIRED_):
    The access token issued by the authorization server.

  - refreshToken (_OPTIONAL_):
    The refresh token, which can be used to obtain new access tokens using the same authorization
    grant as described in [Section 6](https://tools.ietf.org/html/rfc6749#section-6).

  - expiresIn (_RECOMMENDED_):
    The lifetime in seconds of the access token. For example, the value "3600" denotes that the
    access token will expire in one hour from the time the response was generated. If omitted, the
    authorization server SHOULD provide the expiration time via other means or document the default
    value.

  - scope (_OPTIONAL, if identical to the scope requested; otherwise, REQUIRED_):
    The scope of the access token as described by [Section 3.3](https://tools.ietf.org/html/rfc6749#section-3.3).

-}
type alias AuthenticationSuccess =
    { token : Token
    , refreshToken : Maybe Token
    , expiresIn : Maybe Int
    , scope : List String
    }


{-| Describes an OAuth error as a result of a request failure

  - error (_REQUIRED_):
    A single ASCII error code.

  - errorDescription (_OPTIONAL_)
    Human-readable ASCII text providing additional information, used to assist the client developer in
    understanding the error that occurred. Values for the `errorDescription` parameter MUST NOT
    include characters outside the set `%x20-21 / %x23-5B / %x5D-7E`.

  - errorUri (_OPTIONAL_):
    A URI identifying a human-readable web page with information about the error, used to
    provide the client developer with additional information about the error. Values for the
    `errorUri` parameter MUST conform to the URI-reference syntax and thus MUST NOT include
    characters outside the set `%x21 / %x23-5B / %x5D-7E`.

-}
type alias AuthenticationError =
    { error : ErrorCode
    , errorDescription : Maybe String
    , errorUri : Maybe String
    }


{-| Parts required to build a request. This record is given to `Http.request` in order
to create a new request and may be adjusted at will.
-}
type alias RequestParts a =
    { method : String
    , headers : List Http.Header
    , url : String
    , body : Http.Body
    , expect : Http.Expect a
    , timeout : Maybe Float
    , tracker : Maybe String
    }


{-| Describes at least a `clientId` and if define, a complete set of credentials
with the `secret`. The secret is so-to-speak optional and depends on whether the
authorization server you interact with requires a 'Basic' authentication on top of
the authentication request. Provides it if you need to do so.

      { clientId = "<my-client-id>"
      , secret = Just "<my-client-secret>"
      }

-}
type alias Credentials =
    { clientId : String
    , secret : Maybe String
    }


{-| Builds a the request components required to get a token from an authorization code

    let req : Http.Request AuthenticationSuccess
        req = makeTokenRequest authentication funcResultToMsg |> Http.request

-}
makeTokenRequest : Authentication -> (Result Http.Error AuthenticationSuccess -> msg) -> RequestParts msg
makeTokenRequest { credentials, code, url, redirectUri } funcResultToMsg =
    let
        body =
            [ Builder.string "grant_type" "authorization_code"
            , Builder.string "client_id" credentials.clientId
            , Builder.string "redirect_uri" (makeRedirectUri redirectUri)
            , Builder.string "code" code
            ]
                |> Builder.toQuery
                |> String.dropLeft 1

        headers =
            makeHeaders <|
                case credentials.secret of
                    Nothing ->
                        Nothing

                    Just secret ->
                        Just { clientId = credentials.clientId, secret = secret }
    in
    makeRequest url headers body funcResultToMsg



--
-- Json Decoders
--


{-| Json decoder for a positive response. You may provide a custom response decoder using other decoders
from this module, or some of your own craft.
-}
defaultAuthenticationSuccessDecoder : Json.Decoder AuthenticationSuccess
defaultAuthenticationSuccessDecoder =
    Internal.authenticationSuccessDecoder


{-| Json decoder for an errored response.

    case res of
        Err (Http.BadStatus { body }) ->
            case Json.decodeString OAuth.AuthorizationCode.defaultAuthenticationErrorDecoder body of
                Ok { error, errorDescription } ->
                    doSomething

                _ ->
                    parserFailed

        _ ->
            someOtherError

-}
defaultAuthenticationErrorDecoder : Json.Decoder AuthenticationError
defaultAuthenticationErrorDecoder =
    Internal.authenticationErrorDecoder defaultErrorDecoder


{-| Json decoder for an 'expire' timestamp
-}
defaultExpiresInDecoder : Json.Decoder (Maybe Int)
defaultExpiresInDecoder =
    Internal.expiresInDecoder


{-| Json decoder for a 'scope'
-}
defaultScopeDecoder : Json.Decoder (List String)
defaultScopeDecoder =
    Internal.scopeDecoder


{-| Json decoder for a 'scope', allowing comma- or space-separated scopes
-}
lenientScopeDecoder : Json.Decoder (List String)
lenientScopeDecoder =
    Internal.lenientScopeDecoder


{-| Json decoder for an 'access\_token'
-}
defaultTokenDecoder : Json.Decoder Token
defaultTokenDecoder =
    Internal.tokenDecoder


{-| Json decoder for a 'refresh\_token'
-}
defaultRefreshTokenDecoder : Json.Decoder (Maybe Token)
defaultRefreshTokenDecoder =
    Internal.refreshTokenDecoder


{-| Json decoder for 'error' field
-}
defaultErrorDecoder : Json.Decoder ErrorCode
defaultErrorDecoder =
    Internal.errorDecoder errorCodeFromString


{-| Json decoder for 'error\_description' field
-}
defaultErrorDescriptionDecoder : Json.Decoder (Maybe String)
defaultErrorDescriptionDecoder =
    Internal.errorDescriptionDecoder


{-| Json decoder for 'error\_uri' field
-}
defaultErrorUriDecoder : Json.Decoder (Maybe String)
defaultErrorUriDecoder =
    Internal.errorUriDecoder
