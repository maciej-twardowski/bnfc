{-
    BNF Converter: C++ abstract syntax generator
    Copyright (C) 2004  Author:  Michael Pellauer

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

    Description   : This module generates the C++ Abstract Syntax
                    tree classes. It generates both a Header file
                    and an Implementation file, and uses the Visitor
                    design pattern.

    Author        : Michael Pellauer (pellauer@cs.chalmers.se)

    License       : GPL (GNU General Public License)

    Created       : 4 August, 2003                           

    Modified      : 22 May, 2004 / Antti-Juhani Kaijanaho

   
   ************************************************************** 
-}

module CFtoSTLAbs (cf2CPPAbs) where

import CF
import Utils((+++),(++++))
import BNFC.Backend.Common.NamedVariables
import List
import Char(toLower)


--The result is two files (.H file, .C file)
cf2CPPAbs :: String -> CF -> (String, String)
cf2CPPAbs name cf = (mkHFile cf, mkCFile cf)


{- **** Header (.H) File Functions **** -}

--Makes the Header file.
mkHFile :: CF -> String
mkHFile cf = unlines
 [
  "#ifndef ABSYN_HEADER",
  "#define ABSYN_HEADER",
  "",
  "#include<string>",
  "#include<vector>",
  "",
  header,
  prTypeDefs user,
  "/********************   Forward Declarations    ********************/\n",
  concatMap prForward classes,
  "",
  prVisitor classes,
  prVisitable,
  "",
  "/********************   Abstract Syntax Classes    ********************/\n",
  concatMap (prDataH user) (posData ++ cf2dataLists cf),
  "",
  "#endif"
 ]
 where
  user0 = fst (unzip (tokenPragmas cf))
  (userPos,user) = partition (isPositionCat cf) user0
  posData = [(c,[(c,["String","Integer"])]) | c <- userPos]
  header = "//C++ Abstract Syntax Interface generated by the BNF Converter.\n"
  rules = getRules cf
  classes = userPos ++ rules ++ (getClasses (allCats cf))
  prForward s | isProperLabel s = "class " ++ (normCat s) ++ ";\n"
  prForward s = ""
  getRules cf = (map testRule (rulesOfCF cf))
  getClasses [] = []
  getClasses (c:cs) = 
   if identCat (normCat c) /= c 
   then getClasses cs
   else if elem c rules
     then getClasses cs
     else c : (getClasses cs)
  
  testRule (f, (c, r)) = 
   if isList c
   then if isConsFun f 
     then identCat c
     else "_" --ignore this
   else f

--Prints interface classes for all categories.
prDataH :: [UserDef] -> Data -> String
prDataH  user (cat, rules) = 
  case lookup cat rules of
    Just x -> concatMap (prRuleH user cat) rules
    Nothing -> if isList cat
      then concatMap (prRuleH user cat) rules
      else unlines
       [
        "class" +++ (identCat cat) +++ ": public Visitable {",
	"public:",
	"  virtual" +++ (identCat cat) +++ "*clone() const = 0;",
	"};\n",
        concatMap (prRuleH user cat) rules
       ]
       
--Interface definitions for rules vary on the type of rule.
prRuleH :: [UserDef] -> String -> (Fun, [Cat]) -> String
prRuleH user c (fun, cats) = 
    if isNilFun fun || isOneFun fun
    then ""  --these are not represented in the AbSyn
    else if isConsFun fun
    then --this is the linked list case.
    unlines
    [
     "class" +++ c' +++ ": public Visitable, public std::vector<" ++memstar++">",
     "{",
     " public:",
     "",
     "  virtual void accept(Visitor *v);",
     "  virtual " ++ c' ++ " *clone() const;",
     "};"
    ]
    else --a standard rule
    unlines
    [
     "class" +++ fun' +++ ": public" +++ super,
     "{",
     " public:",
     prInstVars user vs,
     "  " ++ fun' ++ "(const" +++ fun' +++ "&);",
     "  " ++ fun' ++ " &operator=(const" +++ fun' +++ "&);",
     "  " ++ fun' ++ "(" ++ (prConstructorH 1 vs) ++ ");",
     prDestructorH fun',
     "  virtual void accept(Visitor *v);",
     "  virtual " +++ fun' +++ " *clone() const;",
     "  void swap(" ++ fun' +++ "&);",
     "};\n"
    ]
   where 
     vs = getVars cats
     fun' = identCat (normCat fun)
     c' = identCat (normCat c);
     mem = drop 4 c'
     memstar = if isBasic user mem then mem else mem ++ "*"
     super = if c == fun then "Visitable" else (identCat c)
     prConstructorH :: Int -> [(String, b)] -> String
     prConstructorH _ [] = ""
     prConstructorH n ((t,_):[]) = t +++ (optstar t) ++ "p" ++ (show n)
     prConstructorH n ((t,_):vs) =( t +++ (optstar t) ++ "p" ++ (show n) ++ ", ") ++ (prConstructorH (n+1) vs)
     prDestructorH n = "  ~" ++ n ++ "();"
     optstar x = if isBasic user x
       then ""
       else "*"

prVisitable :: String
prVisitable = unlines
 [
  "class Visitable",
  "{",
  " public:",
  -- all classes with virtual methods require a virtual destructor
  "  virtual ~Visitable() {}",
  "  virtual void accept(Visitor *v) = 0;",
  "};\n"
 ]

prVisitor :: [String] -> String
prVisitor fs = unlines
 [
  "/********************   Visitor Interfaces    ********************/",
  "",
  "class Visitor",
  "{",
  " public:",
  "  virtual ~Visitor() {}",
  (concatMap (prVisitFun) fs),
  footer
 ]
 where
   footer = unlines
    [  --later only include used categories
     "  virtual void visitInteger(Integer i) = 0;",
     "  virtual void visitDouble(Double d) = 0;",
     "  virtual void visitChar(Char c) = 0;",
     "  virtual void visitString(String s) = 0;",
     "};"
    ]
   prVisitFun f | isProperLabel f = 
     "  virtual void visit" ++ f' ++ "(" ++ f' ++ " *p) = 0;\n"
    where
       f' = identCat (normCat f)
   prVisitFun _ = ""

--typedefs in the Header make generation much nicer.
prTypeDefs user = unlines
  [
   "/********************   TypeDef Section    ********************/",
   "typedef int Integer;",
   "typedef char Char;",
   "typedef double Double;",
   "typedef std::string String;",
   "typedef std::string Ident;",
   concatMap prUserDef user
  ]
 where
  prUserDef s = "typedef std::string " ++ s ++ ";\n"
  
--A class's instance variables.
prInstVars :: [UserDef] -> [IVar] -> String
prInstVars _ [] = []
prInstVars user vars@((t,n):vs) = 
  "  " ++ t +++ uniques ++ ";" ++++
  (prInstVars user vs')
 where
   (uniques, vs') = prUniques t vars
   --these functions group the types together nicely
   prUniques :: String -> [IVar] -> (String, [IVar])
   prUniques t vs = (prVars (findIndices (\x -> case x of (y,_) ->  y == t) vs) vs, remType t vs)
   prVars (x:[]) vs =  case vs !! x of
   			(t,n) -> ((varLinkName t) ++ (showNum n))
   prVars (x:xs) vs = case vs !! x of 
   			(t,n) -> ((varLinkName t) ++ (showNum n)) ++ "," +++
				 (prVars xs vs)
   varLinkName z = if isBasic user z
     then (map toLower z) ++ "_"
     else "*" ++ (map toLower z) ++ "_"
   remType :: String -> [IVar] -> [IVar]
   remType _ [] = []
   remType t ((t2,n):ts) = if t == t2 
   				then (remType t ts) 
				else (t2,n) : (remType t ts)

 
{- **** Implementation (.C) File Functions **** -}

--Makes the .C file
mkCFile :: CF -> String
mkCFile cf = unlines
 [
  header,
  concatMap (prDataC user) (posData ++ cf2dataLists cf)
 ]
 where
  user0 = fst (unzip (tokenPragmas cf))
  (userPos,user) = partition (isPositionCat cf) user0
  posData = [(c,[(c,["String","Integer"])]) | c <- userPos]
  header = unlines
   [
    "//C++ Abstract Syntax Implementation generated by the BNF Converter.",
    "#include <algorithm>",
    "#include <string>",
    "#include <iostream>",
    "#include <vector>",
    "#include \"Absyn.H\""
   ]

--This is not represented in the implementation.
prDataC :: [UserDef] -> Data -> String
prDataC user (cat, rules) = concatMap (prRuleC user cat) rules

--Classes for rules vary based on the type of rule.
prRuleC user c (fun, cats) = 
    if isNilFun fun || isOneFun fun
    then ""  --these are not represented in the AbSyn
    else if isConsFun fun
    then --this is the linked list case.
    unlines
    [
     "/********************   " ++ c' ++ "    ********************/",
     prAcceptC c',
     prCloneC user c' vs,
     ""
    ]
    else --a standard rule
    unlines
    [
     "/********************   " ++ fun' ++ "    ********************/",
     prConstructorC user fun' vs cats,
     prCopyC user fun' vs,
     prDestructorC user fun' vs,
     prAcceptC fun,
     prCloneC user fun' vs,
     ""
    ]
   where 
     vs = getVars cats
     fun' = identCat (normCat fun)
     c' = identCat (normCat c)

--These are all built-in list functions.
--Later we could include things like lookup,insert,delete,etc.
prListFuncs :: [UserDef] -> String -> String
prListFuncs user c = unlines
 [
  c ++ "::" ++ c ++ "(" ++ m +++ mstar ++ "p)",
  "{",
  "  " ++ m' ++ " = p;",
  "  " ++ v ++ "= 0;",
  "}",
  c ++ "*" +++ c ++ "::" ++ "reverse()",
  "{",
  "  if (" ++ v +++ "== 0) return this;",
  "  else",
  "  {",
  "    " ++ c ++ " *tmp =" +++ v ++ "->reverse(this);",
  "    " ++ v +++ "= 0;",
  "    return tmp;",
  "  }",
  "}",
  "",
  c ++ "*" +++ c ++ "::" ++ "reverse(" ++ c ++ "* prev)",
  "{",
  "  if (" ++ v +++ "== 0)",
  "  {",
  "    " ++ v +++ "= prev;",
  "    return this;",
  "  }",
  "  else",
  "  {",
  "    " ++ c +++ "*tmp =" +++ v ++ "->reverse(this);",
  "    " ++ v +++ "= prev;",
  "    return tmp;",
  "  }",
  "}"
 ]
 where
   v = (map toLower c) ++ "_"
   m = drop 4 c
   mstar = if isBasic user m then "" else "*"
   m' = drop 4 v

--The standard accept function for the Visitor pattern
prAcceptC :: String -> String
prAcceptC ty = 
  "\nvoid " ++ ty ++ "::accept(Visitor *v) { v->visit" ++ ty ++ "(this); }"

--The constructor just assigns the parameters to the corresponding instance variables.
prConstructorC :: [UserDef] -> String -> [IVar] -> [Cat] -> String
prConstructorC user c vs cats = 
  c ++ "::" ++ c ++"(" ++ (interleave types params) ++ ")" +++ "{" +++ 
   prAssigns vs params ++ "}"
  where
   (types, params) = unzip (prParams cats (length cats) ((length cats)+1))
   interleave _ [] = []
   interleave (x:[]) (y:[]) = x +++ (optstar x) ++ y
   interleave (x:xs) (y:ys) = x +++ (optstar x) ++ y ++ "," +++ (interleave xs ys)
   optstar x = if isBasic user x
       then ""
       else "*"

--Print copy constructor and copy assignment
prCopyC :: [UserDef] -> String -> [IVar] -> String
prCopyC user c vs =
    c ++ "::" ++ c ++ "(const" +++ c +++ "& other) {" +++
      concatMap doV vs ++++
      "}" ++++
      c +++ "&" ++ c ++ "::" ++ "operator=(const" +++ c +++ "& other) {" ++++
      "  " ++ c +++ "tmp(other);" ++++
      "  swap(tmp);" ++++
      "  return *this;" ++++
      "}" ++++
      "void" +++ c ++ "::swap(" ++ c +++ "& other) {" ++++
      concatMap swapV vs ++++
      "}\n"
    where  doV :: IVar -> String
	   doV v@(t, _) 
	     | isBasic user t = "  " ++ vn v ++ " = other." ++ vn v ++ ";\n"
	     | otherwise = "  " ++ vn v ++ " = other." ++ vn v ++ "->clone();\n"
	   vn :: IVar -> String
	   vn (t, 0) = varName t
	   vn (t, n) = varName t ++ show n
	   swapV :: IVar -> String
	   swapV v = "  std::swap(" ++ vn v ++ ", other." ++ vn v ++ ");\n"

--The cloner makes a new deep copy of the object
prCloneC :: [UserDef] -> String -> [IVar] -> String
prCloneC user c vs =
  c +++ "*" ++ c ++ "::clone() const {" ++++
    "  return new" +++ c ++ "(*this);\n}"

--The destructor deletes all a class's members.
prDestructorC :: [UserDef] -> String -> [IVar] -> String
prDestructorC user c vs  = 
  c ++ "::~" ++ c ++"()" +++ "{" +++ 
   (concatMap prDeletes vs) ++ "}"
  where
   prDeletes :: (String, Int) -> String
   prDeletes (t, n) = if isBasic user t
    then ""
    else if n == 0
     then "delete(" ++ (varName t) ++ "); "
     else "delete(" ++ (varName t) ++ (show n) ++ "); "

--Prints the constructor's parameters.    
prParams :: [Cat] -> Int -> Int -> [(String,String)]
prParams [] _ _ = []
prParams (c:cs) n m = (identCat c,"p" ++ (show (m-n)))
			: (prParams cs (n-1) m)
      
--Prints the assignments of parameters to instance variables.
--This algorithm peeks ahead in the list so we don't use map or fold
prAssigns :: [IVar] -> [String] -> String
prAssigns [] _ = []
prAssigns _ [] = []
prAssigns ((t,n):vs) (p:ps) =
 if n == 1 then
  case findIndices (\x -> case x of (l,r) -> l == t) vs of
    [] -> (varName t) +++ "=" +++ p ++ ";" +++ (prAssigns vs ps)
    z -> ((varName t) ++ (showNum n)) +++ "=" +++ p ++ ";" +++ (prAssigns vs ps)
 else ((varName t) ++ (showNum n)) +++ "=" +++ p ++ ";" +++ (prAssigns vs ps)


{- **** Helper Functions **** -}

--Checks if something is a basic or user-defined type.
-- These are not treated as classes.
-- But position tokens are.
isBasic :: [UserDef] -> String -> Bool
isBasic user x = 
  if elem x user
    then True
    else case x of
      "Integer" -> True
      "Char" -> True
      "String" -> True
      "Double" -> True
      "Ident" -> True
      _ -> False
