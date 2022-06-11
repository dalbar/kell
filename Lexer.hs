module Lexer
( lexer,
  getDollarExp,
  quoteEsc,
  quote
) where
import Text.Parsec
-- TODO No proper wchar support
import Text.Parsec.String (Parser)
import Data.Stack 
data Token = Word String
  -- operators as in https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#:~:text=command%20is%20parsed.-,2.10.2,-Shell%20Grammar%20Rules
  | AND_IF   -- &&
  | OR_IF    -- ||
  | DSEMI    -- ;;
  | DLESS    -- <<
  | DGREAT   -- >>
  | LESSAND  -- <&
  | GREATAND -- >&
  | LESSGREAT-- <>
  | DLESSDASH-- <<-
  | CLOBBER  -- >|
  | If       -- if
  | Then     -- then
  | Else     -- else
  | Elif     -- elif
  | Fi       -- fi
  | Do       -- do
  | Done     -- done
  | Case     -- case
  | Esac     -- esac
  | While    -- while
  | Until    -- until
  | For      -- for
  -- other control operators as in https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap03.html#tag_03_113
  | Ampersand
  | LBracket
  | RBracket
  | SEMI
  | PIPE
  | NEWLINE
  | EOF
  deriving (Show, Eq)

parseReservedOp :: Parser Token
parseReservedOp = foldl1 (<|>) ((\(a,b)-> try $ string a >> ( return b) ) <$> reservedOps) 
  where reservedOps=[("&&",    AND_IF)
                    ,("||",    OR_IF)
                    ,(";;",    DSEMI)
                    ,("<<",    DLESS)
                    ,(">>",    DGREAT)
                    ,("<&",    LESSAND)
                    ,(">&",    GREATAND)
                    ,("<>",    LESSGREAT)
                    ,("<<-",   DLESSDASH)
                    ,(">|",    CLOBBER)
                    ,("if",    If)
                    ,("then",  Then)
                    ,("else",  Else)
                    ,("elif",  Elif)
                    ,("fi",    Fi)
                    ,("done",  Done)
                    ,("do",    Do)
                    ,("case",  Case)
                    ,("esac",  Esac)
                    ,("while", While)
                    ,("until", Until)
                    ,("for",   For)
                    ,("(",     LBracket)
                    ,(")",     RBracket)
                    ,(";",     SEMI)
                    ,("|",     PIPE)]


quoteEsc :: String -> Parser String -> Parser String
quoteEsc escIdents endCondition = let eofA = (eof >> unexpected("mising quote end") )
                                      escape c = (char c >> (eofA <|> (++) . (:[]) <$> anyChar <*> quoteEsc escIdents endCondition) ) in eofA <|> endCondition
            <|> foldl1 (<|>) ( escape <$> escIdents )
            <|> ( (++) . (:[]) <$> anyChar <*> (quoteEsc escIdents endCondition) )

quote :: Parser String -> Parser String
quote = quoteEsc "\\"

getDollarExp :: (String -> String) -> Stack String -> Parser String
getDollarExp f s = (foldl1 (<|>) (stackHandler <$> stackAction s)) -- Pattern matching will fail if string is empty
  where closingAction s c = if stackIsEmpty s || ( (stackPeek s) /= (Just c)) then Nothing else (\(Just s)-> Just $ fst s) $ stackPop s
        stackAction s = [("$((", Just $ stackPush s "))")
                        ,("$(",  Just $ stackPush s ")")
                        ,("${",  Just $ stackPush s "}")
                        ,("))",  closingAction s "))")
                        ,(")",   closingAction s ")")
                        ,("}",   closingAction s "}")]
        stackHandler (str, (Just a)) = try $ string str >> if stackIsEmpty a then return $ f str else quote (getDollarExp id a) >>= return . (str++)
        stackHandler (str, Nothing) = unexpected("unexpected " ++ str)

parseWord :: Parser [Token]
parseWord = let eofA = (eof >> return [Word ""])
                appendStr s = parseWord >>= (\((Word r):o) -> return $ [Word $ s ++ r] ++ o)
                delimit delimiters = ( (([Word ""] ++ delimiters) ++) <$> lexer) in eofA
            <|> (parseReservedOp >>= delimit . (:[]) ) 
            <|> (char ' '        >>  delimit []      )                                                 -- NOTE: delimiter will be removed later 
            <|> (char '\n'       >>  delimit [NEWLINE] )
            <|> (char '\\' >> (eofA <|> ( anyChar >>= return . (['\\']++) . (:[]) >>= appendStr ) ) )  -- parse quotes
            <|> (char '\'' >> ((quote (char '\''>> return "'" ) )   >>= appendStr . ("'"++) ) )
            <|> (char '"'  >> ((quote (char '"' >> return "\""  ) ) >>= appendStr . ("\""++) ) )       -- TODO <|> wordExpansion
            <|> (getDollarExp id stackNew >>= return . (:[]) . Word )                                  -- word expansion
            <|> (anyChar   >>= appendStr .  (:[])  )                                                   -- parse letter

lexer :: Parser [Token]
lexer = let eofA = (eof>> return [EOF])
            comment = (eofA <|> (char '\n' >> (([NEWLINE]++) <$> lexer )) <|> (anyChar >> comment)) in eofA
        <|> (           ( (++) . (:[]) ) <$> parseReservedOp <*> lexer )
        <|> (char '\n'       >>               (([NEWLINE]++) <$> lexer ) )
        <|> (char '#'        >> comment)
        <|> (char ' '        >> lexer) <|> parseWord

