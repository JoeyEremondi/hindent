{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}


-- | Chris Done's style.
--
-- Documented here: <https://github.com/chrisdone/haskell-style-guide>

module HIndent.Styles.ElmLang where

import HIndent.Pretty
import HIndent.Comments
import HIndent.Types

import Control.Monad
import Control.Monad.Loops
import Control.Monad.State.Class
import Data.Int
import Data.Maybe
import Language.Haskell.Exts.Annotated (parseExpWithComments)
import Language.Haskell.Exts.Annotated.Fixity
import Language.Haskell.Exts.Annotated.Syntax
import Language.Haskell.Exts.Parser (ParseResult(..))
import Prelude hiding (exp)
import Data.Monoid hiding (Alt)

import           Data.Text.Lazy.Builder (Builder)

import qualified Language.Haskell.Exts.Annotated.Syntax as Syntax

--------------------------------------------------------------------------------
-- Style configuration

-- | A short function name.
shortName :: Int64
shortName = 20

-- | Column limit: 80
smallColumnLimit :: Int64
smallColumnLimit = 100

-- | Empty state.
data State =
  State

-- | The printer style.
elmLang :: Style
elmLang =
  Style {styleName = "elm-lang"
        ,styleAuthor = "Joey Eremondi"
        ,styleDescription = "Elm Lang Style. Documented here: <https://gist.github.com/evancz/0a1f3717c92fe71702be>"
        ,styleInitialState = State
        ,styleExtenders =
           [Extender exp
           ,Extender fieldupdate
           ,Extender rhs
           ,Extender contextualGuardedRhs
           ,Extender stmt
           ,Extender decl
           ,Extender prettyAlt
           ,Extender prettyModule
           , Extender conDecl]
        ,styleDefConfig =
           defaultConfig {configMaxColumns = 100
                         ,configIndentSpaces = 2
                         , configClearEmptyLines = True}
        ,styleCommentPreprocessor = return}

--------------------------------------------------------------------------------
-- Extenders

prettyModule x =
    case x of
      Module _ mayModHead pragmas imps decls ->
        inter (do newline
                  newline)
              (mapMaybe (\(isNull,r) ->
                           if isNull
                              then Nothing
                              else Just r)
                        [(null pragmas,inter newline (map pretty pragmas))
                        ,(case mayModHead of
                            Nothing -> (True,return ())
                            Just modHead -> (False,pretty modHead))
                        ,(null imps,inter newline (map pretty imps))
                        ,(null decls
                         ,interOf newline
                                  (map (\case
                                          r@TypeSig{} -> (1,pretty r)
                                          r -> (3,pretty r))
                                       decls))])
        where interOf i ((c,p):ps) =
                case ps of
                  [] -> p
                  _ ->
                    do p
                       replicateM_ c i
                       interOf i ps
              interOf _ [] = return ()
      XmlPage{} -> error "FIXME: No implementation for XmlPage."
      XmlHybrid{} -> error "FIXME: No implementation for XmlHybrid."


conDecl x =
    case x of
      ConDecl _ name bangty ->
        depend (do pretty name
                   space)
               (spaced (map pretty bangty))
      InfixConDecl l a f b ->
        pretty (ConDecl l f [a,b])
      RecDecl _ name fields ->
        swing (pretty name)
               (do depend (write "{ ")
                          (prefixedLined ", "
                                         (map pretty fields))
                   newline
                   write "}")



-- | Pretty print type signatures like
--
-- foo :: (Show x,Read x)
--     => (Foo -> Bar)
--     -> Maybe Int
--     -> (Char -> X -> Y)
--     -> IO ()
--
decl :: Decl NodeInfo -> Printer s ()
decl (TypeSig _ names ty') =
  do (fitting,st) <- fitsInColumnLimit dependent
     if fitting
        then put st
        else do inter (write ", ")
                      (map pretty names)
                newline
                indentSpaces <- getIndentSpaces
                indented indentSpaces
                         (depend (write ":: ")
                                 (declTy ty'))
  where dependent =
          do inter (write ", ")
                           (map pretty names)
             write " :: "
             declTy ty'
        declTy dty =
          case dty of
            TyForall _ mbinds mctx ty ->
              do case mbinds of
                   Nothing -> return ()
                   Just ts ->
                     do write "forall "
                        spaced (map pretty ts)
                        write ". "
                        newline
                 case mctx of
                   Nothing -> prettyTy ty
                   Just ctx ->
                     do pretty ctx
                        newline
                        indented (-3)
                                 (depend (write "=> ")
                                         (prettyTy ty))
            TyFun _ a b ->
              do pretty a
                 write " -> "
                 pretty b
            _ -> prettyTy dty
        collapseFaps (TyFun _ arg result) = arg : collapseFaps result
        collapseFaps e = [e]
        prettyTy ty =
          do (fits,st) <- fitsOnOneLine (pretty ty)
             if fits
                then put st
                else case collapseFaps ty of
                       [] -> pretty ty
                       tys ->
                         prefixedLined "-> "
                                       (map pretty tys)
decl (TypeDecl _ typehead typ) =
  swing
    (do  (write "type ")
         (depend (pretty typehead)
                 (write " =") ))
        (pretty typ)

decl e = prettyNoExt e

-- | I want field updates to be dependent or newline.
fieldupdate :: FieldUpdate NodeInfo -> Printer t ()
fieldupdate e =
  case e of
    FieldUpdate _ n e' ->
      dependOrNewline
        (do pretty n
            write " = ")
        e'
        pretty
    _ -> prettyNoExt e



-- | Right-hand sides are dependent.
rhs :: Rhs NodeInfo -> Printer t ()
rhs grhs =
  do inCase <- gets psInsideCase
     if inCase
        then unguardedalt grhs
        else unguardedrhs grhs

-- | Right-hand sides are dependent.
unguardedrhs :: Rhs NodeInfo -> Printer t ()
unguardedrhs (UnGuardedRhs _ e) =
  do indentSpaces <- getIndentSpaces
     swing (write " =") (pretty e)
              --(dependOrNewline (write " = ")
              --                 e
              --                 pretty)
unguardedrhs e = prettyNoExt e

-- | Unguarded case alts.
unguardedalt :: Rhs NodeInfo -> Printer t ()
unguardedalt (UnGuardedRhs _ e) =
  --dependOrNewline
    swing (write " ->") (pretty e)
--    e
--    (indented 2 .
--     pretty)
unguardedalt e = prettyNoExt e

-- | Decide whether to do alts or rhs based on the context.
contextualGuardedRhs :: GuardedRhs NodeInfo -> Printer t ()
contextualGuardedRhs grhs =
  do inCase <- gets psInsideCase
     if inCase
        then guardedalt grhs
        else guardedrhs grhs

-- | I want guarded RHS be dependent or newline.
guardedrhs :: GuardedRhs NodeInfo -> Printer t ()
guardedrhs (GuardedRhs _ stmts e) =
  indented 1
           (do prefixedLined
                 ", "
                 (map (\p ->
                         do space
                            pretty p)
                      stmts)
               dependOrNewline
                 (write " = ")
                 e
                 (indented 1 .
                  pretty))

-- | I want guarded alts be dependent or newline.
guardedalt :: GuardedRhs NodeInfo -> Printer t ()
guardedalt (GuardedRhs _ stmts e) =
  indented 1
           (do (prefixedLined
                  ", "
                  (map (\p ->
                          do space
                             pretty p)
                       stmts))
               dependOrNewline
                 (write " ->")
                 e
                 (indented 1 .
                  pretty))

-- Do statements need to handle infix expression indentation specially because
-- do x *
--    y
-- is two invalid statements, not one valid infix op.
stmt :: Stmt NodeInfo -> Printer t ()
stmt (Qualifier _ e@(InfixApp _ a op b)) =
  do col <- fmap (psColumn . snd)
                 (sandbox (write ""))
     infixApp e (Just col)
stmt (Generator _ p e) =
  do indentSpaces <- getIndentSpaces
     pretty p
     indented indentSpaces
              (dependOrNewline
                 (write " <- ")
                 e
                 pretty)
stmt e = prettyNoExt e


prettyAlt (Alt ln (PParen _ p) galts mbinds) =
  prettyAlt $ Alt ln p galts mbinds
prettyAlt (Syntax.Alt _ p galts mbinds) =
        do pretty p
           rhs galts
           case mbinds of
             Nothing -> return ()
             Just binds ->
               do newline
                  indentSpaces <- getIndentSpaces
                  indented indentSpaces
                           (depend (write "where ")
                                   (pretty binds))

writeElse e@(If _ _ _ _) = do
  write "else "
  pretty e
writeElse e =
  swing (write "else") (pretty e)

-- | Expressions
exp :: Exp NodeInfo -> Printer t ()
exp e@(QuasiQuote _ "i" s) =
  do parseMode <- gets psParseMode
     case parseExpWithComments parseMode s of
       ParseOk (e',comments) ->
         do depend (do write "["
                       string "i"
                       write "|")
                   (do exp (snd (annotateComments (fromMaybe e' (applyFixities baseFixities e'))
                                                  comments))
                       write "|]")
       _ -> prettyNoExt e
-- Infix applications will render on one line if possible, otherwise
-- if any of the arguments are not "flat" then that expression is
-- line-separated.
exp e@(InfixApp _ a op b) =
  infixApp e Nothing
--Taken from Johan Tibell style
exp (App _ op a) =
  do (fits,st) <-
       fitsOnOneLine (spaced (map pretty (f : args)))
     if fits
        then put st
        else swing
          (pretty f)
          (lined (map pretty args))
  where (f,args) = flatten op [a]
        flatten :: Exp NodeInfo
                -> [Exp NodeInfo]
                -> (Exp NodeInfo,[Exp NodeInfo])
        flatten (App _ f' a') b =
          flatten f' (a' : b)
        flatten f' as = (f',as)
-- | Lambdas are dependent if they can be.
exp (Lambda _ ps b) =
  depend (write "\\" >> maybeSpace)
         (do spaced (map pretty ps)
             dependOrNewline
               (write " -> ")
               b
               (indented 2 .
                pretty))
  where maybeSpace = case ps of
                       (PBangPat{}):_ -> space
                       (PIrrPat {}):_ -> space
                       _ -> return ()
exp (Do _ stmts) =
  depend (write "do  ")
         (lined (map pretty stmts))
exp (RecConstr _ n fs) =
  do indentSpaces <- getIndentSpaces
     swing (pretty n)
            (spacedDelim "{" "}" (prefixedLined ", "
                                   (map pretty fs)))
exp (RecUpdate _ n fs) =
  do indentSpaces <- getIndentSpaces
     swing (pretty n)
            (spacedDelim "{" "}" (prefixedLined ", "
                                   (map pretty fs)))
exp (Tuple _ boxed exps) =
  do
    (ok,st) <- sandbox renderFlat
    if ok
          then put st
          else spacerFn (prefixedLined ", "
                                       (map pretty exps))
    where
      spacerFn = case boxed of
          Unboxed -> spacedDelim "(# " "#)"
          Boxed -> spacedDelim "( " " )"
      renderFlat =
            do line <- gets psLine
               elmParens (commas (map pretty exps))
               st <- get
               columnLimit <- getColumnLimit
               let overflow = psColumn st > columnLimit
                   single = psLine st == line
               return (not overflow && single)
--Space after each case expression
exp (Case _ e alts) =
  do depend (write "case ")
            (do pretty e
                write " of")
     newline
     indentSpaces <- getIndentSpaces
     indented indentSpaces (lined (map (\x -> withCaseContext True $ pretty x >> newline) alts))

--Special case: always indent if condition of if is an if
exp (If _ p@(If _ _ _ _) t e) =
  do
    indentSpaces <- getIndentSpaces
    swing (write "if ") ((elmParens $ pretty p) >> twolines)
    swing (write "then ") (pretty t >> twolines)
    writeElse e

exp (If _ p t e) =
  do
    indentSpaces <- getIndentSpaces
    id
       (swing (do write "if "
                  pretty p
                  (write " then") )
              (pretty t >> newline) )
    writeElse e
exp (List _ es) =
  do (ok,st) <- sandbox renderFlat
     if ok
        then put st
        else spacedDelim "[" "]" (prefixedLined ", "
                                     (map pretty es))
  where renderFlat =
          do line <- gets psLine
             brackets (commas (map pretty es))
             st <- get
             columnLimit <- getColumnLimit
             let overflow = psColumn st > columnLimit
                 single = psLine st == line
             return (not overflow && single)

exp (Let _ binds e) =
  do
     spaces <- getIndentSpaces
     swing (write "let ")
            ( pretty binds)
     newline
     swing (write "in ")
            (pretty e)

exp e = prettyNoExt e

--------------------------------------------------------------------------------
-- Indentation helpers

-- | Sandbox and render the nodes on multiple lines, returning whether
-- each is a single line.
sandboxSingles :: Pretty ast
               => [ast NodeInfo] -> Printer t (Bool,PrintState t)
sandboxSingles args =
  sandbox (allM (\(i,arg) ->
                   do when (i /=
                            (0 :: Int))
                           newline
                      line <- gets psLine
                      pretty arg
                      st <- get
                      return (psLine st == line))
                (zip [0 ..] args))

-- | Render multi-line nodes.
multi :: Pretty ast
      => Int64 -> [ast NodeInfo] -> Bool -> Printer t ()
multi orig args headIsShort =
  if headIsShort
     then lined (map pretty args)
     else do (allAreSingle,st) <- sandboxSingles args
             if allAreSingle
                then put st
                else do newline
                        indentSpaces <- getIndentSpaces
                        column (indentSpaces)
                               (lined (map pretty args))

-- | Sandbox and render the node on a single line, return whether it's
-- on a single line and whether it's overflowing.
sandboxNonOverflowing :: Pretty ast
                      => [ast NodeInfo] -> Printer t ((Bool,Bool),PrintState t)
sandboxNonOverflowing args =
  sandbox (do line <- gets psLine
              columnLimit <- getColumnLimit
              singleLineRender
              st <- get
              return (psLine st == line,psColumn st > columnLimit + 20))
  where singleLineRender =
          spaced (map pretty args)

--------------------------------------------------------------------------------
-- Predicates

-- | Is the expression "short"? Used for app heads.
isShort :: (Pretty ast)
        => ast NodeInfo -> Printer t (Bool,PrintState t)
isShort p =
  do line <- gets psLine
     orig <- fmap (psColumn . snd)
                  (sandbox (write ""))
     (_,st) <- sandbox (pretty p)
     return (psLine st == line &&
             (psColumn st < orig + shortName)
            ,st)

-- | Is the given expression "small"? I.e. does it fit on one line and
-- under 'smallColumnLimit' columns.
isSmall :: MonadState (PrintState t) m
        => m a -> m (Bool,PrintState t)
isSmall p =
  do line <- gets psLine
     (_,st) <- sandbox p
     return (psLine st == line && psColumn st < smallColumnLimit,st)

-- | Is the given expression "small"? I.e. does it fit under
-- 'smallColumnLimit' columns.
isSmallFitting :: MonadState (PrintState t) m
               => m a -> m (Bool,PrintState t)
isSmallFitting p =
  do (_,st) <- sandbox p
     return (psColumn st < smallColumnLimit,st)

-- | Is an expression flat?
isFlat :: Exp NodeInfo -> Bool
isFlat (Lambda _ _ e) = isFlat e
isFlat (App _ a b) = isName a && isName b
  where isName (Var{}) = True
        isName _ = False
isFlat (InfixApp _ a _ b) = isFlat a && isFlat b
isFlat (NegApp _ a) = isFlat a
isFlat VarQuote{} = True
isFlat TypQuote{} = True
isFlat (List _ []) = True
isFlat Var{} = True
isFlat Lit{} = True
isFlat Con{} = True
isFlat (LeftSection _ e _) = isFlat e
isFlat (RightSection _ _ e) = isFlat e
isFlat _ = False

-- | Does printing the given thing overflow column limit? (e.g. 80)
fitsOnOneLine :: MonadState (PrintState s) m => m a -> m (Bool,PrintState s)
fitsOnOneLine p =
  do line <- gets psLine
     (_,st) <- sandbox p
     columnLimit <- getColumnLimit
     return (psLine st == line && psColumn st < columnLimit,st)

-- | Does printing the given thing overflow column limit? (e.g. 80)
fitsInColumnLimit :: Printer t a -> Printer t (Bool,PrintState t)
fitsInColumnLimit p =
  do (_,st) <- sandbox p
     columnLimit <- getColumnLimit
     return (psColumn st < columnLimit,st)

--------------------------------------------------------------------------------
-- Helpers


infixApp :: Exp NodeInfo
         -> Maybe Int64
         -> Printer s ()
infixApp e indent =
  do
     let wholeChain@(OpChainExp a : chain) = (flattenOpChain e)
     (fits,st) <-
       fitsOnOneLine
         (spaced (map (\link ->
                         case link of
                           OpChainExp e' -> pretty e'
                           OpChainLink qop -> pretty qop)
                      wholeChain))


     if fits
        then put st
        else
          swing (pretty a) $
          forM_ chain $ \link -> do
                  let
                    toPrint =
                      case link of
                        OpChainExp e' -> pretty e' >> newline
                        OpChainLink qop -> pretty qop >> space
                  case indent of
                    Nothing ->
                      do
                        toPrint
                    Just col ->
                      toPrint
                      --do indentSpaces <- getIndentSpaces
                      --   column (col + indentSpaces)
                      --          (toPrint)
  --where prettyWithIndent e' =
  --        case e' of
  --          (InfixApp _ a' op' b') ->
  --            infixApp e' a' op' b' indent
  --          _ -> pretty e'

-- | A link in a chain of operator applications.
data OpChainLink l
  = OpChainExp (Exp l)
  | OpChainLink (QOp l)
  deriving (Show)

-- | Flatten a tree of InfixApp expressions into a chain of operator
-- links.
flattenOpChain :: Exp l -> [OpChainLink l]
flattenOpChain (InfixApp _ left op right) =
  flattenOpChain left <>
  [OpChainLink op] <>
  flattenOpChain right
flattenOpChain e = [OpChainExp e]



-- | Make the right hand side dependent if it's flat, otherwise
-- newline it.
dependOrNewline
  :: Printer t ()
  -> Exp NodeInfo
  -> (Exp NodeInfo -> Printer t ())
  -> Printer t ()
dependOrNewline left right f =
  do (fits,st) <- fitsOnOneLine (depend left (f right))
     if fits
        then put st
        else do left
                newline
                (f right)

-- | Wrap in braces.
spacedDelim :: MonadState (PrintState s) m => Builder -> Builder -> m a -> m a
spacedDelim start end p =
  depend (write start >> space)
         (do v <- p
             write end
             return v)



maybeSwing True x y = swing x y
maybeSwing False x y = x >> y


elmParens :: MonadState (PrintState s) m => m a -> m a
elmParens p =
  depend (write "( ")
         (do v <- p
             write " )"
             return v)
