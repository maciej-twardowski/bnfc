{-
    BNF Converter: C# GPLEX Generator
    Copyright (C) 2006  Author:  Johan Broberg
    
    Modified from CFtoFlex

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

{- 
   **************************************************************
    BNF Converter Module

    Description   : This module generates the GPLEX file.

    Author        : Johan Broberg (johan@pontemonti.com)

    License       : GPL (GNU General Public License)

    Created       : 23 November, 2006

    Modified      : 17 December, 2006 by Johan Broberg

   ************************************************************** 
-}

module BNFC.Backend.CSharp.CFtoGPLEX (cf2gplex) where

import CF
import BNFC.Backend.CSharp.RegToGPLEX
import Utils((+++), (++++))
import BNFC.Backend.Common.NamedVariables
import Data.List
import BNFC.Backend.CSharp.CSharpUtils

--The environment must be returned for the parser to use.
cf2gplex :: Namespace -> CF -> (String, SymEnv)
cf2gplex namespace cf = (unlines [
  prelude namespace,
  cMacros,
  prettyprinter $ (lexSymbols env) ++ (gplex namespace cf env'),
  "%%"
  ], env')
  where
    env = makeSymEnv (symbols cf ++ reservedWords cf) (0 :: Int)
    env' = env ++ (makeSymEnv (fst (unzip (tokenPragmas cf))) (length env))
    -- GPPG doesn't seem to like tokens beginning with an underscore, so they (the underscores, nothing else) have been removed.
    makeSymEnv [] _ = []
    makeSymEnv (s:symbs) n = (s, "SYMB_" ++ (show n)) : (makeSymEnv symbs (n+1))

prelude :: Namespace -> String
prelude namespace = unlines [
  "/* This GPLex file was machine-generated by the BNF converter */",
  "",
  "%namespace " ++ namespace,
  "",
  "%{",
  "        /// <summary>",
  "        /// Buffer for escaped characters in strings.",
  "        /// </summary>",
  "        private System.Text.StringBuilder strBuffer = new System.Text.StringBuilder();",
  "",
  "        /// <summary>",
  "        /// Change to enable output - useful for debugging purposes",
  "        /// </summary>",
  "        public bool Trace = false;",
  "",
  "        /// <summary>",
  "        /// Culture-independent IFormatProvider for numbers. ",
  "        /// This is just a \"wrapper\" for System.Globalization.NumberFormatInfo.InvariantInfo.",
  "        /// </summary>",
  "        /// <remarks>",
  "        /// This should be used when parsing numbers. Otherwise the parser might fail: ",
  "        /// culture en-US uses a dot as decimal separator, while for example sv-SE uses a comma. ",
  "        /// BNFC uses dot as decimal separator for Double values, so if your culture is sv-SE ",
  "        /// the parse will fail if this InvariantInfo isn't used.",
  "        /// </remarks>",
  "        private static System.Globalization.NumberFormatInfo InvariantFormatInfo = System.Globalization.NumberFormatInfo.InvariantInfo;",
  "",
  "        /// <summary>",
  "        /// Convenience method to create scanner AND initialize it correctly.",
  "        /// As long as you don't want to enable trace output, this is all you ",
  "        /// need to call and give to the parser to be able to parse.",
  "        /// </summary>",
  "        public static Scanner CreateScanner(Stream stream)",
  "        {",
  "          Scanner scanner = new Scanner(stream);",
  "          scanner.Begin();",
  "          return scanner;",
  "        }",
  "",
  "        /// <summary>",
  "        /// Sets the scanner to the correct initial state (YYINITIAL). ",
  "        /// You should call this method prior to calling parser.Parse().",
  "        /// </summary>",
  "        public void Begin()",
  "        {",
  "          BEGIN(YYINITIAL);",
  "        }",
  "",
  "        /// <summary>",
  "        /// Convenience method to \"reset\" the buffer for escaped characters in strings.",
  "        /// </summary>",
  "        private void BufferReset()",
  "        {",
  "          this.strBuffer = new System.Text.StringBuilder();",
  "        }",
  "",
  "%}",
  ""
  ]

--For now all categories are included.
--Optimally only the ones that are used should be generated.
cMacros :: String
cMacros = unlines
  [
  "alpha [a-zA-Z]",
  "alphaCapital [A-Z]",
  "alphaSmall [a-z]",
  "digit [0-9]",
  "ident [a-zA-Z0-9'_]",
  -- start states, must be defined one at a time
  "%s YYINITIAL",
  "%s COMMENT",
  "%s CHAR",
  "%s CHARESC",
  "%s CHAREND",
  "%s STRING",
  "%s ESCAPED",
  "%%"
  ]

lexSymbols :: SymEnv -> [(String, String)]
lexSymbols ss = map transSym ss
  where
    transSym (s,r) = 
      ("<YYINITIAL>\"" ++ s' ++ "\"" , "if(Trace) System.Console.Error.WriteLine(yytext); return (int)Tokens." ++ r ++ ";")
        where
         s' = escapeChars s

gplex :: Namespace -> CF -> SymEnv -> [(String, String)]
gplex namespace cf env = concat [
  lexComments (comments cf),
  userDefTokens,
  ifC "String" strStates,
  ifC "Char" charStates,
  ifC "Double"  [("<YYINITIAL>{digit}+\".\"{digit}+(\"e\"(\\-)?{digit}+)?" , "if(Trace) System.Console.Error.WriteLine(yytext); yylval.double_ = Double.Parse(yytext, InvariantFormatInfo); return (int)Tokens.DOUBLE_;")],
  ifC "Integer" [("<YYINITIAL>{digit}+"                                    , "if(Trace) System.Console.Error.WriteLine(yytext); yylval.int_    = Int32.Parse(yytext,  InvariantFormatInfo); return (int)Tokens.INTEGER_;")],
  ifC "Ident"   [("<YYINITIAL>{alpha}{ident}*"                             , "if(Trace) System.Console.Error.WriteLine(yytext); yylval.string_ = yytext; return (int)Tokens.IDENT_;")],
  [("<YYINITIAL>[ \\t\\r\\n\\f]" , "/* ignore white space. */;")],
  [("<YYINITIAL>."               , "return (int)Tokens.error;")]
  ]
  where
   ifC cat s = if isUsedCat cf cat then s else []
   userDefTokens = map tokenline (tokenPragmas cf)
     where
       tokenline (name, exp) = ("<YYINITIAL>" ++ printRegGPLEX exp , action name)
       action n = "if(Trace) System.Console.Error.WriteLine(yytext); yylval." ++ varName (normCat n) ++ " = new " ++ identifier namespace n ++ "(yytext); return (int)Tokens." ++ sName n ++ ";"
       sName n = case lookup n env of
         Just x -> x
         Nothing -> n
   -- These handle escaped characters in Strings.
   strStates = [
     ("<YYINITIAL>\"\\\"\"" , "BEGIN(STRING);"),
     ("<STRING>\\\\"        , "BEGIN(ESCAPED);"),
     ("<STRING>\\\""        , "yylval.string_ = this.strBuffer.ToString(); BufferReset(); BEGIN(YYINITIAL); return (int)Tokens.STRING_;"),
     ("<STRING>."           , "this.strBuffer.Append(yytext);"),
     ("<ESCAPED>n"          , "this.strBuffer.Append(\"\\n\");   BEGIN(STRING);"),
     ("<ESCAPED>\\\""       , "this.strBuffer.Append(\"\\\"\");   BEGIN(STRING);"),
     ("<ESCAPED>\\\\"       , "this.strBuffer.Append(\"\\\\\");   BEGIN(STRING);"),
     ("<ESCAPED>t"          , "this.strBuffer.Append(\"\\t\");   BEGIN(STRING);"),
     ("<ESCAPED>."          , "this.strBuffer.Append(yytext); BEGIN(STRING);")
     ]
   -- These handle escaped characters in Chars.
   charStates = [
     ("<YYINITIAL>\"'\"" , "BEGIN(CHAR);"),
     ("<CHAR>\\\\"       , "BEGIN(CHARESC);"),
     ("<CHAR>[^']"       , "BEGIN(CHAREND); yylval.char_ = yytext[0]; return (int)Tokens.CHAR_;"),
     ("<CHARESC>n"       , "BEGIN(CHAREND); yylval.char_ = '\\n';      return (int)Tokens.CHAR_;"),
     ("<CHARESC>t"       , "BEGIN(CHAREND); yylval.char_ = '\\t';      return (int)Tokens.CHAR_;"),
     ("<CHARESC>."       , "BEGIN(CHAREND); yylval.char_ = yytext[0]; return (int)Tokens.CHAR_;"),
     ("<CHAREND>\"'\""   , "BEGIN(YYINITIAL);")
     ]

lexComments :: ([(String, String)], [String]) -> [(String, String)]
lexComments (m,s) = (map lexSingleComment s) ++ (concatMap lexMultiComment m)

lexSingleComment :: String -> (String, String)
lexSingleComment c = 
  ("<YYINITIAL>\"" ++ c ++ "\"[^\\n]*\\n" , "/* BNFC single-line comment */;")

--There might be a possible bug here if a language includes 2 multi-line comments.
--They could possibly start a comment with one character and end it with another.
--However this seems rare.
lexMultiComment :: (String, String) -> [(String, String)]
lexMultiComment (b,e) = [
  ("<YYINITIAL>\"" ++ b ++ "\"" , "BEGIN(COMMENT);"),
  ("<COMMENT>\"" ++ e ++ "\""   , "BEGIN(YYINITIAL);"),
  ("<COMMENT>."                 , "/* BNFC multi-line comment */;"),
  ("<COMMENT>[\\n]"             , "/* BNFC multi-line comment */;")
  ]

-- Used to print the lexer rules; makes sure that all rules are equally indented, to make the GPLEX file a little more readable.
prettyprinter :: [(String, String)] -> String
prettyprinter xs = unlines $ map prettyprinter' xs
  where 
    padlength = 1 + (last $ sort $ map length $ map fst xs)
    prettyprinter' (x, y) = x ++ replicate (padlength - length x) ' ' ++ y
