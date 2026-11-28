--!optimize 2
--!strict
--[=[
LuauParser feca7f036d2e24825c5b096f8979ba005e48a0cf
MIT License

Copyright (c) 2026 vantoanvh

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

MIT License

Copyright (c) 2019-2025 Roblox Corporation
Copyright (c) 1994–2019 Lua.org, PUC-Rio.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

]=]
type Position = vector

type Location = {
	begin: Position,
	end_: Position,
}


type AstName = {
	value: string,
}

type AstExpr = AstExprGroup
| AstExprConstantNil
| AstExprConstantBool
| AstExprConstantNumber
| AstExprConstantInteger
| AstExprConstantString
| AstExprLocal
| AstExprGlobal
| AstExprVarargs
| AstExprCall
| AstExprIndexName
| AstExprIndexExpr
| AstExprFunction
| AstExprTable
| AstExprUnary
| AstExprBinary
| AstExprTypeAssertion
| AstExprIfElse
| AstExprInterpString
| AstExprInstantiate
| AstExprError

type AstStat = AstStatBlock
| AstStatIf
| AstStatWhile
| AstStatRepeat
| AstStatBreak
| AstStatContinue
| AstStatReturn
| AstStatExpr
| AstStatLocal
| AstStatFor
| AstStatForIn
| AstStatAssign
| AstStatCompoundAssign
| AstStatFunction
| AstStatLocalFunction
| AstStatTypeAlias
| AstStatTypeFunction
| AstStatDeclareGlobal
| AstStatDeclareFunction
| AstStatDeclareExternType
| AstStatClass
| AstStatError

type AstTypePack = AstTypePackExplicit | AstTypePackVariadic | AstTypePackGeneric

type AstType = AstTypeReference
| AstTypeTable
| AstTypeFunction
| AstTypeTypeof
| AstTypeUnion
| AstTypeIntersection
| AstTypeSingletonBool
| AstTypeSingletonString
| AstTypeGroup
| AstTypeError
| AstTypeOptional

type AstTypeList = {
	types: { AstType },
	tailType: AstTypePack?,
}

type AstTypeOrPack = {
	type: AstType?,
	typePack: AstTypePack?,
}

type AstTableAccess = "Read" | "Write" | "ReadWrite"

type AstArgumentName = {
	name: string,
	location: Location,
}

type AstLocal = {
	name: string,
	location: Location,
	shadow: AstLocal?,
	functionDepth: number,
	loopDepth: number,
	annotation: AstType?,
	isConst: boolean?,
	isExported: boolean?,
}

type AstAttr = {
	cstNode: CstAttr | CstParametrizedAttr?,
	kind: "Attr",
	location: Location,
	type: string?,
	args: { AstExpr },
	name: string?,
}

type AstGenericType = {
	cstNode: CstGenericType?,
	kind: "GenericType",
	location: Location,
	name: string,
	defaultValue: AstType?,
}

type AstGenericTypePack = {
	cstNode: CstGenericTypePack?,
	kind: "GenericTypePack",
	location: Location,
	name: string,
	defaultValue: AstTypePack?,
}

type AstExprGroup = {
	cstNode: CstExprGroup?,
	kind: "ExprGroup",
	location: Location,
	expr: AstExpr,
}

type AstExprConstantNil = {
	kind: "ExprConstantNil",
	location: Location,
}

type AstExprConstantBool = {
	kind: "ExprConstantBool",
	location: Location,
	value: boolean,
}

type AstExprConstantNumber = {
	cstNode: CstExprConstantNumber?,
	kind: "ExprConstantNumber",
	location: Location,
	value: number,
	parseResult: "Ok" | "Imprecise" | "HexOverflow" | "BinOverflow" | "IntOverflow" | "Malformed",
}

type AstExprConstantInteger = {
	cstNode: CstExprConstantInteger?,
	kind: "ExprConstantInteger",
	location: Location,
	low: number,
	high: number,
	parseResult: "Ok" | "Imprecise" | "HexOverflow" | "BinOverflow" | "IntOverflow" | "Malformed",
}

type AstExprConstantString = {
	cstNode: CstExprConstantString?,
	kind: "ExprConstantString",
	location: Location,
	value: string,
	quoteStyle: number,
}

type AstExprLocal = {
	kind: "ExprLocal",
	location: Location,
	["local"]: AstLocal,
	upvalue: boolean,
}

type AstExprGlobal = {
	kind: "ExprGlobal",
	location: Location,
	name: string,
}

type AstExprVarargs = {
	kind: "ExprVarargs",
	location: Location,
}

type AstExprCall = {
	cstNode: CstExprCall?,
	kind: "ExprCall",
	location: Location,
	func: AstExpr,
	args: { AstExpr },
	self: boolean,
	typeArguments: { AstTypeOrPack },
	argLocation: Location,
}

type AstExprIndexName = {
	kind: "ExprIndexName",
	location: Location,
	expr: AstExpr,
	index: string,
	indexLocation: Location,
	opPosition: Position,
	op: number,
}

type AstExprIndexExpr = {
	cstNode: CstExprIndexExpr?,
	kind: "ExprIndexExpr",
	location: Location,
	expr: AstExpr,
	index: AstExpr,
}

type AstExprFunction = {
	cstNode: CstExprFunction?,
	kind: "ExprFunction",
	location: Location,
	attributes: { AstAttr },
	generics: { AstGenericType },
	genericPacks: { AstGenericTypePack },
	self: AstLocal?,
	args: { AstLocal },
	returnAnnotation: AstTypePack?,
	vararg: boolean,
	varargLocation: Location?,
	varargAnnotation: AstTypePack?,
	body: AstStatBlock,
	functionDepth: number,
	debugname: string?,
	argLocation: Location?,
}

type AstExprTableItem = {
	kind: "List" | "Record" | "General",
	key: AstExpr?,
	value: AstExpr,
}

type AstExprTable = {
	cstNode: CstExprTable?,
	kind: "ExprTable",
	location: Location,
	items: { AstExprTableItem },
}

type AstExprUnary = {
	cstNode: CstExprOp?,
	kind: "ExprUnary",
	location: Location,
	op: number,
	expr: AstExpr,
}

type AstExprBinary = {
	cstNode: CstExprOp?,
	kind: "ExprBinary",
	location: Location,
	op: number,
	left: AstExpr,
	right: AstExpr,
}

type AstExprTypeAssertion = {
	cstNode: CstExprTypeAssertion?,
	kind: "ExprTypeAssertion",
	location: Location,
	expr: AstExpr,
	annotation: AstType,
}

type AstExprInstantiate = {
	cstNode: CstExprExplicitTypeInstantiation?,
	kind: "ExprInstantiate",
	location: Location,
	expr: AstExpr,
	typeArguments: { AstTypeOrPack },
}

type AstExprIfElse = {
	cstNode: CstExprIfElse?,
	kind: "ExprIfElse",
	location: Location,
	condition: AstExpr,
	hasThen: boolean,
	trueExpr: AstExpr,
	hasElse: boolean,
	falseExpr: AstExpr,
}

type AstExprInterpString = {
	cstNode: CstExprInterpString?,
	kind: "ExprInterpString",
	location: Location,
	strings: { string },
	expressions: { AstExpr },
}

type AstExprError = {
	kind: "ExprError",
	location: Location,
	expressions: { AstExpr },
	messageIndex: number,
}

type AstStatBlock = {
	cstNode: CstStatDo?,
	kind: "StatBlock",
	location: Location,
	body: { AstStat },
	hasEnd: boolean,
	hasSemicolon: boolean?,
}

type AstStatIf = {
	kind: "StatIf",
	location: Location,
	condition: AstExpr,
	thenbody: AstStatBlock,
	elsebody: AstStat?,
	thenLocation: Location?,
	elseLocation: Location?,
	hasSemicolon: boolean?,
}

type AstStatWhile = {
	kind: "StatWhile",
	location: Location,
	condition: AstExpr,
	body: AstStatBlock,
	hasDo: boolean,
	doLocation: Location,
	hasSemicolon: boolean?,
}

type AstStatRepeat = {
	cstNode: CstStatRepeat?,
	kind: "StatRepeat",
	location: Location,
	condition: AstExpr,
	body: AstStatBlock,
	hasUntil: boolean,
	hasSemicolon: boolean?,
}

type AstStatBreak = {
	kind: "StatBreak",
	location: Location,
	hasSemicolon: boolean?
}

type AstStatContinue = {
	kind: "StatContinue",
	location: Location,
	hasSemicolon: boolean?
}

type AstStatReturn = {
	cstNode: CstStatReturn?,
	kind: "StatReturn",
	location: Location,
	list: { AstExpr },
	hasSemicolon: boolean?,
}
type AstStatExpr = {
	kind: "StatExpr",
	location: Location,
	expr: AstExpr,
	hasSemicolon: boolean?
}

type AstStatLocal = {
	cstNode: CstStatLocal?,
	kind: "StatLocal",
	location: Location,
	vars: { AstLocal },
	values: { AstExpr },
	equalsSignLocation: Location?,
	isConst: boolean?,
	isExported: boolean?,
	keywordLocation: Location?,
	hasSemicolon: boolean?,
}

type AstStatFor = {
	cstNode: CstStatFor?,
	kind: "StatFor",
	location: Location,
	var: AstLocal,
	from: AstExpr,
	to: AstExpr,
	step: AstExpr?,
	body: AstStatBlock,
	hasDo: boolean,
	doLocation: Location,
	hasSemicolon: boolean?,
}

type AstStatForIn = {
	cstNode: CstStatForIn?,
	kind: "StatForIn",
	location: Location,
	vars: { AstLocal },
	values: { AstExpr },
	body: AstStatBlock,
	hasIn: boolean,
	inLocation: Location,
	hasDo: boolean,
	doLocation: Location,
	hasSemicolon: boolean?,
}

type AstStatAssign = {
	cstNode: CstStatAssign?,
	kind: "StatAssign",
	location: Location,
	vars: { AstExpr },
	values: { AstExpr },
	hasSemicolon: boolean?,
}

type AstStatCompoundAssign = {
	cstNode: CstStatCompoundAssign?,
	kind: "StatCompoundAssign",
	location: Location,
	op: number,
	var: AstExpr,
	value: AstExpr,
	hasSemicolon: boolean?,
}

type AstStatFunction = {
	cstNode: CstStatFunction?,
	kind: "StatFunction",
	location: Location,
	name: AstExpr,
	func: AstExprFunction,
	hasSemicolon: boolean?,
}

type AstStatLocalFunction = {
	cstNode: CstStatLocalFunction?,
	kind: "StatLocalFunction",
	location: Location,
	name: AstLocal?,
	func: AstExprFunction,
	isConst: boolean?,
	constKeywordBegin: Position?,
	hasSemicolon: boolean?,
}

type AstStatTypeAlias = {
	cstNode: CstStatTypeAlias?,
	kind: "StatTypeAlias",
	location: Location,
	name: string,
	nameLocation: Location,
	generics: { AstGenericType },
	genericPacks: { AstGenericTypePack },
	type: AstType,
	exported: boolean,
	hasSemicolon: boolean?,
}

type AstStatTypeFunction = {
	cstNode: CstStatTypeFunction?,
	kind: "StatTypeFunction",
	location: Location,
	name: string,
	nameLocation: Location,
	body: AstExprFunction,
	exported: boolean,
	hasErrors: boolean,
	hasSemicolon: boolean?,
}

type AstStatDeclareGlobal = {
	kind: "StatDeclareGlobal",
	location: Location,
	name: string,
	nameLocation: Location,
	type: AstType,
	hasSemicolon: boolean?,
}

type AstStatDeclareFunction = {
	kind: "StatDeclareFunction",
	location: Location,
	attributes: { AstAttr },
	name: string,
	nameLocation: Location,
	generics: { AstGenericType },
	genericPacks: { AstGenericTypePack },
	params: AstTypeList,
	paramNames: { AstArgumentName },
	vararg: boolean,
	varargLocation: Location?,
	retTypes: AstTypePack,
	hasSemicolon: boolean?,
}

type AstTableProp = {
	kind: "TableProp",
	name: AstName,
	location: Location,
	type: AstType,
	access: AstTableAccess,
	accessLocation: Location?,
}

type AstTableIndexer = {
	kind: "TableIndexer",
	indexType: AstType,
	resultType: AstType,
	location: Location,
	access: AstTableAccess,
	accessLocation: Location?,
}

type AstDeclaredExternTypeProperty = {
	kind: "DeclaredExternTypeProperty",
	name: AstName,
	nameLocation: Location,
	type: AstType,
	isMethod: boolean,
	location: Location,
	access: AstTableAccess,
}

type AstClassProperty = {
	kind: "ClassProperty",
	qualifierLocation: Location,
	name: AstName,
	nameLocation: Location,
	typeColonLocation: Location?,
	type: AstType?,
}

type AstClassMethod = {
	kind: "ClassMethod",
	qualifierLocation: Location?,
	keywordLocation: Location,
	functionName: AstName,
	nameLocation: Location,
	func: AstExprFunction,
}

type AstClassMember = AstClassProperty | AstClassMethod

type AstStatClass = {
	kind: "StatClass",
	location: Location,
	name: AstLocal,
	super: AstExpr?,
	members: { AstClassMember },
	exported: boolean,
	open: boolean,
	hasSemicolon: boolean?,
}

type AstStatDeclareExternType = {
	kind: "StatDeclareExternType",
	location: Location,
	name: string,
	superName: string?,
	props: { AstDeclaredExternTypeProperty },
	indexer: AstTableIndexer?,
	hasSemicolon: boolean?,
}

type AstStatError = {
	kind: "StatError",
	location: Location,
	expressions: { AstExpr },
	statements: { AstStat },
	messageIndex: number,
	hasSemicolon: boolean?,
}

type AstTypeReference = {
	cstNode: CstTypeReference?,
	kind: "TypeReference",
	location: Location,
	hasParameterList: boolean,
	prefix: string?,
	prefixLocation: Location?,
	prefixLocal: AstLocal?,
	name: string,
	nameLocation: Location,
	parameters: { AstTypeOrPack },
}

type AstTypeTable = {
	cstNode: CstTypeTable?,
	kind: "TypeTable",
	location: Location,
	props: { AstTableProp },
	indexer: AstTableIndexer?,
}

type AstTypeFunction = {
	cstNode: CstTypeFunction?,
	kind: "TypeFunction",
	location: Location,
	attributes: { AstAttr },
	generics: { AstGenericType },
	genericPacks: { AstGenericTypePack },
	argTypes: AstTypeList,
	argNames: { AstArgumentName | boolean },
	returnTypes: AstTypePack,
}

type AstTypeTypeof = {
	cstNode: CstTypeTypeof?,
	kind: "TypeTypeof",
	location: Location,
	expr: AstExpr,
}

type AstTypeUnion = {
	cstNode: CstTypeUnion?,
	kind: "TypeUnion",
	location: Location,
	types: { AstType },
}

type AstTypeIntersection = {
	cstNode: CstTypeIntersection?,
	kind: "TypeIntersection",
	location: Location,
	types: { AstType },
}

type AstTypeSingletonBool = {
	kind: "TypeSingletonBool",
	location: Location,
	value: boolean,
}

type AstTypeSingletonString = {
	cstNode: CstTypeSingletonString?,
	kind: "TypeSingletonString",
	location: Location,
	value: string,
}

type AstTypeGroup = {
	cstNode: CstTypeGroup?,
	kind: "TypeGroup",
	location: Location,
	type: AstType,
}

type AstTypeError = {
	kind: "TypeError",
	location: Location,
	types: { AstType },
	isMissing: boolean,
	messageIndex: number,
}

type AstTypeOptional = {
	kind: "TypeOptional",
	location: Location,
}

type AstTypePackExplicit = {
	cstNode: CstTypePackExplicit?,
	kind: "TypePackExplicit",
	location: Location,
	types: { AstType },
	tailType: AstTypePack?,
}

type AstTypePackVariadic = {
	kind: "TypePackVariadic",
	location: Location,
	variadicType: AstType,
}

type AstTypePackGeneric = {
	cstNode: CstTypePackGeneric?,
	kind: "TypePackGeneric",
	location: Location,
	genericName: string,
}

type Binding = {
	name: AstName,
	location: Location,
	annotation: AstType?,
	colonPosition: Position?,
	isConst: boolean?,
}

type BindingList = { Binding }
type Attrs = { AstAttr }

type CstAttr = {
	kind: "CstAttr",
	hasAt: boolean,
}

type CstParametrizedAttr = {
	kind: "CstParametrizedAttr",
	openParenPosition: Position,
	closeParenPosition: Position,
	argsCommaPositions: { Position },
}

type CstAttrList = {
	kind: "CstAttrList",
	atBracketPosition: Position,
	closeBracketPosition: Position,
	commaPositions: { Position },
}

type CstExprGroup = {
	kind: "CstExprGroup",
	closePosition: Position,
}

type CstExprConstantNumber = {
	kind: "CstExprConstantNumber",
	value: string?,
}

type CstExprConstantInteger = {
	kind: "CstExprConstantInteger",
	value: string?,
}

type CstExprConstantString = {
	kind: "CstExprConstantString",
	sourceString: string?,
	quoteStyle: number,
	blockDepth: number,
}

type CstTypeInstantiation = {
	kind: "CstTypeInstantiation",
	leftArrow1Position: Position,
	leftArrow2Position: Position?,
	commaPositions: { Position },
	rightArrow1Position: Position?,
	rightArrow2Position: Position,
}

type CstExprCall = {
	kind: "CstExprCall",
	openParens: Position?,
	closeParens: Position?,
	commaPositions: { Position },
	explicitTypes: CstTypeInstantiation?,
}

type CstExprIndexExpr = {
	kind: "CstExprIndexExpr",
	openBracketPosition: Position,
	closeBracketPosition: Position,
}

type CstExprFunction = {
	kind: "CstExprFunction",
	attrLists: { CstAttrList },
	functionKeywordPosition: Position,
	openGenericsPosition: Position,
	genericsCommaPositions: { Position },
	closeGenericsPosition: Position,
	argsAnnotationColonPositions: { Position? },
	argsCommaPositions: { Position },
	varargAnnotationColonPosition: Position?,
	returnSpecifierPosition: Position,
}

type CstExprTableItem = {
	kind: "Record" | "General" | "List",
	equalsPosition: Position?,
	separator: number?,
	separatorPosition: Position,
	indexerOpenPosition: Position?,
	indexerClosePosition: Position?,
}

type CstExprTable = {
	kind: "CstExprTable",
	items: { CstExprTableItem },
}

type CstExprOp = {
	kind: "CstExprOp",
	opPosition: Position,
}

type CstExprTypeAssertion = {
	kind: "CstExprTypeAssertion",
	opPosition: Position,
}

type CstExprIfElse = {
	kind: "CstExprIfElse",
	thenPosition: Position,
	elsePosition: Position,
	isElseIf: boolean,
}

type CstExprInterpString = {
	kind: "CstExprInterpString",
	sourceStrings: { string },
	stringPositions: { Position },
}

type CstExprExplicitTypeInstantiation = {
	kind: "CstExprExplicitTypeInstantiation",
	instantiation: CstTypeInstantiation,
}

type CstStatDo = {
	kind: "CstStatDo",
	statsStart: Position,
	endPosition: Position,
}

type CstStatRepeat = {
	kind: "CstStatRepeat",
	untilPosition: Position,
}

type CstStatReturn = {
	kind: "CstStatReturn",
	commaPositions: { Position },
}

type CstStatLocal = {
	kind: "CstStatLocal",
	varsAnnotationColonPositions: { Position? },
	varsCommaPositions: { Position },
	valuesCommaPositions: { Position },
}

type CstStatFor = {
	kind: "CstStatFor",
	annotationColonPosition: Position?,
	equalsPosition: Position,
	endCommaPosition: Position,
	stepCommaPosition: Position?,
}

type CstStatForIn = {
	kind: "CstStatForIn",
	varsAnnotationColonPositions: { Position? },
	varsCommaPositions: { Position },
	valuesCommaPositions: { Position },
}

type CstStatAssign = {
	kind: "CstStatAssign",
	varsCommaPositions: { Position },
	equalsPosition: Position,
	valuesCommaPositions: { Position },
}

type CstStatCompoundAssign = {
	kind: "CstStatCompoundAssign",
	opPosition: Position,
}

type CstStatFunction = {
	kind: "CstStatFunction",
	attrLists: { CstAttrList },
	functionKeywordPosition: Position,
}

type CstStatLocalFunction = {
	kind: "CstStatLocalFunction",
	attrLists: { CstAttrList },
	localKeywordPosition: Position,
	functionKeywordPosition: Position,
}

type CstGenericType = {
	kind: "CstGenericType",
	defaultEqualsPosition: Position?,
}

type CstGenericTypePack = {
	kind: "CstGenericTypePack",
	ellipsisPosition: Position,
	defaultEqualsPosition: Position?,
}

type CstStatTypeAlias = {
	kind: "CstStatTypeAlias",
	typeKeywordPosition: Position,
	genericsOpenPosition: Position?,
	genericsCommaPositions: { Position },
	genericsClosePosition: Position?,
	equalsPosition: Position,
}

type CstStatTypeFunction = {
	kind: "CstStatTypeFunction",
	typeKeywordPosition: Position,
	functionKeywordPosition: Position,
}

type CstTypeReference = {
	kind: "CstTypeReference",
	prefixPointPosition: Position?,
	openParametersPosition: Position?,
	parametersCommaPositions: { Position },
	closeParametersPosition: Position?,
}

type CstTypeTableItem = {
	kind: "Property" | "StringProperty" | "Indexer",
	colonPosition: Position?,
	separator: number?,
	separatorPosition: Position?,
	indexerOpenPosition: Position?,
	indexerClosePosition: Position?,
	stringInfo: CstExprConstantString?,
	stringPosition: Position?,
}

type CstTypeTable = {
	kind: "CstTypeTable",
	items: { CstTypeTableItem },
	isArray: boolean,
}

type CstTypeFunction = {
	kind: "CstTypeFunction",
	openGenericsPosition: Position,
	genericsCommaPositions: { Position },
	closeGenericsPosition: Position,
	openArgsPosition: Position,
	argumentNameColonPositions: { Position | boolean },
	argumentsCommaPositions: { Position },
	closeArgsPosition: Position,
	returnArrowPosition: Position,
}

type CstTypeTypeof = {
	kind: "CstTypeTypeof",
	openPosition: Position,
	closePosition: Position,
}

type CstTypeUnion = {
	kind: "CstTypeUnion",
	leadingPosition: Position?,
	separatorPositions: { Position },
}

type CstTypeIntersection = {
	kind: "CstTypeIntersection",
	leadingPosition: Position?,
	separatorPositions: { Position },
}

type CstTypeSingletonString = {
	kind: "CstTypeSingletonString",
	sourceString: string?,
	quoteStyle: number,
	blockDepth: number,
}

type CstTypeGroup = {
	kind: "CstTypeGroup",
	closePosition: Position,
}

type CstTypePackExplicit = {
	kind: "CstTypePackExplicit",
	openParenthesesPosition: Position?,
	closeParenthesesPosition: Position?,
	commaPositions: { Position }?,
}

type CstTypePackGeneric = {
	kind: "CstTypePackGeneric",
	ellipsisPosition: Position,
}

type AstNode = AstExpr
| AstStat
| AstType
| AstTypePack
| AstGenericType
| AstGenericTypePack
| AstAttr
| AstLocal

type ParseError = {
	location: Location,
	message: string,
}

type Options = {
	allowDeclarationSyntax: boolean?,
	captureComments: boolean?,
	noErrorLimit: boolean?,
	parseFragment: {
		localMap: { [string]: AstLocal? },
		localStack: { AstLocal? },
		resumePosition: Position,
	}?,
	storeCstData: boolean?,
}

type Lexeme = {
	type: number,
	location: Location,
}

type Comment = {
	type: number,
	location: Location,
}

type HotComment = {
	header: boolean,
	content: string,
	location: Location,
}

type FunctionState = {
	vararg: boolean,
	loopDepth: number,
}

type Result = {
	root: AstStatBlock?,
	lines: number,
	commentLocations: { Comment },
	hotcomments: { HotComment },
	errors: { ParseError },
}


local function Main()
-- // Parser Settings

const Flags = {
	LuauIntegerType2 = true,
	LuauExportValueSyntax = true,
	DebugLuauNoInline = false,
	DebugLuauUserDefinedClasses = false,
	LuauAllowGlobalDeclarationToBeCalledClass = false,
	LuauDisallowExternClassInTypeDefinitions = false,
	LuauStoreConstKeywordBegin = true,
	LuauTrackPrefixLocal = false,
	LuauNoDuplicateBinaryPrefix = false,
	LuauSingleTypeOptionalPackReturnsAttributeParens = false,
}

const LuauRecursionLimit = 1000
const LuauTypeLengthLimit = 1000
const LuauParseErrorLimit = 100

-- // Requires modules

const Confusables = {
	[34] = '"',
	[48] = "O",
	[49] = "l",
	[73] = "l",
	[96] = "'",
	[109] = "rn",
	[124] = "l",
	[160] = " ",
	[180] = "'",
	[184] = ",",
	[198] = "AE",
	[215] = "x",
	[230] = "ae",
	[305] = "i",
	[306] = "lJ",
	[307] = "ij",
	[329] = "'n",
	[338] = "OE",
	[339] = "oe",
	[383] = "f",
	[385] = "'B",
	[388] = "b",
	[391] = "C'",
	[394] = "'D",
	[397] = "g",
	[403] = "G'",
	[406] = "l",
	[408] = "K'",
	[416] = "O'",
	[417] = "o'",
	[420] = "'P",
	[422] = "R",
	[423] = "2",
	[428] = "'T",
	[435] = "'Y",
	[439] = "3",
	[444] = "5",
	[445] = "s",
	[448] = "l",
	[449] = "ll",
	[451] = "!",
	[455] = "LJ",
	[456] = "Lj",
	[457] = "lj",
	[458] = "NJ",
	[459] = "Nj",
	[460] = "nj",
	[497] = "DZ",
	[498] = "Dz",
	[499] = "dz",
	[540] = "3",
	[546] = "8",
	[547] = "8",
	[577] = "?",
	[593] = "a",
	[609] = "g",
	[611] = "y",
	[617] = "i",
	[618] = "i",
	[623] = "w",
	[651] = "u",
	[655] = "y",
	[660] = "?",
	[675] = "dz",
	[678] = "ts",
	[682] = "ls",
	[683] = "lz",
	[697] = "'",
	[698] = '"',
	[699] = "'",
	[700] = "'",
	[701] = "'",
	[702] = "'",
	[706] = "<",
	[707] = ">",
	[708] = "^",
	[710] = "^",
	[712] = "'",
	[714] = "'",
	[715] = "'",
	[720] = ":",
	[727] = "-",
	[731] = "i",
	[732] = "~",
	[733] = '"',
	[750] = '"',
	[756] = "'",
	[758] = '"',
	[760] = ":",
	[884] = "'",
	[890] = "i",
	[894] = ";",
	[895] = "J",
	[900] = "'",
	[913] = "A",
	[914] = "B",
	[917] = "E",
	[918] = "Z",
	[919] = "H",
	[921] = "l",
	[922] = "K",
	[924] = "M",
	[925] = "N",
	[927] = "O",
	[929] = "P",
	[932] = "T",
	[933] = "Y",
	[935] = "X",
	[945] = "a",
	[947] = "y",
	[953] = "i",
	[957] = "v",
	[959] = "o",
	[961] = "p",
	[963] = "o",
	[965] = "u",
	[978] = "Y",
	[988] = "F",
	[1000] = "2",
	[1009] = "p",
	[1010] = "c",
	[1011] = "j",
	[1017] = "C",
	[1018] = "M",
	[1029] = "S",
	[1030] = "l",
	[1032] = "J",
	[1040] = "A",
	[1042] = "B",
	[1045] = "E",
	[1047] = "3",
	[1050] = "K",
	[1052] = "M",
	[1053] = "H",
	[1054] = "O",
	[1056] = "P",
	[1057] = "C",
	[1058] = "T",
	[1059] = "Y",
	[1061] = "X",
	[1067] = "bl", 
	[1068] = "b",
	[1070] = "lO", 
	[1072] = "a",
	[1073] = "6",
	[1075] = "r",
	[1077] = "e",
	[1086] = "o",
	[1088] = "p",
	[1089] = "c",
	[1091] = "y",
	[1093] = "x",
	[1109] = "s",
	[1110] = "i",
	[1112] = "j",
	[1121] = "w",
	[1140] = "V",
	[1141] = "v",
	[1169] = "r'", 
	[1198] = "Y",
	[1199] = "y",
	[1211] = "h",
	[1213] = "e",
	[1216] = "l",
	[1231] = "i",
	[1236] = "AE", 
	[1237] = "ae", 
	[1248] = "3",
	[1281] = "d",
	[1292] = "G",
	[1307] = "q",
	[1308] = "W",
	[1309] = "w",
	[1357] = "U",
	[1359] = "S",
	[1365] = "O",
	[1370] = "'",
	[1373] = "'",
	[1377] = "w",
	[1379] = "q",
	[1382] = "q",
	[1392] = "h",
	[1400] = "n",
	[1404] = "n",
	[1405] = "u",
	[1409] = "g",
	[1412] = "f",
	[1413] = "o",
	[1417] = ":",
	[1472] = "l",
	[1475] = ":",
	[1493] = "l",
	[1496] = "v",
	[1497] = "'",
	[1503] = "l",
	[1505] = "o",
	[1520] = "ll", 
	[1521] = "l'", 
	[1522] = '"', 
	[1523] = "'",
	[1524] = '"', 
	[1549] = ",",
	[1575] = "l",
	[1607] = "o",
	[1632] = ".",
	[1633] = "l",
	[1637] = "o",
	[1639] = "V",
	[1643] = ",",
	[1645] = "*",
	[1726] = "o",
	[1729] = "o",
	[1748] = "-",
	[1749] = "o",
	[1776] = ".",
	[1777] = "l",
	[1781] = "o",
	[1783] = "V",
	[1793] = ".",
	[1794] = ".",
	[1795] = ":",
	[1796] = ":",
	[1984] = "O",
	[1994] = "l",
	[2036] = "'",
	[2037] = "'",
	[2042] = "_",
	[2307] = ":",
	[2406] = "o",
	[2429] = "?",
	[2534] = "O",
	[2538] = "8",
	[2541] = "9",
	[2662] = "o",
	[2663] = "9",
	[2666] = "8",
	[2691] = ":",
	[2790] = "o",
	[2819] = "8",
	[2848] = "O",
	[2918] = "O",
	[2920] = "9",
	[3046] = "o",
	[3074] = "o",
	[3174] = "o",
	[3202] = "o",
	[3302] = "o",
	[3330] = "o",
	[3360] = "o",
	[3430] = "o",
	[3437] = "9",
	[3458] = "o",
	[3664] = "o",
	[3792] = "o",
	[4125] = "o",
	[4160] = "o",
	[4327] = "y",
	[4351] = "o",
	[4608] = "U",
	[4816] = "O",
	[5024] = "D",
	[5025] = "R",
	[5026] = "T",
	[5028] = "O'", 
	[5029] = "i",
	[5033] = "Y",
	[5034] = "A",
	[5035] = "J",
	[5036] = "E",
	[5038] = "?",
	[5043] = "W",
	[5047] = "M",
	[5051] = "H",
	[5053] = "Y",
	[5056] = "G",
	[5058] = "h",
	[5059] = "Z",
	[5070] = "4",
	[5071] = "b",
	[5074] = "R",
	[5076] = "W",
	[5077] = "S",
	[5081] = "V",
	[5082] = "S",
	[5086] = "L",
	[5087] = "C",
	[5090] = "P",
	[5094] = "K",
	[5095] = "d",
	[5102] = "6",
	[5107] = "G",
	[5108] = "B",
	[5120] = "=",
	[5167] = "V",
	[5171] = ">",
	[5176] = "<",
	[5194] = "'",
	[5196] = "U",
	[5223] = "U'", 
	[5229] = "P",
	[5231] = "d",
	[5254] = "P'", 
	[5255] = "d'", 
	[5261] = "J",
	[5290] = "L",
	[5311] = "2",
	[5441] = "x",
	[5500] = "H",
	[5501] = "x",
	[5511] = "R",
	[5551] = "b",
	[5556] = "F",
	[5573] = "A",
	[5598] = "D",
	[5610] = "D",
	[5616] = "M",
	[5623] = "B",
	[5741] = "X",
	[5742] = "x",
	[5760] = " ",
	[5810] = "<",
	[5815] = "X",
	[5825] = "l",
	[5836] = "'",
	[5845] = "K",
	[5846] = "M",
	[5868] = ":",
	[5869] = "+",
	[5941] = "/",
	[6147] = ":",
	[6153] = ":",
	[7379] = '"', 
	[7428] = "c",
	[7439] = "o",
	[7441] = "o",
	[7452] = "u",
	[7456] = "v",
	[7457] = "w",
	[7458] = "z",
	[7462] = "r",
	[7531] = "ue", 
	[7555] = "g",
	[7564] = "y",
	[7837] = "f",
	[7935] = "y",
	[8125] = "'",
	[8126] = "i",
	[8127] = "'",
	[8128] = "~",
	[8175] = "'",
	[8189] = "'",
	[8190] = "'",
	[8192] = " ",
	[8193] = " ",
	[8194] = " ",
	[8195] = " ",
	[8196] = " ",
	[8197] = " ",
	[8198] = " ",
	[8199] = " ",
	[8200] = " ",
	[8201] = " ",
	[8202] = " ",
	[8208] = "-",
	[8209] = "-",
	[8210] = "-",
	[8211] = "-",
	[8214] = "ll", 
	[8216] = "'",
	[8217] = "'",
	[8218] = ",",
	[8219] = "'",
	[8220] = '"', 
	[8221] = '"', 
	[8223] = '"', 
	[8228] = ".",
	[8229] = "..", 
	[8230] = "...",
	[8232] = " ",
	[8233] = " ",
	[8239] = " ",
	[8242] = "'",
	[8243] = '"', 
	[8244] = "'''",
	[8245] = "'",
	[8246] = '"', 
	[8247] = "'''",
	[8249] = "<",
	[8250] = ">",
	[8252] = "!!", 
	[8257] = "/",
	[8259] = "-",
	[8260] = "/",
	[8263] = "??", 
	[8264] = "?!", 
	[8265] = "!?", 
	[8270] = "*",
	[8275] = "~",
	[8279] = "''''",
	[8282] = ":",
	[8287] = " ",
	[8360] = "Rs", 
	[8374] = "lt", 
	[8448] = "a/c",
	[8449] = "a/s",
	[8450] = "C",
	[8453] = "c/o",
	[8454] = "c/u",
	[8458] = "g",
	[8459] = "H",
	[8460] = "H",
	[8461] = "H",
	[8462] = "h",
	[8464] = "l",
	[8465] = "l",
	[8466] = "L",
	[8467] = "l",
	[8469] = "N",
	[8470] = "No", 
	[8473] = "P",
	[8474] = "Q",
	[8475] = "R",
	[8476] = "R",
	[8477] = "R",
	[8481] = "TEL",
	[8484] = "Z",
	[8488] = "Z",
	[8490] = "K",
	[8492] = "B",
	[8493] = "C",
	[8494] = "e",
	[8495] = "e",
	[8496] = "E",
	[8497] = "F",
	[8499] = "M",
	[8500] = "o",
	[8505] = "i",
	[8507] = "FAX",
	[8509] = "y",
	[8517] = "D",
	[8518] = "d",
	[8519] = "e",
	[8520] = "i",
	[8521] = "j",
	[8544] = "l",
	[8545] = "ll", 
	[8546] = "lll",
	[8547] = "lV", 
	[8548] = "V",
	[8549] = "Vl", 
	[8550] = "Vll",
	[8551] = "Vlll",
	[8552] = "lX", 
	[8553] = "X",
	[8554] = "Xl", 
	[8555] = "Xll",
	[8556] = "L",
	[8557] = "C",
	[8558] = "D",
	[8559] = "M",
	[8560] = "i",
	[8561] = "ii", 
	[8562] = "iii",
	[8563] = "iv", 
	[8564] = "v",
	[8565] = "vi", 
	[8566] = "vii",
	[8567] = "viii",
	[8568] = "ix", 
	[8569] = "x",
	[8570] = "xi", 
	[8571] = "xii",
	[8572] = "l",
	[8573] = "c",
	[8574] = "d",
	[8575] = "rn", 
	[8722] = "-",
	[8725] = "/",
	[8726] = "\\", 
	[8727] = "*",
	[8734] = "oo", 
	[8739] = "l",
	[8741] = "ll", 
	[8744] = "v",
	[8746] = "U",
	[8758] = ":",
	[8764] = "~",
	[8810] = "<<", 
	[8811] = ">>", 
	[8868] = "T",
	[8897] = "v",
	[8899] = "U",
	[8920] = "<<<",
	[8921] = ">>>",
	[8959] = "E",
	[9075] = "i",
	[9076] = "p",
	[9082] = "a",
	[9213] = "l",
	[9290] = "\\\\",
	[9332] = "(l)",
	[9333] = "(2)",
	[9334] = "(3)",
	[9335] = "(4)",
	[9336] = "(5)",
	[9337] = "(6)",
	[9338] = "(7)",
	[9339] = "(8)",
	[9340] = "(9)",
	[9341] = "(lO)",
	[9342] = "(ll)",
	[9343] = "(l2)",
	[9344] = "(l3)",
	[9345] = "(l4)",
	[9346] = "(l5)",
	[9347] = "(l6)",
	[9348] = "(l7)",
	[9349] = "(l8)",
	[9350] = "(l9)",
	[9351] = "(2O)",
	[9352] = "l.", 
	[9353] = "2.", 
	[9354] = "3.", 
	[9355] = "4.", 
	[9356] = "5.", 
	[9357] = "6.", 
	[9358] = "7.", 
	[9359] = "8.", 
	[9360] = "9.", 
	[9361] = "lO.",
	[9362] = "ll.",
	[9363] = "l2.",
	[9364] = "l3.",
	[9365] = "l4.",
	[9366] = "l5.",
	[9367] = "l6.",
	[9368] = "l7.",
	[9369] = "l8.",
	[9370] = "l9.",
	[9371] = "2O.",
	[9372] = "(a)",
	[9373] = "(b)",
	[9374] = "(c)",
	[9375] = "(d)",
	[9376] = "(e)",
	[9377] = "(f)",
	[9378] = "(g)",
	[9379] = "(h)",
	[9380] = "(i)",
	[9381] = "(j)",
	[9382] = "(k)",
	[9383] = "(l)",
	[9384] = "(rn)",
	[9385] = "(n)",
	[9386] = "(o)",
	[9387] = "(p)",
	[9388] = "(q)",
	[9389] = "(r)",
	[9390] = "(s)",
	[9391] = "(t)",
	[9392] = "(u)",
	[9393] = "(v)",
	[9394] = "(w)",
	[9395] = "(x)",
	[9396] = "(y)",
	[9397] = "(z)",
	[9585] = "/",
	[9587] = "X",
	[10088] = "(", 
	[10089] = ")", 
	[10094] = "<", 
	[10095] = ">", 
	[10098] = "(", 
	[10099] = ")", 
	[10100] = "{", 
	[10101] = "}", 
	[10133] = "+", 
	[10134] = "-", 
	[10187] = "/", 
	[10189] = "\\",
	[10201] = "T", 
	[10539] = "x", 
	[10540] = "x", 
	[10741] = "\\",
	[10744] = "/", 
	[10745] = "\\",
	[10784] = ">>",
	[10799] = "x", 
	[10868] = "::=",
	[10869] = "==",
	[10870] = "===",
	[10917] = "><",
	[11003] = "///",
	[11005] = "//",
	[11397] = "r", 
	[11406] = "H", 
	[11410] = "l", 
	[11412] = "K", 
	[11416] = "M", 
	[11418] = "N", 
	[11422] = "O", 
	[11423] = "o", 
	[11426] = "P", 
	[11427] = "p", 
	[11428] = "C", 
	[11429] = "c", 
	[11430] = "T", 
	[11432] = "Y", 
	[11436] = "X", 
	[11450] = "-", 
	[11462] = "/", 
	[11466] = "9", 
	[11468] = "3", 
	[11472] = "L", 
	[11474] = "6", 
	[11513] = "\\\\", 
	[11576] = "V", 
	[11577] = "E", 
	[11599] = "l", 
	[11601] = "!", 
	[11604] = "O", 
	[11605] = "Q", 
	[11613] = "X", 
	[11816] = "((",
	[11817] = "))",
	[11840] = "=", 
	[12034] = "\\",
	[12035] = "/", 
	[12291] = '"',
	[12295] = "O", 
	[12308] = "(", 
	[12309] = ")", 
	[12339] = "/", 
	[12448] = "=", 
	[12494] = "/", 
	[12755] = "/", 
	[12756] = "\\",
	[20022] = "\\",
	[20031] = "/", 
	[42192] = "B", 
	[42193] = "P", 
	[42194] = "d", 
	[42195] = "D", 
	[42196] = "T", 
	[42198] = "G", 
	[42199] = "K", 
	[42201] = "J", 
	[42202] = "C", 
	[42204] = "Z", 
	[42205] = "F", 
	[42207] = "M", 
	[42208] = "N", 
	[42209] = "L", 
	[42210] = "S", 
	[42211] = "R", 
	[42214] = "V", 
	[42215] = "H", 
	[42218] = "W", 
	[42219] = "X", 
	[42220] = "Y", 
	[42222] = "A", 
	[42224] = "E", 
	[42226] = "l", 
	[42227] = "O", 
	[42228] = "U", 
	[42232] = ".", 
	[42233] = ",", 
	[42234] = "..",
	[42235] = ".,",
	[42237] = ":", 
	[42238] = "-.",
	[42239] = "=", 
	[42510] = ".", 
	[42564] = "2", 
	[42567] = "i", 
	[42648] = "OO",
	[42649] = "oo",
	[42719] = "V", 
	[42731] = "?", 
	[42735] = "2", 
	[42792] = "T3",
	[42801] = "s", 
	[42802] = "AA",
	[42803] = "aa",
	[42804] = "AO",
	[42805] = "ao",
	[42806] = "AU",
	[42807] = "au",
	[42808] = "AV",
	[42809] = "av",
	[42810] = "AV",
	[42811] = "av",
	[42812] = "AY",
	[42813] = "ay",
	[42830] = "OO",
	[42831] = "oo",
	[42842] = "2", 
	[42858] = "3", 
	[42862] = "9", 
	[42871] = "tf",
	[42872] = "&", 
	[42889] = ":", 
	[42892] = "'", 
	[42904] = "F", 
	[42905] = "f", 
	[42911] = "u", 
	[42923] = "3", 
	[42930] = "J", 
	[42931] = "X", 
	[42932] = "B", 
	[43826] = "e", 
	[43829] = "f", 
	[43837] = "o", 
	[43847] = "r", 
	[43848] = "r", 
	[43854] = "u", 
	[43858] = "u", 
	[43866] = "y", 
	[43875] = "uo",
	[43893] = "i", 
	[43905] = "r", 
	[43907] = "w", 
	[43923] = "z", 
	[43945] = "v", 
	[43946] = "s", 
	[43951] = "c", 
	[64256] = "ff",
	[64257] = "fi",
	[64258] = "fl",
	[64259] = "ffi",
	[64260] = "ffl",
	[64262] = "st",
	[64422] = "o", 
	[64423] = "o", 
	[64424] = "o", 
	[64425] = "o", 
	[64426] = "o", 
	[64427] = "o", 
	[64428] = "o", 
	[64429] = "o", 
	[64830] = "(", 
	[64831] = ")", 
	[65072] = ":", 
	[65101] = "_", 
	[65102] = "_", 
	[65103] = "_", 
	[65112] = "-", 
	[65128] = "\\",
	[65165] = "l", 
	[65166] = "l", 
	[65257] = "o", 
	[65258] = "o", 
	[65259] = "o", 
	[65260] = "o", 
	[65281] = "!", 
	[65282] = '"',
	[65287] = "'", 
	[65306] = ":", 
	[65313] = "A", 
	[65314] = "B", 
	[65315] = "C", 
	[65317] = "E", 
	[65320] = "H", 
	[65321] = "l", 
	[65322] = "J", 
	[65323] = "K", 
	[65325] = "M", 
	[65326] = "N", 
	[65327] = "O", 
	[65328] = "P", 
	[65331] = "S", 
	[65332] = "T", 
	[65336] = "X", 
	[65337] = "Y", 
	[65338] = "Z", 
	[65339] = "(", 
	[65340] = "\\",
	[65341] = ")", 
	[65344] = "'", 
	[65345] = "a", 
	[65347] = "c", 
	[65349] = "e", 
	[65351] = "g", 
	[65352] = "h", 
	[65353] = "i", 
	[65354] = "j", 
	[65356] = "l", 
	[65359] = "o", 
	[65360] = "p", 
	[65363] = "s", 
	[65366] = "v", 
	[65368] = "x", 
	[65369] = "y", 
	[65512] = "l", 
	[66178] = "B", 
	[66182] = "E", 
	[66183] = "F", 
	[66186] = "l", 
	[66192] = "X", 
	[66194] = "O", 
	[66197] = "P", 
	[66198] = "S", 
	[66199] = "T", 
	[66203] = "+", 
	[66208] = "A", 
	[66209] = "B", 
	[66210] = "C", 
	[66213] = "F", 
	[66219] = "O", 
	[66224] = "M", 
	[66225] = "T", 
	[66226] = "Y", 
	[66228] = "X", 
	[66255] = "H", 
	[66293] = "Z", 
	[66305] = "B", 
	[66306] = "C", 
	[66313] = "l", 
	[66321] = "M", 
	[66325] = "T", 
	[66327] = "X", 
	[66330] = "8", 
	[66335] = "*", 
	[66336] = "l", 
	[66338] = "X", 
	[66564] = "O", 
	[66581] = "C", 
	[66587] = "L", 
	[66592] = "S", 
	[66604] = "o", 
	[66621] = "c", 
	[66632] = "s", 
	[66740] = "R", 
	[66754] = "O", 
	[66766] = "U", 
	[66770] = "7", 
	[66794] = "o", 
	[66806] = "u", 
	[66835] = "N", 
	[66838] = "O", 
	[66840] = "K", 
	[66844] = "C", 
	[66845] = "V", 
	[66853] = "F", 
	[66854] = "L", 
	[66855] = "X", 
	[68176] = ".", 
	[70864] = "O", 
	[71424] = "rn",
	[71430] = "v", 
	[71434] = "w", 
	[71438] = "w", 
	[71439] = "w", 
	[71840] = "V", 
	[71842] = "F", 
	[71843] = "L", 
	[71844] = "Y", 
	[71846] = "E", 
	[71849] = "Z", 
	[71852] = "9", 
	[71854] = "E", 
	[71855] = "4", 
	[71858] = "L", 
	[71861] = "O", 
	[71864] = "U", 
	[71867] = "5", 
	[71868] = "T", 
	[71872] = "v", 
	[71873] = "s", 
	[71874] = "F", 
	[71875] = "i", 
	[71876] = "z", 
	[71878] = "7", 
	[71880] = "o", 
	[71882] = "3", 
	[71884] = "9", 
	[71893] = "6", 
	[71894] = "9", 
	[71895] = "o", 
	[71896] = "u", 
	[71900] = "y", 
	[71904] = "O", 
	[71907] = "rn",
	[71909] = "Z", 
	[71910] = "W", 
	[71913] = "C", 
	[71916] = "X", 
	[71919] = "W", 
	[71922] = "C", 
	[93960] = "V", 
	[93962] = "T", 
	[93974] = "L", 
	[93992] = "l", 
	[94005] = "R", 
	[94010] = "S", 
	[94011] = "3", 
	[94015] = ">", 
	[94016] = "A", 
	[94018] = "U", 
	[94019] = "Y", 
	[94033] = "'", 
	[94034] = "'", 
	[119060] = "{",
	[119149] = ".",
	[119302] = "3",
	[119309] = "V",
	[119311] = "\\",
	[119314] = "7",
	[119315] = "F",
	[119318] = "R",
	[119338] = "L",
	[119350] = "<",
	[119351] = ">",
	[119354] = "/",
	[119355] = "\\",
	[119808] = "A",
	[119809] = "B",
	[119810] = "C",
	[119811] = "D",
	[119812] = "E",
	[119813] = "F",
	[119814] = "G",
	[119815] = "H",
	[119816] = "l",
	[119817] = "J",
	[119818] = "K",
	[119819] = "L",
	[119820] = "M",
	[119821] = "N",
	[119822] = "O",
	[119823] = "P",
	[119824] = "Q",
	[119825] = "R",
	[119826] = "S",
	[119827] = "T",
	[119828] = "U",
	[119829] = "V",
	[119830] = "W",
	[119831] = "X",
	[119832] = "Y",
	[119833] = "Z",
	[119834] = "a",
	[119835] = "b",
	[119836] = "c",
	[119837] = "d",
	[119838] = "e",
	[119839] = "f",
	[119840] = "g",
	[119841] = "h",
	[119842] = "i",
	[119843] = "j",
	[119844] = "k",
	[119845] = "l",
	[119846] = "rn",
	[119847] = "n",
	[119848] = "o",
	[119849] = "p",
	[119850] = "q",
	[119851] = "r",
	[119852] = "s",
	[119853] = "t",
	[119854] = "u",
	[119855] = "v",
	[119856] = "w",
	[119857] = "x",
	[119858] = "y",
	[119859] = "z",
	[119860] = "A",
	[119861] = "B",
	[119862] = "C",
	[119863] = "D",
	[119864] = "E",
	[119865] = "F",
	[119866] = "G",
	[119867] = "H",
	[119868] = "l",
	[119869] = "J",
	[119870] = "K",
	[119871] = "L",
	[119872] = "M",
	[119873] = "N",
	[119874] = "O",
	[119875] = "P",
	[119876] = "Q",
	[119877] = "R",
	[119878] = "S",
	[119879] = "T",
	[119880] = "U",
	[119881] = "V",
	[119882] = "W",
	[119883] = "X",
	[119884] = "Y",
	[119885] = "Z",
	[119886] = "a",
	[119887] = "b",
	[119888] = "c",
	[119889] = "d",
	[119890] = "e",
	[119891] = "f",
	[119892] = "g",
	[119894] = "i",
	[119895] = "j",
	[119896] = "k",
	[119897] = "l",
	[119898] = "rn",
	[119899] = "n",
	[119900] = "o",
	[119901] = "p",
	[119902] = "q",
	[119903] = "r",
	[119904] = "s",
	[119905] = "t",
	[119906] = "u",
	[119907] = "v",
	[119908] = "w",
	[119909] = "x",
	[119910] = "y",
	[119911] = "z",
	[119912] = "A",
	[119913] = "B",
	[119914] = "C",
	[119915] = "D",
	[119916] = "E",
	[119917] = "F",
	[119918] = "G",
	[119919] = "H",
	[119920] = "l",
	[119921] = "J",
	[119922] = "K",
	[119923] = "L",
	[119924] = "M",
	[119925] = "N",
	[119926] = "O",
	[119927] = "P",
	[119928] = "Q",
	[119929] = "R",
	[119930] = "S",
	[119931] = "T",
	[119932] = "U",
	[119933] = "V",
	[119934] = "W",
	[119935] = "X",
	[119936] = "Y",
	[119937] = "Z",
	[119938] = "a",
	[119939] = "b",
	[119940] = "c",
	[119941] = "d",
	[119942] = "e",
	[119943] = "f",
	[119944] = "g",
	[119945] = "h",
	[119946] = "i",
	[119947] = "j",
	[119948] = "k",
	[119949] = "l",
	[119950] = "rn",
	[119951] = "n",
	[119952] = "o",
	[119953] = "p",
	[119954] = "q",
	[119955] = "r",
	[119956] = "s",
	[119957] = "t",
	[119958] = "u",
	[119959] = "v",
	[119960] = "w",
	[119961] = "x",
	[119962] = "y",
	[119963] = "z",
	[119964] = "A",
	[119966] = "C",
	[119967] = "D",
	[119970] = "G",
	[119973] = "J",
	[119974] = "K",
	[119977] = "N",
	[119978] = "O",
	[119979] = "P",
	[119980] = "Q",
	[119982] = "S",
	[119983] = "T",
	[119984] = "U",
	[119985] = "V",
	[119986] = "W",
	[119987] = "X",
	[119988] = "Y",
	[119989] = "Z",
	[119990] = "a",
	[119991] = "b",
	[119992] = "c",
	[119993] = "d",
	[119995] = "f",
	[119997] = "h",
	[119998] = "i",
	[119999] = "j",
	[120000] = "k",
	[120001] = "l",
	[120002] = "rn",
	[120003] = "n",
	[120005] = "p",
	[120006] = "q",
	[120007] = "r",
	[120008] = "s",
	[120009] = "t",
	[120010] = "u",
	[120011] = "v",
	[120012] = "w",
	[120013] = "x",
	[120014] = "y",
	[120015] = "z",
	[120016] = "A",
	[120017] = "B",
	[120018] = "C",
	[120019] = "D",
	[120020] = "E",
	[120021] = "F",
	[120022] = "G",
	[120023] = "H",
	[120024] = "l",
	[120025] = "J",
	[120026] = "K",
	[120027] = "L",
	[120028] = "M",
	[120029] = "N",
	[120030] = "O",
	[120031] = "P",
	[120032] = "Q",
	[120033] = "R",
	[120034] = "S",
	[120035] = "T",
	[120036] = "U",
	[120037] = "V",
	[120038] = "W",
	[120039] = "X",
	[120040] = "Y",
	[120041] = "Z",
	[120042] = "a",
	[120043] = "b",
	[120044] = "c",
	[120045] = "d",
	[120046] = "e",
	[120047] = "f",
	[120048] = "g",
	[120049] = "h",
	[120050] = "i",
	[120051] = "j",
	[120052] = "k",
	[120053] = "l",
	[120054] = "rn",
	[120055] = "n",
	[120056] = "o",
	[120057] = "p",
	[120058] = "q",
	[120059] = "r",
	[120060] = "s",
	[120061] = "t",
	[120062] = "u",
	[120063] = "v",
	[120064] = "w",
	[120065] = "x",
	[120066] = "y",
	[120067] = "z",
	[120068] = "A",
	[120069] = "B",
	[120071] = "D",
	[120072] = "E",
	[120073] = "F",
	[120074] = "G",
	[120077] = "J",
	[120078] = "K",
	[120079] = "L",
	[120080] = "M",
	[120081] = "N",
	[120082] = "O",
	[120083] = "P",
	[120084] = "Q",
	[120086] = "S",
	[120087] = "T",
	[120088] = "U",
	[120089] = "V",
	[120090] = "W",
	[120091] = "X",
	[120092] = "Y",
	[120094] = "a",
	[120095] = "b",
	[120096] = "c",
	[120097] = "d",
	[120098] = "e",
	[120099] = "f",
	[120100] = "g",
	[120101] = "h",
	[120102] = "i",
	[120103] = "j",
	[120104] = "k",
	[120105] = "l",
	[120106] = "rn",
	[120107] = "n",
	[120108] = "o",
	[120109] = "p",
	[120110] = "q",
	[120111] = "r",
	[120112] = "s",
	[120113] = "t",
	[120114] = "u",
	[120115] = "v",
	[120116] = "w",
	[120117] = "x",
	[120118] = "y",
	[120119] = "z",
	[120120] = "A",
	[120121] = "B",
	[120123] = "D",
	[120124] = "E",
	[120125] = "F",
	[120126] = "G",
	[120128] = "l",
	[120129] = "J",
	[120130] = "K",
	[120131] = "L",
	[120132] = "M",
	[120134] = "O",
	[120138] = "S",
	[120139] = "T",
	[120140] = "U",
	[120141] = "V",
	[120142] = "W",
	[120143] = "X",
	[120144] = "Y",
	[120146] = "a",
	[120147] = "b",
	[120148] = "c",
	[120149] = "d",
	[120150] = "e",
	[120151] = "f",
	[120152] = "g",
	[120153] = "h",
	[120154] = "i",
	[120155] = "j",
	[120156] = "k",
	[120157] = "l",
	[120158] = "rn",
	[120159] = "n",
	[120160] = "o",
	[120161] = "p",
	[120162] = "q",
	[120163] = "r",
	[120164] = "s",
	[120165] = "t",
	[120166] = "u",
	[120167] = "v",
	[120168] = "w",
	[120169] = "x",
	[120170] = "y",
	[120171] = "z",
	[120172] = "A",
	[120173] = "B",
	[120174] = "C",
	[120175] = "D",
	[120176] = "E",
	[120177] = "F",
	[120178] = "G",
	[120179] = "H",
	[120180] = "l",
	[120181] = "J",
	[120182] = "K",
	[120183] = "L",
	[120184] = "M",
	[120185] = "N",
	[120186] = "O",
	[120187] = "P",
	[120188] = "Q",
	[120189] = "R",
	[120190] = "S",
	[120191] = "T",
	[120192] = "U",
	[120193] = "V",
	[120194] = "W",
	[120195] = "X",
	[120196] = "Y",
	[120197] = "Z",
	[120198] = "a",
	[120199] = "b",
	[120200] = "c",
	[120201] = "d",
	[120202] = "e",
	[120203] = "f",
	[120204] = "g",
	[120205] = "h",
	[120206] = "i",
	[120207] = "j",
	[120208] = "k",
	[120209] = "l",
	[120210] = "rn",
	[120211] = "n",
	[120212] = "o",
	[120213] = "p",
	[120214] = "q",
	[120215] = "r",
	[120216] = "s",
	[120217] = "t",
	[120218] = "u",
	[120219] = "v",
	[120220] = "w",
	[120221] = "x",
	[120222] = "y",
	[120223] = "z",
	[120224] = "A",
	[120225] = "B",
	[120226] = "C",
	[120227] = "D",
	[120228] = "E",
	[120229] = "F",
	[120230] = "G",
	[120231] = "H",
	[120232] = "l",
	[120233] = "J",
	[120234] = "K",
	[120235] = "L",
	[120236] = "M",
	[120237] = "N",
	[120238] = "O",
	[120239] = "P",
	[120240] = "Q",
	[120241] = "R",
	[120242] = "S",
	[120243] = "T",
	[120244] = "U",
	[120245] = "V",
	[120246] = "W",
	[120247] = "X",
	[120248] = "Y",
	[120249] = "Z",
	[120250] = "a",
	[120251] = "b",
	[120252] = "c",
	[120253] = "d",
	[120254] = "e",
	[120255] = "f",
	[120256] = "g",
	[120257] = "h",
	[120258] = "i",
	[120259] = "j",
	[120260] = "k",
	[120261] = "l",
	[120262] = "rn",
	[120263] = "n",
	[120264] = "o",
	[120265] = "p",
	[120266] = "q",
	[120267] = "r",
	[120268] = "s",
	[120269] = "t",
	[120270] = "u",
	[120271] = "v",
	[120272] = "w",
	[120273] = "x",
	[120274] = "y",
	[120275] = "z",
	[120276] = "A",
	[120277] = "B",
	[120278] = "C",
	[120279] = "D",
	[120280] = "E",
	[120281] = "F",
	[120282] = "G",
	[120283] = "H",
	[120284] = "l",
	[120285] = "J",
	[120286] = "K",
	[120287] = "L",
	[120288] = "M",
	[120289] = "N",
	[120290] = "O",
	[120291] = "P",
	[120292] = "Q",
	[120293] = "R",
	[120294] = "S",
	[120295] = "T",
	[120296] = "U",
	[120297] = "V",
	[120298] = "W",
	[120299] = "X",
	[120300] = "Y",
	[120301] = "Z",
	[120302] = "a",
	[120303] = "b",
	[120304] = "c",
	[120305] = "d",
	[120306] = "e",
	[120307] = "f",
	[120308] = "g",
	[120309] = "h",
	[120310] = "i",
	[120311] = "j",
	[120312] = "k",
	[120313] = "l",
	[120314] = "rn",
	[120315] = "n",
	[120316] = "o",
	[120317] = "p",
	[120318] = "q",
	[120319] = "r",
	[120320] = "s",
	[120321] = "t",
	[120322] = "u",
	[120323] = "v",
	[120324] = "w",
	[120325] = "x",
	[120326] = "y",
	[120327] = "z",
	[120328] = "A",
	[120329] = "B",
	[120330] = "C",
	[120331] = "D",
	[120332] = "E",
	[120333] = "F",
	[120334] = "G",
	[120335] = "H",
	[120336] = "l",
	[120337] = "J",
	[120338] = "K",
	[120339] = "L",
	[120340] = "M",
	[120341] = "N",
	[120342] = "O",
	[120343] = "P",
	[120344] = "Q",
	[120345] = "R",
	[120346] = "S",
	[120347] = "T",
	[120348] = "U",
	[120349] = "V",
	[120350] = "W",
	[120351] = "X",
	[120352] = "Y",
	[120353] = "Z",
	[120354] = "a",
	[120355] = "b",
	[120356] = "c",
	[120357] = "d",
	[120358] = "e",
	[120359] = "f",
	[120360] = "g",
	[120361] = "h",
	[120362] = "i",
	[120363] = "j",
	[120364] = "k",
	[120365] = "l",
	[120366] = "rn",
	[120367] = "n",
	[120368] = "o",
	[120369] = "p",
	[120370] = "q",
	[120371] = "r",
	[120372] = "s",
	[120373] = "t",
	[120374] = "u",
	[120375] = "v",
	[120376] = "w",
	[120377] = "x",
	[120378] = "y",
	[120379] = "z",
	[120380] = "A",
	[120381] = "B",
	[120382] = "C",
	[120383] = "D",
	[120384] = "E",
	[120385] = "F",
	[120386] = "G",
	[120387] = "H",
	[120388] = "l",
	[120389] = "J",
	[120390] = "K",
	[120391] = "L",
	[120392] = "M",
	[120393] = "N",
	[120394] = "O",
	[120395] = "P",
	[120396] = "Q",
	[120397] = "R",
	[120398] = "S",
	[120399] = "T",
	[120400] = "U",
	[120401] = "V",
	[120402] = "W",
	[120403] = "X",
	[120404] = "Y",
	[120405] = "Z",
	[120406] = "a",
	[120407] = "b",
	[120408] = "c",
	[120409] = "d",
	[120410] = "e",
	[120411] = "f",
	[120412] = "g",
	[120413] = "h",
	[120414] = "i",
	[120415] = "j",
	[120416] = "k",
	[120417] = "l",
	[120418] = "rn",
	[120419] = "n",
	[120420] = "o",
	[120421] = "p",
	[120422] = "q",
	[120423] = "r",
	[120424] = "s",
	[120425] = "t",
	[120426] = "u",
	[120427] = "v",
	[120428] = "w",
	[120429] = "x",
	[120430] = "y",
	[120431] = "z",
	[120432] = "A",
	[120433] = "B",
	[120434] = "C",
	[120435] = "D",
	[120436] = "E",
	[120437] = "F",
	[120438] = "G",
	[120439] = "H",
	[120440] = "l",
	[120441] = "J",
	[120442] = "K",
	[120443] = "L",
	[120444] = "M",
	[120445] = "N",
	[120446] = "O",
	[120447] = "P",
	[120448] = "Q",
	[120449] = "R",
	[120450] = "S",
	[120451] = "T",
	[120452] = "U",
	[120453] = "V",
	[120454] = "W",
	[120455] = "X",
	[120456] = "Y",
	[120457] = "Z",
	[120458] = "a",
	[120459] = "b",
	[120460] = "c",
	[120461] = "d",
	[120462] = "e",
	[120463] = "f",
	[120464] = "g",
	[120465] = "h",
	[120466] = "i",
	[120467] = "j",
	[120468] = "k",
	[120469] = "l",
	[120470] = "rn",
	[120471] = "n",
	[120472] = "o",
	[120473] = "p",
	[120474] = "q",
	[120475] = "r",
	[120476] = "s",
	[120477] = "t",
	[120478] = "u",
	[120479] = "v",
	[120480] = "w",
	[120481] = "x",
	[120482] = "y",
	[120483] = "z",
	[120484] = "i",
	[120488] = "A",
	[120489] = "B",
	[120492] = "E",
	[120493] = "Z",
	[120494] = "H",
	[120496] = "l",
	[120497] = "K",
	[120499] = "M",
	[120500] = "N",
	[120502] = "O",
	[120504] = "P",
	[120507] = "T",
	[120508] = "Y",
	[120510] = "X",
	[120514] = "a",
	[120516] = "y",
	[120522] = "i",
	[120526] = "v",
	[120528] = "o",
	[120530] = "p",
	[120532] = "o",
	[120534] = "u",
	[120544] = "p",
	[120546] = "A",
	[120547] = "B",
	[120550] = "E",
	[120551] = "Z",
	[120552] = "H",
	[120554] = "l",
	[120555] = "K",
	[120557] = "M",
	[120558] = "N",
	[120560] = "O",
	[120562] = "P",
	[120565] = "T",
	[120566] = "Y",
	[120568] = "X",
	[120572] = "a",
	[120574] = "y",
	[120580] = "i",
	[120584] = "v",
	[120586] = "o",
	[120588] = "p",
	[120590] = "o",
	[120592] = "u",
	[120602] = "p",
	[120604] = "A",
	[120605] = "B",
	[120608] = "E",
	[120609] = "Z",
	[120610] = "H",
	[120612] = "l",
	[120613] = "K",
	[120615] = "M",
	[120616] = "N",
	[120618] = "O",
	[120620] = "P",
	[120623] = "T",
	[120624] = "Y",
	[120626] = "X",
	[120630] = "a",
	[120632] = "y",
	[120638] = "i",
	[120642] = "v",
	[120644] = "o",
	[120646] = "p",
	[120648] = "o",
	[120650] = "u",
	[120660] = "p",
	[120662] = "A",
	[120663] = "B",
	[120666] = "E",
	[120667] = "Z",
	[120668] = "H",
	[120670] = "l",
	[120671] = "K",
	[120673] = "M",
	[120674] = "N",
	[120676] = "O",
	[120678] = "P",
	[120681] = "T",
	[120682] = "Y",
	[120684] = "X",
	[120688] = "a",
	[120690] = "y",
	[120696] = "i",
	[120700] = "v",
	[120702] = "o",
	[120704] = "p",
	[120706] = "o",
	[120708] = "u",
	[120718] = "p",
	[120720] = "A",
	[120721] = "B",
	[120724] = "E",
	[120725] = "Z",
	[120726] = "H",
	[120728] = "l",
	[120729] = "K",
	[120731] = "M",
	[120732] = "N",
	[120734] = "O",
	[120736] = "P",
	[120739] = "T",
	[120740] = "Y",
	[120742] = "X",
	[120746] = "a",
	[120748] = "y",
	[120754] = "i",
	[120758] = "v",
	[120760] = "o",
	[120762] = "p",
	[120764] = "o",
	[120766] = "u",
	[120776] = "p",
	[120778] = "F",
	[120782] = "O",
	[120783] = "l",
	[120784] = "2",
	[120785] = "3",
	[120786] = "4",
	[120787] = "5",
	[120788] = "6",
	[120789] = "7",
	[120790] = "8",
	[120791] = "9",
	[120792] = "O",
	[120793] = "l",
	[120794] = "2",
	[120795] = "3",
	[120796] = "4",
	[120797] = "5",
	[120798] = "6",
	[120799] = "7",
	[120800] = "8",
	[120801] = "9",
	[120802] = "O",
	[120803] = "l",
	[120804] = "2",
	[120805] = "3",
	[120806] = "4",
	[120807] = "5",
	[120808] = "6",
	[120809] = "7",
	[120810] = "8",
	[120811] = "9",
	[120812] = "O",
	[120813] = "l",
	[120814] = "2",
	[120815] = "3",
	[120816] = "4",
	[120817] = "5",
	[120818] = "6",
	[120819] = "7",
	[120820] = "8",
	[120821] = "9",
	[120822] = "O",
	[120823] = "l",
	[120824] = "2",
	[120825] = "3",
	[120826] = "4",
	[120827] = "5",
	[120828] = "6",
	[120829] = "7",
	[120830] = "8",
	[120831] = "9",
	[125127] = "l",
	[125131] = "8",
	[126464] = "l",
	[126500] = "o",
	[126564] = "o",
	[126592] = "l",
	[126596] = "o",
	[127232] = "O.",
	[127233] = "O,",
	[127234] = "l,",
	[127235] = "2,",
	[127236] = "3,",
	[127237] = "4,",
	[127238] = "5,",
	[127239] = "6,",
	[127240] = "7,",
	[127241] = "8,",
	[127242] = "9,",
	[127248] = "(A)", 
	[127249] = "(B)", 
	[127250] = "(C)", 
	[127251] = "(D)", 
	[127252] = "(E)", 
	[127253] = "(F)", 
	[127254] = "(G)", 
	[127255] = "(H)", 
	[127256] = "(l)", 
	[127257] = "(J)", 
	[127258] = "(K)", 
	[127259] = "(L)", 
	[127260] = "(M)", 
	[127261] = "(N)", 
	[127262] = "(O)", 
	[127263] = "(P)", 
	[127264] = "(Q)", 
	[127265] = "(R)", 
	[127266] = "(S)", 
	[127267] = "(T)", 
	[127268] = "(U)", 
	[127269] = "(V)", 
	[127270] = "(W)", 
	[127271] = "(X)", 
	[127272] = "(Y)", 
	[127273] = "(Z)", 
	[127274] = "(S)", 
	[128768] = "QE",
	[128775] = "AR",
	[128844] = "C",
	[128860] = "sss", 
	[128872] = "T",
	[128875] = "MB",
	[128876] = "VB"
}


const EmptyArray = table.freeze({})



-- // String types

const BraceType = {
	InterpolatedString = 0,
	Normal = 1,
}

const QuoteStyle = {
	QuotedSimple = 0,
	QuotedSingle = 1,
	QuotedRaw = 2,
	Unquoted = 3,
}

const CstQuotes = {
	QuotedSingle = 0, -- ''
	QuotedDouble = 1, -- ""
	QuotedRaw = 2, -- [[]]
	QuotedInterp = 3, -- ``
}

-- // Lookup for keywords
const ReversedKeywords = {
	[291] = "and",
	[292] = "break",
	[293] = "do",
	[294] = "else",
	[295] = "elseif",
	[296] = "end",
	[297] = "false",
	[298] = "for",
	[299] = "function",
	[300] = "if",
	[301] = "in",
	[302] = "local",
	[303] = "nil",
	[304] = "not",
	[305] = "or",
	[306] = "repeat",
	[307] = "return",
	[308] = "then",
	[309] = "true",
	[310] = "until",
	[311] = "while",
}

const IdentifierCharacters = buffer.create(256)
buffer.writeu8(IdentifierCharacters, 95, 1)
for Byte = 65, 90 do
	buffer.writeu8(IdentifierCharacters, Byte, 1)
end
for Byte = 97, 122 do
	buffer.writeu8(IdentifierCharacters, Byte, 1)
end
for Byte = 48, 57 do
	buffer.writeu8(IdentifierCharacters, Byte, 2)
end

const SimpleTokens = buffer.create(512)
buffer.writeu16(SimpleTokens, 40 * 2, 40) -- (
buffer.writeu16(SimpleTokens, 41 * 2, 41) -- )
buffer.writeu16(SimpleTokens, 93 * 2, 93) -- ]
buffer.writeu16(SimpleTokens, 59 * 2, 59) -- ;
buffer.writeu16(SimpleTokens, 44 * 2, 44) -- ,
buffer.writeu16(SimpleTokens, 35 * 2, 35) -- #
buffer.writeu16(SimpleTokens, 63 * 2, 63) -- ?
buffer.writeu16(SimpleTokens, 38 * 2, 38) -- &
buffer.writeu16(SimpleTokens, 124 * 2, 124) -- |
buffer.writeu16(SimpleTokens, 61 * 2, 257) -- ==
buffer.writeu16(SimpleTokens, 60 * 2, 258) -- <=
buffer.writeu16(SimpleTokens, 62 * 2, 259) -- >=
buffer.writeu16(SimpleTokens, 126 * 2, 260) -- ~=
buffer.writeu16(SimpleTokens, 43 * 2, 270) -- +=
buffer.writeu16(SimpleTokens, 42 * 2, 272) -- *=
buffer.writeu16(SimpleTokens, 37 * 2, 275) -- %=
buffer.writeu16(SimpleTokens, 94 * 2, 276) -- ^=

-- // Lookup for operators

const BinaryOp = {
	Add = 0,
	Sub = 1,
	Mul = 2,
	Div = 3,
	FloorDiv = 4,
	Mod = 5,
	Pow = 6,
	Concat = 7,
	CompareNe = 8,
	CompareEq = 9,
	CompareLt = 10,
	CompareLe = 11,
	CompareGt = 12,
	CompareGe = 13,
	And = 14,
	Or = 15,
}

const BinaryPriority = {
	[BinaryOp.Add] = { 6, 6 },
	[BinaryOp.Sub] = { 6, 6 },
	[BinaryOp.Mul] = { 7, 7 },
	[BinaryOp.Div] = { 7, 7 },
	[BinaryOp.FloorDiv] = { 7, 7 },
	[BinaryOp.Mod] = { 7, 7 },
	[BinaryOp.Pow] = { 10, 9 },
	[BinaryOp.Concat] = { 5, 4 },
	[BinaryOp.CompareNe] = { 3, 3 },
	[BinaryOp.CompareEq] = { 3, 3 },
	[BinaryOp.CompareLt] = { 3, 3 },
	[BinaryOp.CompareLe] = { 3, 3 },
	[BinaryOp.CompareGt] = { 3, 3 },
	[BinaryOp.CompareGe] = { 3, 3 },
	[BinaryOp.And] = { 2, 2 },
	[BinaryOp.Or] = { 1, 1 },
}

const CompoundLookup = {
	[274] = BinaryOp.FloorDiv, -- FloorDivAssign
	[277] = BinaryOp.Concat, -- ConcatAssign
	[275] = BinaryOp.Mod, -- ModAssign
	[276] = BinaryOp.Pow, -- PowAssign
	[270] = BinaryOp.Add, -- AddAssign
	[271] = BinaryOp.Sub, -- SubAssign
	[272] = BinaryOp.Mul, -- MulAssign
	[273] = BinaryOp.Div, -- DivAssign
}

const BinaryOpLookup = {
	[43] = BinaryOp.Add,
	[45] = BinaryOp.Sub,
	[42] = BinaryOp.Mul,
	[47] = BinaryOp.Div,

	[265] = BinaryOp.FloorDiv, -- FloorDiv

	[37] = BinaryOp.Mod,
	[94] = BinaryOp.Pow,

	[261] = BinaryOp.Concat, -- Dot2
	[260] = BinaryOp.CompareNe, -- NotEqual
	[257] = BinaryOp.CompareEq, -- Equal

	[60] = BinaryOp.CompareLt,

	[258] = BinaryOp.CompareLe, -- LessEqual

	[62] = BinaryOp.CompareGt,

	[259] = BinaryOp.CompareGe, -- GreaterEqual
	[291] = BinaryOp.And, -- ReservedAnd
	[305] = BinaryOp.Or, -- ReservedOr
}

const UnaryOpLookup = {
	[304] = 0, -- ReservedNot
	[45] = 1, -- Minus
	[35] = 2, -- Len
}

const BlockFollow = {
	[295] = true, -- ReservedElseif
	[310] = true, -- ReservedUntil
	[294] = true, -- ReservedElse
	[296] = true, -- ReservedEnd
	[0] = true, -- Eof
}

const ConstantLiteral = {
	ExprConstantNil = true,
	ExprConstantBool = true,
	ExprConstantNumber = true,
	ExprConstantInteger = true,
	ExprConstantString = true,
}

const ExprLValues = {
	ExprLocal = true,
	ExprGlobal = true,
	ExprIndexExpr = true,
	ExprIndexName = true,
}

const AllowedClassMetamethods = {
	__init = true,
	__call = true,
	__concat = true,
	__unm = true,
	__add = true,
	__sub = true,
	__mul = true,
	__div = true,
	__mod = true,
	__pow = true,
	__tostring = true,
	__eq = true,
	__lt = true,
	__le = true,
	__iter = true,
	__len = true,
	__idiv = true,
}

const DisallowedClassMetamethods = {
	__index = true,
	__newindex = true,
	__mode = true,
	__metatable = true,
	__type = true,
}

-- // Lookups for Lexer

const HexDigits: { [number]: boolean } = {}
const HexVal: { [number]: number } = {}
const Digits: { [number]: boolean } = {}
const Alpha: { [number]: boolean } = {}

const Spaces = {
	[09] = true, -- \t
	[10] = true, -- \n
	[11] = true, -- \v
	[12] = true, -- \f
	[13] = true, -- \r
	[32] = true, -- space
}

const Escapes = {
	[97] = 7,
	[98] = 8,
	[102] = 12,
	[110] = 10,
	[114] = 13,
	[116] = 9,
	[118] = 11,
}

for i = 48, 57 do -- '0' - '9'
	HexDigits[i] = true
	Digits[i] = true
end

for i = 65, 90 do
	if i <= 70 then
		HexDigits[i] = true
	end -- 'a' - 'f'
	Alpha[i] = true
end

for i = 97, 122 do
	if i <= 102 then
		HexDigits[i] = true
	end -- 'A' - 'F'
	Alpha[i] = true
end

for i = 48, 57 do HexVal[i] = i - 48 end -- '0'-'9'
for i = 65, 70 do HexVal[i] = i - 55 end -- 'A'-'F'
for i = 97, 102 do HexVal[i] = i - 87 end -- 'a'-'f'

-- // Lexer helper

const function fixupQuotedString(data: string): (boolean, string?)
	if #data == 0 or not string.find(data, "\\") then
		return true, data
	end

	const size = #data
	const src = buffer.fromstring(data)
	const buf = buffer.create(size)
	local write = 0
	local i = 0

	while i < size do
		const ch = buffer.readu8(src, i)

		if ch ~= 92 then -- not '\'
			buffer.writeu8(buf, write, ch)
			write += 1
			i += 1
			continue
		end

		if i + 1 == size then
			return false, nil -- Trailing backslash
		end

		const escape = buffer.readu8(src, i + 1)
		i += 2 -- skip \ and the escape char

		if escape == 10 then -- \n
			buffer.writeu8(buf, write, 10)
			write += 1
		elseif escape == 13 then -- \r
			buffer.writeu8(buf, write, 10)
			write += 1
			if i < size and buffer.readu8(src, i) == 10 then
				i += 1
			end
		elseif escape == 0 then
			return false, nil
		elseif escape == 120 then -- 'x'
			if i + 2 > size then
				return false, nil
			end

			local code = 0
			for j = 0, 1 do
				const c = buffer.readu8(src, i + j)
				if not HexDigits[c] then
					return false, nil
				end

				const hexVal = if Digits[c] then c - 48 else bit32.bor(c, 32) - 97 + 10
				code = 16 * code + hexVal
			end

			buffer.writeu8(buf, write, code)
			write += 1
			i += 2
		elseif escape == 122 then -- 'z'
			while i < size and Spaces[buffer.readu8(src, i)] do
				i += 1
			end
		elseif escape == 117 then -- 'u'
			if i + 3 > size then
				return false, nil
			end
			if buffer.readu8(src, i) ~= 123 then
				return false, nil
			end -- '{'
			i += 1

			if buffer.readu8(src, i) == 125 then
				return false, nil
			end

			local code = 0
			local ended = false

			for j = 0, 15 do
				if i == size then
					return false, nil
				end
				const c = buffer.readu8(src, i)

				if c == 125 then
					ended = true
					break
				end

				if not HexDigits[c] then
					return false, nil
				end

				const hexVal = if Digits[c] then c - 48 else bit32.bor(c, 32) - 97 + 10
				code = 16 * code + hexVal
				i += 1
			end

			if not ended then
				if i == size or buffer.readu8(src, i) ~= 125 then
					return false, nil
				end
			end
			i += 1 -- skip '}'

			if code < 0x80 then
				buffer.writeu8(buf, write, code)
				write += 1
			elseif code < 0x800 then
				buffer.writeu8(buf, write, bit32.bor(0xC0, bit32.rshift(code, 6)))
				buffer.writeu8(buf, write + 1, bit32.bor(0x80, bit32.band(code, 0x3F)))
				write += 2
			elseif code < 0x10000 then
				buffer.writeu8(buf, write, bit32.bor(0xE0, bit32.rshift(code, 12)))
				buffer.writeu8(buf, write + 1, bit32.bor(0x80, bit32.band(bit32.rshift(code, 6), 0x3F)))
				buffer.writeu8(buf, write + 2, bit32.bor(0x80, bit32.band(code, 0x3F)))
				write += 3
			elseif code < 0x110000 then
				buffer.writeu8(buf, write, bit32.bor(0xF0, bit32.rshift(code, 18)))
				buffer.writeu8(buf, write + 1, bit32.bor(0x80, bit32.band(bit32.rshift(code, 12), 0x3F)))
				buffer.writeu8(buf, write + 2, bit32.bor(0x80, bit32.band(bit32.rshift(code, 6), 0x3F)))
				buffer.writeu8(buf, write + 3, bit32.bor(0x80, bit32.band(code, 0x3F)))
				write += 4
			else
				return false, nil
			end
		else
			if Digits[escape] then
				local code = escape - 48

				for j = 0, 1 do
					if i == size then
						break
					end
					const c = buffer.readu8(src, i)
					if not Digits[c] then
						break
					end
					code = 10 * code + (c - 48)
					i += 1
				end

				if code > 255 then
					return false, nil
				end

				buffer.writeu8(buf, write, code)
				write += 1
			else
				buffer.writeu8(buf, write, Escapes[escape] or escape)
				write += 1
			end
		end
	end

	return true, buffer.readstring(buf, 0, write)
end

const function fixupMultilineString(data: string): string
	if #data == 0 then
		return data
	end

	data = string.gsub(data, "^\r?\n", "")
	data = string.gsub(data, "\r\n", "\n")

	return data
end

const function ToString(t: number, data: string?, codepoint: number?): string
	if t == 0 then
		return "<eof>"
	elseif t == 257 then
		return "'=='"
	elseif t == 258 then
		return "'<='"
	elseif t == 259 then
		return "'>='"
	elseif t == 260 then
		return "'~='"
	elseif t == 261 then
		return "'..'"
	elseif t == 262 then
		return "'...'"
	elseif t == 263 then
		return "'->'"
	elseif t == 264 then
		return "'::'"
	elseif t == 265 then
		return "'//'"
	elseif t == 270 then
		return "'+='"
	elseif t == 271 then
		return "'-='"
	elseif t == 272 then
		return "'*='"
	elseif t == 273 then
		return "'/='"
	elseif t == 274 then
		return "'//='"
	elseif t == 275 then
		return "'%='"
	elseif t == 276 then
		return "'^='"
	elseif t == 277 then
		return "'..='"
	elseif t == 278 or t == 279 then
		if data then
			return `"{data}"`
		else
			return "string"
		end
	elseif t == 266 then
		if data then
			return `\`{data}\{`
		else
			return "the beginning of an interpolated string"
		end
	elseif t == 267 then
		if data then
			return `\}{data}\{`
		else
			return "the middle of an interpolated string"
		end
	elseif t == 268 then
		if data then
			return `\}{data}\``
		else
			return "the end of an interpolated string"
		end
	elseif t == 269 then
		if data then
			return `\`{data}\``
		else
			return "interpolated string"
		end
	elseif t == 280 then
		if data then
			return `'{data}'`
		else
			return "number"
		end
	elseif t == 281 then
		if data then
			return `'{data}'`
		else
			return "identifier"
		end
	elseif t == 282 then
		return "comment"
	elseif t == 284 then
		if data then
			return `'{data}'`
		else
			return "attribute"
		end
	elseif t == 285 then
		return "'@['"
	elseif t == 286 then
		return "malformed string"
	elseif t == 287 then
		return "unfinished comment"
	elseif t == 289 then
		return "'{{', which is invalid (did you mean '\\{'?)"
	elseif t == 288 then
		if codepoint then
			const confusable = Confusables[codepoint]
			if confusable then
				return `Unicode character {string.format("U+%x", codepoint)} (did you mean '{confusable}'?)`
			end
			return string.format("Unicode character U+%x", codepoint)
		else
			return "invalid UTF-8 sequence"
		end
	else
		if t < 256 then
			return string.format("'%c'", t)
		elseif ReversedKeywords[t] then
			return `'{ReversedKeywords[t]}'`
		else
			return "<unknown>"
		end
	end
end

-- // Parser Helpers

const function isLiteralTable(expr: AstExpr): boolean
	if expr.kind ~= "ExprTable" then
		return false
	end

	for _, item in expr.items do
		if item.kind == "General" then
			return false
		elseif item.kind == "Record" or item.kind == "List" then
			if not ConstantLiteral[item.value.kind] and not isLiteralTable(item.value) then
				return false
			end
		end
	end

	return true
end

-- // Attributes

const function deprecatedArgsValidator(attrLoc: Location, args: { AstExpr }): { ParseError }
	const errors: { ParseError } = {}
	if #args == 0 then
		return errors
	end
	if #args > 1 then
		table.insert(errors, {
			location = attrLoc,
			message = "@deprecated can be parametrized only by 1 argument",
		})
		return errors
	end

	const arg = args[1]
	if arg.kind ~= "ExprTable" then
		table.insert(errors, {
			location = arg.location,
			message = "Unknown argument type for @deprecated",
		})
		return errors
	end

	for _, item in arg.items do
		if item.key and item.kind == "Record" and item.key.kind == "ExprConstantString" then
			const keyString = item.key.value
			if keyString ~= "use" and keyString ~= "reason" then
				table.insert(errors, {
					location = item.key.location,
					message = `Unknown argument '{keyString}' for @deprecated. Only string constants for 'use' and 'reason' are allowed`,
				})
			elseif item.value.kind ~= "ExprConstantString" then
				table.insert(errors, {
					location = item.value.location,
					message = `Only constant string allowed as value for '{keyString}'`,
				})
			end
		else
			table.insert(errors, {
				location = item.value.location,
				message = "Only constants keys 'use' and 'reason' are allowed for @deprecated attribute",
			})
		end
	end
	return errors
end

const kAttributeEntries = {
	checked = {type = "Checked"},
	native = {type = "Native"},

	deprecated = {
		type = "Deprecated",
		argsValidator = deprecatedArgsValidator,
	},
}

const kDebugAttributeEntries = {
	debugnoinline = {type = "DebugNoinline"},
}

-- // Main

local function New()
local hotcommentHeader = true
local onLexeme: ((number, number, number) -> ())?
local tokenOffset = 0
local lexerCheckpoint: (() -> ())?
local nextCheckpoint = math.huge
local options = {} :: Options

-- // Settings init

local captureComments = options.captureComments
local storeCstData = options.storeCstData

-- // Lexer State & Buffer

local buff_data = buffer.create(0)
local size = 0

-- Current State
local offset = 0
local line = 0
local lineOffset = 0

local braceStack: { number } = {}
local braceStackSize = 0

-- // Current Token State

local token_type = 0 -- Eof

-- Locations
local token_start_line = 0
local token_start_col = 0
local token_end_line = 0
local token_end_col = 0

-- Previous Token Location (for errors/end mismatch)
local prev_start_line = 0
local prev_start_col = 0
local prev_end_line = 0
local prev_end_col = 0

-- Payload
local token_string: string? = nil
local token_aux: number? = nil
local token_codepoint: number? = nil

-- // Parser init

local recursionCounter = 0

local commentLocations: { Comment } = {}
local hotcomments = {} :: { HotComment }
local parseErrors: { ParseError } = {}
local declaredExportBindings: { [string]: Location } = {}
local hasModuleReturn = false
local classesWithinModule: { [string]: AstStatClass } = {}

type TableIndexerResult = {
	node: AstTableIndexer,
	indexerOpenPosition: Position,
	indexerClosePosition: Position,
	colonPosition: Position?,
}


-- // Suspect State

local next_type = 0 -- Eof
local next_start_line = 0
local next_end_line = 0

local next_start_col = 0
local next_end_col = 0

local next_codepoint: number? = nil
local next_string: string? = nil
local next_aux: number? = nil

local suspect_type = 0 -- Eof sentinel

local suspect_line = 0

local matchRecovery = table.create(312, 0)
matchRecovery[0] = 1 -- Eof

-- // Stacks

local functionStack: { FunctionState } = {{ vararg = true, loopDepth = 0 }}

local localStack: { AstLocal? } = {}
local localMap: { [string]: AstLocal? } = {}

-- // Lexer // --

const function yieldLexer(position: number)
	nextCheckpoint = position + 16384
	if lexerCheckpoint then lexerCheckpoint() end
end

const function lex(skip_comments: boolean)
	local ptr = offset
	local cur_line = line
	local cur_line_offset = lineOffset

	const buff = buff_data
	const sourceSize = size
	const IdentifierCharactersLookup = IdentifierCharacters
	const SimpleTokensLookup = SimpleTokens

	while true do
		if ptr >= nextCheckpoint then yieldLexer(ptr) end
		if ptr >= sourceSize then
			-- EOF Logic
			offset = ptr
			line = cur_line
			lineOffset = cur_line_offset

			next_type = 0 -- Eof
			next_end_line = cur_line
			next_end_col = ptr - cur_line_offset

			next_start_line = cur_line
			next_start_col = ptr - cur_line_offset
			return
		end

		const c = buffer.readu8(buff, ptr)

		if c == 32 or c == 9 then -- space or tab
			ptr += 1
		elseif c == 10 then -- \n
			cur_line += 1
			ptr += 1
			cur_line_offset = ptr
		elseif c == 13 then -- \r
			if ptr + 1 < sourceSize and buffer.readu8(buff, ptr + 1) == 10 then
				ptr += 2
				cur_line += 1
				cur_line_offset = ptr
			else
				ptr += 1
			end
		elseif c == 11 or c == 12 then -- \v, \f
			ptr += 1
		else
			break -- not whitespace
		end
	end

	next_start_line = cur_line
	next_start_col = ptr - cur_line_offset
	next_string = nil
	next_aux = nil
	next_codepoint = nil

	const ch = buffer.readu8(buff, ptr)
	const characterType = buffer.readu8(IdentifierCharactersLookup, ch)
	const start_ptr = ptr
	tokenOffset = ptr
	ptr += 1 -- Consume current char

	-- Identifiers / Keywords
	if characterType == 1 then
		while ptr < sourceSize do
			if ptr >= nextCheckpoint then yieldLexer(ptr) end
			const c = buffer.readu8(buff, ptr)
			if buffer.readu8(IdentifierCharactersLookup, c) ~= 0 then
				ptr += 1
			else
				break
			end
		end

		const identifierLength = ptr - start_ptr
		local identifierType = 281

		if identifierLength == 2 then
			const bytes = buffer.readu16(buff, start_ptr)
			if bytes == 0x6f64 then -- do
				identifierType = 293
			elseif bytes == 0x6669 then -- if
				identifierType = 300
			elseif bytes == 0x6e69 then -- in
				identifierType = 301
			elseif bytes == 0x726f then -- or
				identifierType = 305
			end
		elseif identifierLength == 3 then
			const firstBytes = buffer.readu16(buff, start_ptr)
			const thirdByte = buffer.readu8(buff, start_ptr + 2)
			if firstBytes == 0x6e61 and thirdByte == 100 then -- and
				identifierType = 291
			elseif firstBytes == 0x6e65 and thirdByte == 100 then -- end
				identifierType = 296
			elseif firstBytes == 0x6f66 and thirdByte == 114 then -- for
				identifierType = 298
			elseif firstBytes == 0x696e and thirdByte == 108 then -- nil
				identifierType = 303
			elseif firstBytes == 0x6f6e and thirdByte == 116 then -- not
				identifierType = 304
			end
		elseif identifierLength == 4 then
			const bytes = buffer.readu32(buff, start_ptr)
			if bytes == 0x65736c65 then -- else
				identifierType = 294
			elseif bytes == 0x6e656874 then -- then
				identifierType = 308
			elseif bytes == 0x65757274 then -- true
				identifierType = 309
			end
		elseif identifierLength == 5 then
			const firstBytes = buffer.readu32(buff, start_ptr)
			const fifthByte = buffer.readu8(buff, start_ptr + 4)
			if firstBytes == 0x61657262 and fifthByte == 107 then -- break
				identifierType = 292
			elseif firstBytes == 0x736c6166 and fifthByte == 101 then -- false
				identifierType = 297
			elseif firstBytes == 0x61636f6c and fifthByte == 108 then -- local
				identifierType = 302
			elseif firstBytes == 0x69746e75 and fifthByte == 108 then -- until
				identifierType = 310
			elseif firstBytes == 0x6c696877 and fifthByte == 101 then -- while
				identifierType = 311
			end
		elseif identifierLength == 6 then
			const firstBytes = buffer.readu32(buff, start_ptr)
			const lastBytes = buffer.readu16(buff, start_ptr + 4)
			if firstBytes == 0x65736c65 and lastBytes == 0x6669 then -- elseif
				identifierType = 295
			elseif firstBytes == 0x65706572 and lastBytes == 0x7461 then -- repeat
				identifierType = 306
			elseif firstBytes == 0x75746572 and lastBytes == 0x6e72 then -- return
				identifierType = 307
			end
		elseif
			identifierLength == 8
			and buffer.readu32(buff, start_ptr) == 0x636e7566
			and buffer.readu32(buff, start_ptr + 4) == 0x6e6f6974
		then -- function
			identifierType = 299
		end

		next_type = identifierType
		if identifierType == 281 then
			next_string = buffer.readstring(buff, start_ptr, ptr - start_ptr)
		end
		-- Numbers (0-9)
	elseif characterType == 2 then
		while ptr < sourceSize do
			if ptr >= nextCheckpoint then yieldLexer(ptr) end
			const numberChar = buffer.readu8(buff, ptr)
			const numberCharacterType = buffer.readu8(IdentifierCharactersLookup, numberChar)

			if numberCharacterType == 2 or numberChar == 46 or numberChar == 95 then
				ptr += 1
			elseif numberChar == 101 or numberChar == 69 then -- e / E
				ptr += 1

				if ptr < sourceSize then
					const exp_ch = buffer.readu8(buff, ptr)
					if exp_ch == 43 or exp_ch == 45 then -- + / -
						ptr += 1
					end
				end
			else
				break
			end
		end

		while ptr < sourceSize do
			if ptr >= nextCheckpoint then yieldLexer(ptr) end
			const suffixChar = buffer.readu8(buff, ptr)

			if buffer.readu8(IdentifierCharactersLookup, suffixChar) ~= 0 then
				ptr += 1
			else
				break
			end
		end
		
		next_type = 280 -- Number
		next_string = buffer.readstring(buff, start_ptr, ptr - start_ptr)

		-- Strings (" or ')
	elseif ch == 34 or ch == 39 then -- " or '
		const delim = ch
		const content_start = ptr

		while ptr < sourceSize do
			if ptr >= nextCheckpoint then yieldLexer(ptr) end
			const c = buffer.readu8(buff, ptr)
			if c == delim then
				break
			elseif c == 92 then -- \
				ptr += 1
				if ptr < sourceSize then
					const esc = buffer.readu8(buff, ptr)
					if esc == 10 then -- \n
						cur_line += 1
						cur_line_offset = ptr + 1
					elseif esc == 13 then -- \r
						if ptr + 1 < sourceSize and buffer.readu8(buff, ptr + 1) == 10 then
							cur_line += 1
							ptr += 1
							cur_line_offset = ptr + 1
						end
					elseif esc == 122 then -- z
						ptr += 1
						while ptr < sourceSize do
							if ptr >= nextCheckpoint then yieldLexer(ptr) end
							const wc = buffer.readu8(buff, ptr)
							if wc == 32 or wc == 9 or wc == 10 or wc == 13 or wc == 11 or wc == 12 then
								if wc == 10 then
									cur_line += 1
									cur_line_offset = ptr + 1
								elseif wc == 13 then
									if ptr + 1 < sourceSize and buffer.readu8(buff, ptr + 1) == 10 then
										ptr += 1
										cur_line += 1
										cur_line_offset = ptr + 1
									end
								end
								ptr += 1
							else
								ptr -= 1
								break
							end
						end
					end
				end
			elseif c == 10 or c == 13 then -- \n / \r
				next_type = 286 -- BrokenString
				break
			end
			ptr += 1
		end

		if next_type == 286 then -- BrokenString
			-- handled
		elseif ptr >= sourceSize then
			next_type = 286 -- BrokenString
		else
			next_type = 279 -- QuotedString
			next_string = buffer.readstring(buff, content_start, ptr - content_start)
			next_aux = if delim == 39 then 0 else 1
			ptr += 1 -- consume closing delim
		end

		-- Operators & Punctuation
	elseif buffer.readu16(SimpleTokensLookup, ch * 2) ~= 0 then
		const directToken = buffer.readu16(SimpleTokensLookup, ch * 2)
		if directToken > 255 and ptr < sourceSize and buffer.readu8(buff, ptr) == 61 then
			ptr += 1
			next_type = directToken
		else
			next_type = ch
		end
	elseif ch == 45 then -- '-'
		const next_ch = if ptr < sourceSize then buffer.readu8(buff, ptr) else 0
		if next_ch == 62 then -- ->
			ptr += 1
			next_type = 263 -- SkinnyArrow
		elseif next_ch == 61 then -- -=
			ptr += 1
			next_type = 271 -- SubAssign
		elseif next_ch == 45 then -- -- Comment
			ptr += 1
			const comment_start = ptr

			-- Block Comment --[
			local is_block = false
			if ptr < sourceSize and buffer.readu8(buff, ptr) == 91 then
				const sep_start = ptr
				ptr += 1
				local count = 0
				while ptr < sourceSize and buffer.readu8(buff, ptr) == 61 do
					ptr += 1
					count += 1
				end

				if ptr < sourceSize and buffer.readu8(buff, ptr) == 91 then
					-- Found long comment
					is_block = true
					ptr += 1
					local found_end = false

					while ptr < sourceSize do
						if ptr >= nextCheckpoint then yieldLexer(ptr) end
						const c = buffer.readu8(buff, ptr)
						if c == 93 then -- ]
							local c2_idx = ptr + 1
							local close_count = 0
							while c2_idx < sourceSize and buffer.readu8(buff, c2_idx) == 61 do
								c2_idx += 1
								close_count += 1
							end
							if close_count == count and c2_idx < sourceSize and buffer.readu8(buff, c2_idx) == 93 then
								ptr = c2_idx + 1
								found_end = true
								break
							end
						elseif c == 10 then -- \n
							cur_line += 1
							cur_line_offset = ptr + 1
						end
						ptr += 1
					end

					if not found_end then
						next_type = 287 -- BrokenComment
					else
						next_type = 283 -- BlockComment
					end
				else
					-- Not a block comment
					ptr = sep_start -- Backtrack
				end
			end

			if not is_block then
				-- Line Comment
				while ptr < sourceSize do
					if ptr >= nextCheckpoint then yieldLexer(ptr) end
					const c = buffer.readu8(buff, ptr)
					if c == 10 or c == 13 then
						break
					end -- \n or \r
					ptr += 1
				end
				next_type = 282 -- Comment
			end

			if
				not skip_comments
				or (
					next_type == 282
					and comment_start < ptr
					and buffer.readu8(buff, comment_start) == 33
				)
			then
				next_string = buffer.readstring(buff, comment_start, ptr - comment_start)
			end
		else
			next_type = 45 -- '-'
		end
	elseif ch == 46 then -- '.'
		const next_ch = if ptr < sourceSize then buffer.readu8(buff, ptr) else 0
		if next_ch == 46 then -- ..
			ptr += 1
			const third_ch = if ptr < sourceSize then buffer.readu8(buff, ptr) else 0
			if third_ch == 46 then -- ...
				ptr += 1
				next_type = 262 -- Dot3
			elseif third_ch == 61 then -- ..=
				ptr += 1
				next_type = 277 -- ConcatAssign
			else
				next_type = 261 -- Dot2
			end
		else
			if buffer.readu8(IdentifierCharactersLookup, next_ch) == 2 then
				ptr -= 1 -- Backtrack
				const n_start = ptr
				while ptr < sourceSize do
					if ptr >= nextCheckpoint then yieldLexer(ptr) end
					const numberChar = buffer.readu8(buff, ptr)
					const numberCharacterType = buffer.readu8(IdentifierCharactersLookup, numberChar)

					if numberCharacterType == 2 or numberChar == 46 or numberChar == 95 then
						ptr += 1
					elseif numberChar == 101 or numberChar == 69 then -- e / E
						ptr += 1

						if ptr < sourceSize then
							const exp_ch = buffer.readu8(buff, ptr)
							if exp_ch == 43 or exp_ch == 45 then -- + / -
								ptr += 1
							end
						end
					else
						break
					end
				end

				while ptr < sourceSize do
					if ptr >= nextCheckpoint then yieldLexer(ptr) end
					const suffixChar = buffer.readu8(buff, ptr)

					if buffer.readu8(IdentifierCharactersLookup, suffixChar) ~= 0 then
						ptr += 1
					else
						break
					end
				end
				
				next_type = 280 -- Number
				next_string = buffer.readstring(buff, n_start, ptr - n_start)
			else
				next_type = 46 -- '.'
			end
		end
	elseif ch == 47 then -- '/'
		const next_ch = if ptr < sourceSize then buffer.readu8(buff, ptr) else 0
		if next_ch == 61 then
			ptr += 1
			next_type = 273 -- DivAssign
		elseif next_ch == 47 then
			ptr += 1
			if ptr < sourceSize and buffer.readu8(buff, ptr) == 61 then
				ptr += 1
				next_type = 274 -- FloorDivAssign
			else
				next_type = 265 -- FloorDiv
			end
		else
			next_type = 47
		end
	elseif ch == 58 then -- ':'
		if ptr < sourceSize and buffer.readu8(buff, ptr) == 58 then
			ptr += 1
			next_type = 264 -- DoubleColon
		else
			next_type = 58
		end

		-- Single Char / Interp
	elseif
		ch == 123
		or ch == 125
	then
		if ch == 123 then
			if braceStackSize > 0 then
				braceStackSize += 1
				braceStack[braceStackSize] = BraceType.Normal
			end
			next_type = ch
		elseif ch == 125 then
			if braceStackSize == 0 then
				next_type = ch
			else
				const top = braceStack[braceStackSize]
				braceStack[braceStackSize] = nil
				braceStackSize -= 1
				if top ~= BraceType.InterpolatedString then
					next_type = ch
				else
					const sectionStart = ptr
					local sectionDone = false

					while ptr < sourceSize do
						if ptr >= nextCheckpoint then yieldLexer(ptr) end
						const c = buffer.readu8(buff, ptr)

						if c == 96 then -- `
							next_type = 268 -- InterpStringEnd
							next_string = buffer.readstring(buff, sectionStart, ptr - sectionStart)
							ptr += 1
							sectionDone = true
							break
						elseif c == 13 or c == 10 then -- \r / \n
							next_type = 286 -- BrokenString
							sectionDone = true
							break
						elseif c == 92 then -- \
							-- Allow \u{...} without treating '{' as interpolation start.
							if
								ptr + 2 < sourceSize
								and buffer.readu8(buff, ptr + 1) == 117
								and buffer.readu8(buff, ptr + 2) == 123
							then
								ptr += 3
							else
								ptr += 1 -- consume '\'

								if ptr < sourceSize then
									const esc = buffer.readu8(buff, ptr)

									if esc == 13 then -- \r
										if ptr + 1 < sourceSize and buffer.readu8(buff, ptr + 1) == 10 then
											cur_line += 1
											ptr += 1
											cur_line_offset = ptr + 1
										end
									elseif esc == 122 then -- z
										ptr += 1
										while ptr < sourceSize do
											if ptr >= nextCheckpoint then yieldLexer(ptr) end
											const wc = buffer.readu8(buff, ptr)
											if
												wc ~= 32
												and wc ~= 9
												and wc ~= 13
												and wc ~= 10
												and wc ~= 11
												and wc ~= 12
											then
												break
											end

											if wc == 10 then
												cur_line += 1
												cur_line_offset = ptr + 1
											elseif
												wc == 13
												and ptr + 1 < sourceSize
												and buffer.readu8(buff, ptr + 1) == 10
											then
												ptr += 1
												cur_line += 1
												cur_line_offset = ptr + 1
											end

											ptr += 1
										end
									elseif esc == 10 then -- \n
										cur_line += 1
										cur_line_offset = ptr + 1
										ptr += 1
									else
										ptr += 1
									end
								end
							end
						elseif c == 123 then -- {
							braceStackSize += 1
							braceStack[braceStackSize] = BraceType.InterpolatedString

							if ptr + 1 < sourceSize and buffer.readu8(buff, ptr + 1) == 123 then
								next_type = 289 -- BrokenInterpDoubleBrace
								next_string = buffer.readstring(buff, sectionStart, ptr - sectionStart)
								ptr += 2
								sectionDone = true
								break
							end

							next_type = 267 -- InterpStringMid
							next_string = buffer.readstring(buff, sectionStart, ptr - sectionStart)
							ptr += 1
							sectionDone = true
							break
						else
							ptr += 1
						end
					end

					if not sectionDone then
						next_type = 286 -- BrokenString
					end
				end
			end
		else
			next_type = ch
		end
	elseif ch == 96 then -- `
		const sectionStart = ptr
		local sectionDone = false

		while ptr < sourceSize do
			if ptr >= nextCheckpoint then yieldLexer(ptr) end
			const c = buffer.readu8(buff, ptr)

			if c == 96 then -- `
				next_type = 269 -- InterpStringSimple
				next_string = buffer.readstring(buff, sectionStart, ptr - sectionStart)
				ptr += 1
				sectionDone = true
				break
			elseif c == 13 or c == 10 then -- \r / \n
				next_type = 286 -- BrokenString
				sectionDone = true
				break
			elseif c == 92 then -- \
				-- Allow \u{...} without treating '{' as interpolation start.
				if ptr + 2 < sourceSize and buffer.readu8(buff, ptr + 1) == 117 and buffer.readu8(buff, ptr + 2) == 123 then
					ptr += 3
				else
					ptr += 1 -- consume '\'
					if ptr < sourceSize then
						const esc = buffer.readu8(buff, ptr)

						if esc == 13 then -- \r
							if ptr + 1 < sourceSize and buffer.readu8(buff, ptr + 1) == 10 then
								cur_line += 1
								ptr += 1
								cur_line_offset = ptr + 1
							end
						elseif esc == 122 then -- z
							ptr += 1
							while ptr < sourceSize do
								if ptr >= nextCheckpoint then yieldLexer(ptr) end
								const wc = buffer.readu8(buff, ptr)
								if wc ~= 32 and wc ~= 9 and wc ~= 13 and wc ~= 10 and wc ~= 11 and wc ~= 12 then
									break
								end

								if wc == 10 then
									cur_line += 1
									cur_line_offset = ptr + 1
								elseif wc == 13 and ptr + 1 < sourceSize and buffer.readu8(buff, ptr + 1) == 10 then
									ptr += 1
									cur_line += 1
									cur_line_offset = ptr + 1
								end

								ptr += 1
							end
						elseif esc == 10 then -- \n
							cur_line += 1
							cur_line_offset = ptr + 1
							ptr += 1
						else
							ptr += 1
						end
					end
				end
			elseif c == 123 then -- {
				braceStackSize += 1
				braceStack[braceStackSize] = BraceType.InterpolatedString

				if ptr + 1 < sourceSize and buffer.readu8(buff, ptr + 1) == 123 then
					next_type = 289 -- BrokenInterpDoubleBrace
					next_string = buffer.readstring(buff, sectionStart, ptr - sectionStart)
					ptr += 2
					sectionDone = true
					break
				end

				next_type = 266 -- InterpStringBegin
				next_string = buffer.readstring(buff, sectionStart, ptr - sectionStart)
				ptr += 1
				sectionDone = true
				break
			else
				ptr += 1
			end
		end

		if not sectionDone then
			next_type = 286 -- BrokenString
		end
	elseif ch == 91 then -- [
		local count = 0
		while ptr < sourceSize and buffer.readu8(buff, ptr) == 61 do
			ptr += 1
			count += 1
		end

		if ptr < sourceSize and buffer.readu8(buff, ptr) == 91 then
			ptr += 1
			-- Long String
			const ls_start = ptr
			local found = false

			while ptr < sourceSize do
				if ptr >= nextCheckpoint then yieldLexer(ptr) end
				if buffer.readu8(buff, ptr) == 93 then
					local c2 = ptr + 1
					local cc = 0

					while c2 < sourceSize and buffer.readu8(buff, c2) == 61 do
						c2 += 1
						cc += 1
					end

					if cc == count and c2 < sourceSize and buffer.readu8(buff, c2) == 93 then
						next_type = 278 -- RawString
						next_string = buffer.readstring(buff, ls_start, ptr - ls_start)
						ptr = c2 + 1
						next_aux = count
						found = true
						break
					end
				elseif buffer.readu8(buff, ptr) == 10 then
					cur_line += 1
					cur_line_offset = ptr + 1
				end
				ptr += 1
			end
			if not found then
				next_type = 286 -- BrokenString
			end
		elseif count == 0 then
			next_type = 91 -- [
		else
			next_type = 286 -- BrokenString
		end
	elseif ch == 64 then -- @
		if ptr < sourceSize and buffer.readu8(buff, ptr) == 91 then
			ptr += 1
			next_type = 285 -- AttributeOpen
		else
			next_type = 284 -- Attribute
			if ptr < sourceSize then
				const first = buffer.readu8(buff, ptr)
				if buffer.readu8(IdentifierCharactersLookup, first) == 1 then
					const name_start = ptr
					ptr += 1
					while ptr < sourceSize do
						if ptr >= nextCheckpoint then yieldLexer(ptr) end
						const c = buffer.readu8(buff, ptr)
						if buffer.readu8(IdentifierCharactersLookup, c) ~= 0 then
							ptr += 1
						else
							break
						end
					end
					next_string = buffer.readstring(buff, name_start, ptr - name_start)
				else
					next_string = ""
				end
			else
				next_string = ""
			end
		end
	else
		if bit32.btest(ch, 0x80) then
			local cp = 0
			local seq_len = 0
			if bit32.band(ch, 0xE0) == 0xC0 then
				seq_len = 1
				cp = bit32.band(ch, 0x1F)
			elseif bit32.band(ch, 0xF0) == 0xE0 then
				seq_len = 2
				cp = bit32.band(ch, 0x0F)
			elseif bit32.band(ch, 0xF8) == 0xF0 then
				seq_len = 3
				cp = bit32.band(ch, 0x07)
			else
				next_type = 288 -- BrokenUnicode
				seq_len = -1 -- signal fail
			end

			if seq_len ~= -1 then
				local ok = true
				for i = 1, seq_len do
					if ptr >= sourceSize then
						ok = false
						break
					end

					const c = buffer.readu8(buff, ptr)
					if bit32.band(c, 0xC0) ~= 0x80 then
						ok = false
						break
					end

					cp = bit32.lshift(cp, 6) + bit32.band(c, 0x3F)
					ptr += 1
				end

				if ok then
					next_type = 288 -- BrokenUnicode
					next_codepoint = cp
				else
					next_type = 288 -- BrokenUnicode
				end
			end
		else
			next_type = ch
		end
	end

	-- Sync State
	offset = ptr
	line = cur_line
	lineOffset = cur_line_offset
	next_end_line = cur_line
	next_end_col = ptr - cur_line_offset
end

-- // Parser Interface
const function fillNext()
	while true do
		lex(not captureComments) -- writes to next_*
		if onLexeme and next_type ~= 0 then onLexeme(next_type, tokenOffset + 1, offset + 1) end

		if next_type == 282 or next_type == 283 or next_type == 287 then -- Comment / BlockComment / BrokenComment
			if captureComments then
				if commentLocations == EmptyArray then
					commentLocations = {}
				end
				table.insert(commentLocations, {
					type = next_type,
					location = {
						begin = vector.create(next_start_line, next_start_col),
						end_ = vector.create(next_end_line, next_end_col),
					},
				})
			end

			if next_type == 282 and next_string and string.byte(next_string :: string, 1) == 33 then -- Comment and '!'
				if hotcomments == EmptyArray then
					hotcomments = {}
				end
				const text = next_string :: string
				local ending = #text

				while ending > 0 do
					const byte = string.byte(text, ending)
					if byte and Spaces[byte] then
						ending -= 1
					else
						break
					end
				end

				table.insert(
					hotcomments,
					{
						header = hotcommentHeader,
						location = {
							begin = vector.create(next_start_line, next_start_col),
							end_ = vector.create(next_end_line, next_end_col),
						},
						content = string.sub(text, 2, ending),
					} :: HotComment
				)
			end

			if next_type == 287 then return end -- BrokenComment
			continue
		end

		break
	end
end

const function nextLexeme()
	-- Save previous current to prev
	prev_start_line = token_start_line
	prev_start_col = token_start_col
	prev_end_line = token_end_line
	prev_end_col = token_end_col

	-- Move NEXT to CURRENT
	token_type = next_type
	token_start_line = next_start_line
	token_start_col = next_start_col
	token_end_line = next_end_line
	token_end_col = next_end_col
	token_string = next_string
	token_aux = next_aux
	token_codepoint = next_codepoint

	-- Refill NEXT
	fillNext()
end

-- // Parser Commons

const function snapshot(): Location
	return {
		begin = vector.create(token_start_line, token_start_col),
		end_ = vector.create(token_end_line, token_end_col),
	}
end

const function getprev(): Location
	return {
		begin = vector.create(prev_start_line, prev_start_col),
		end_ = vector.create(prev_end_line, prev_end_col),
	}
end

-- // Error reports

const function positionsEqual(a: Position, b: Position): boolean
	return a.x == b.x and a.y == b.y
end

const function locationsEqual(a: Location, b: Location): boolean
	return positionsEqual(a.begin, b.begin) and positionsEqual(a.end_, b.end_)
end

const function report(loc: Location, fmt: string, ...: unknown)
	if #parseErrors > 0 and locationsEqual(parseErrors[#parseErrors].location, loc) then
		return
	end

	const msg = string.format(fmt, ...)
	if parseErrors == EmptyArray then
		parseErrors = {}
	end
	table.insert(parseErrors, { location = loc, message = msg })

	if LuauParseErrorLimit == 1 then
		error(msg, 0)
	end

	if #parseErrors >= LuauParseErrorLimit and not options.noErrorLimit then
		error(`Reached error limit ({LuauParseErrorLimit})`, 0)
	end
end

const function expectAndConsumeFail(type_: number, context: string?)
	const typeString = ToString(type_)
	const lexString = ToString(token_type, token_string, token_codepoint)

	if context then
		report(snapshot(), "Expected %s when parsing %s, got %s", typeString, context, lexString)
	else
		report(snapshot(), "Expected %s, got %s", typeString, lexString)
	end
end

const function expectMatchAndConsumeFail(
	type_: number,
	begin_type: number,
	line: number,
	column: number,
	extra: string?
)
	const typeString = ToString(type_)
	const matchString = ToString(begin_type)
	const currString = ToString(token_type, token_string, token_codepoint)

	if token_start_line == line then
		report(
			snapshot(),
			"Expected %s (to close %s at column %d), got %s%s",
			typeString,
			matchString,
			column + 1,
			currString,
			extra or ""
		)
	else
		report(
			snapshot(),
			"Expected %s (to close %s at line %d), got %s%s",
			typeString,
			matchString,
			line + 1,
			currString,
			extra or ""
		)
	end
end

const function expectAndConsume(type_: number, context: string?): boolean
	if token_type ~= type_ then
		expectAndConsumeFail(type_, context)

		if next_type == type_ then
			nextLexeme()
			nextLexeme()
		end

		return false
	end

	nextLexeme()
	return true
end

const function expectMatchAndConsume(
	value: number,
	begin_type: number,
	line: number,
	column: number,
	searchForMissing: boolean?
): boolean
	if token_type ~= value then
		expectMatchAndConsumeFail(value, begin_type, line, column)

		if searchForMissing then
			const currentLine = prev_end_line
			local type_ = token_type

			while currentLine == token_start_line and type_ ~= value and matchRecovery[type_] == 0 do
				nextLexeme()
				type_ = token_type
			end

			if type_ == value then
				nextLexeme()
				return true
			end
		else
			if next_type == value then
				nextLexeme()
				nextLexeme()
				return true
			end
		end

		return false
	end

	nextLexeme()
	return true
end

const function expectMatchEndAndConsume(type_: number, begin_type: number, line: number, column: number): boolean
	if token_type ~= type_ then
		if suspect_type ~= 0 and suspect_line > line then
			expectMatchAndConsumeFail(type_, begin_type, line, column,
				string.format(
				"; did you forget to close %s at line %d?",
				ToString(suspect_type, token_string, token_codepoint),
				suspect_line + 1
				)
			)
		else
			expectMatchAndConsumeFail(type_, begin_type, line, column)
		end

		if next_type == type_ then
			nextLexeme()
			nextLexeme()
			return true
		end

		return false
	end

	if token_start_line ~= line and token_start_col ~= column and suspect_line < line then
		suspect_line = line
		suspect_type = begin_type
	end

	nextLexeme()
	return true
end

-- // Ast reports

const function reportStatError(
	location: Location,
	exprs: { AstExpr },
	stats: { AstStat },
	fmt: string,
	...: unknown
): AstStatError
	report(location, fmt, ...)

	return {
		kind = "StatError",
		location = location,
		expressions = exprs,
		statements = stats,
		messageIndex = #parseErrors,
	}
end

const function reportExprError(
	location: Location,
	exprs: { AstExpr },
	fmt: string,
	...: unknown
): AstExprError
	report(location, fmt, ...)

	return {
		kind = "ExprError",
		location = location,
		expressions = exprs,
		messageIndex = #parseErrors,
	}
end

const function reportTypeError(
	location: Location,
	types: { AstType },
	fmt: string,
	...: unknown
): AstTypeError
	report(location, fmt, ...)

	return {
		kind = "TypeError",
		location = location,
		types = types,
		isMissing = false,
		messageIndex = #parseErrors,
	}
end

const function reportMissingTypeError(
	parseErrorLocation: Location,
	astErrorLocation: Location,
	fmt: string,
	...: unknown
): AstTypeError
	report(parseErrorLocation, fmt, ...)

	return {
		kind = "TypeError",
		location = astErrorLocation,
		types = EmptyArray :: { AstType },
		isMissing = true,
		messageIndex = #parseErrors,
	}
end

const function reportNameError(context: string?)
	const currString = ToString(token_type, token_string, token_codepoint)
	if context then
		report(snapshot(), "Expected identifier when parsing %s, got %s", context, currString)
	else
		report(snapshot(), "Expected identifier, got %s", currString)
	end
end

-- // Locals Helpers

const function restoreLocals(offset: number)
	for i = #localStack, offset + 1, -1 do
		const l = localStack[i] :: AstLocal
		localMap[l.name] = l.shadow
	end

	for i = #localStack, offset + 1, -1 do
		localStack[i] = nil
	end
end

const function pushLocal(binding: Binding): AstLocal
	const name = binding.name.value
	const shadow = localMap[name]

	const local_ = {
		name = name,
		location = binding.location,
		shadow = shadow,
		functionDepth = #functionStack - 1,
		loopDepth = functionStack[#functionStack].loopDepth,
		annotation = binding.annotation,
		isConst = binding.isConst == true,
		isExported = false,
	} :: AstLocal

	localMap[name] = local_
	table.insert(localStack, local_)

	return local_
end

const function incrementRecursionCounter(context: string)
	recursionCounter += 1

	if recursionCounter > LuauRecursionLimit then
		const msg = `Exceeded allowed recursion depth; simplify your {context} to make the code compile`
		report(snapshot(), "%s", msg)
		error(msg, 0)
	end
end

const function isExprLValue(expr: AstExpr): boolean
	if expr.kind == "ExprLocal" then
		const local_ = expr["local"]
		return local_.isConst ~= true
	end

	if expr.kind == "ExprGlobal" and Flags.DebugLuauUserDefinedClasses and classesWithinModule[expr.name] then
		return false
	end

	return ExprLValues[expr.kind] == true
end

const function reportLValueError(expr: AstExpr): AstExprError
	if expr.kind == "ExprLocal" and expr["local"].isConst == true then
		return reportExprError(
			expr.location,
			{ expr },
			"Variable '%s' is constant and may not be reassigned",
			expr["local"].name
		)
	end

	if expr.kind == "ExprGlobal" and Flags.DebugLuauUserDefinedClasses then
		const classStat = classesWithinModule[expr.name]
		if classStat then
			return reportExprError(
				expr.location,
				{ expr },
				"'%s' refers to a class and cannot be used as a variable name (defined on line %d)",
				expr.name,
				classStat.location.begin.x + 1
			)
		end
	end

	return reportExprError(expr.location, { expr }, "Assigned expression must be a variable or a field")
end

-- // The core of the code

local typeFunctionDepth = 0

type ParserFunctionTable = {
	parseStat: () -> AstStat,
	parseReturnType: () -> AstTypePack,
	parseSimpleType: (boolean, boolean) -> (AstType?, AstTypePack?),
	parseExpr: (number?) -> AstExpr,
}

const ParserFunctions = {} :: ParserFunctionTable

const function parseNameScalars(context: string?): (string?, number, number, number, number)
	if token_type ~= 281 then
		reportNameError(context)
		return nil, token_start_line, token_start_col, token_end_line, token_end_col
	end

	const name = token_string :: string
	const startLine, startColumn = token_start_line, token_start_col
	const endLine, endColumn = token_end_line, token_end_col

	nextLexeme()
	return name, startLine, startColumn, endLine, endColumn
end

const function parseNameOptImpl(context: string?): Binding?
	const name, startLine, startColumn, endLine, endColumn = parseNameScalars(context)
	if not name then
		return nil
	end

	const result = {
		name = { value = name },
		location = {
			begin = vector.create(startLine, startColumn),
			end_ = vector.create(endLine, endColumn),
		},
	} :: Binding

	return result
end

-- Type ::=
--      nil |
--      Name[`.' Name] [`<' namelist `>'] |
--      `{' [PropList] `}' |
--      `(' [TypeList] `)' `->` ReturnType
--      `typeof` Type
const function parseTypeSuffixImpl(type_: AstType?, beginLine: number, beginColumn: number): AstType
	const parts = {} :: { AstType }
	if type_ then
		table.insert(parts, type_)
	end

	incrementRecursionCounter("type annotation")

	local isUnion = false
	local isIntersection = false
	local optionalCount = 0

	const separatorPositions: { Position }? = if storeCstData then {} else nil
	local leadingPosition: Position? = nil

	while true do
		const t = token_type
		const separatorLine, separatorColumn = token_start_line, token_start_col

		if t == 124 then
			nextLexeme()

			const oldRecursion = recursionCounter

			const typePart, _ = ParserFunctions.parseSimpleType(false, false)
			if typePart then
				table.insert(parts, typePart)
			end

			recursionCounter = oldRecursion

			isUnion = true

			if separatorPositions then
				const separatorPosition = vector.create(separatorLine, separatorColumn)
				if type_ == nil and not leadingPosition then
					leadingPosition = separatorPosition
				else
					table.insert(separatorPositions, separatorPosition)
				end
			end
		elseif t == 63 then
			const loc = snapshot()
			nextLexeme()

			table.insert(parts, { kind = "TypeOptional", location = loc } :: AstTypeOptional)

			optionalCount += 1
			isUnion = true
		elseif t == 38 then
			nextLexeme()

			const oldRecursion = recursionCounter

			const typePart, _ = ParserFunctions.parseSimpleType(false, false)
			if typePart then
				table.insert(parts, typePart)
			end

			recursionCounter = oldRecursion

			isIntersection = true

			if separatorPositions then
				const separatorPosition = vector.create(separatorLine, separatorColumn)
				if type_ == nil and not leadingPosition then
					leadingPosition = separatorPosition
				else
					table.insert(separatorPositions, separatorPosition)
				end
			end
		elseif t == 262 then
			report(snapshot(), "Unexpected '...' after type annotation")
			nextLexeme()
		else
			break
		end

		if #parts > LuauTypeLengthLimit + optionalCount then
			const msg = "Exceeded allowed type length; simplify your type annotation to make the code compile"
			report(parts[#parts].location, "%s", msg)
			error(msg, 0)
		end
	end

	if #parts == 1 and not isUnion and not isIntersection then
		return parts[1]
	end

	if isUnion and isIntersection then
		return reportTypeError(
			{
				begin = vector.create(beginLine, beginColumn),
				end_ = parts[#parts].location.end_,
			},
			parts,
			"Mixing union and intersection types is not allowed; consider wrapping in parentheses."
		)
	end

	const loc = {
		begin = vector.create(beginLine, beginColumn),
		end_ = parts[#parts].location.end_,
	}

	if isUnion then
		const node = { kind = "TypeUnion", location = loc, types = parts } :: AstTypeUnion
		if separatorPositions then
			node.cstNode = {
				kind = "CstTypeUnion",
				leadingPosition = leadingPosition,
				separatorPositions = separatorPositions,
			}
		end
		return node
	end

	if isIntersection then
		const node = { kind = "TypeIntersection", location = loc, types = parts } :: AstTypeIntersection
		if separatorPositions then
			node.cstNode = {
				kind = "CstTypeIntersection",
				leadingPosition = leadingPosition,
				separatorPositions = separatorPositions,
			}
		end
		return node
	end

	return parts[1]
end

const function parseTypeImpl(inDeclarationContext: boolean?): AstType
	const oldRec = recursionCounter
	-- recursion counter is incremented in parseSimpleType and/or parseTypeSuffix

	const beginLine, beginColumn = token_start_line, token_start_col

	local type_: AstType? = nil

	if token_type ~= 124 and token_type ~= 38 then
		type_ = ParserFunctions.parseSimpleType(false, inDeclarationContext or false)
		recursionCounter = oldRec
	end

	const typeWithSuffix = parseTypeSuffixImpl(type_, beginLine, beginColumn)
	recursionCounter = oldRec

	return typeWithSuffix
end

const function parseOptionalTypeImpl(): AstType?
	if token_type == 58 then
		nextLexeme()
		return parseTypeImpl(false)
	else
		return nil
	end
end

const function parseBinding(isConst: boolean?): Binding
	local name, startLine, startColumn, endLine, endColumn = parseNameScalars("variable name")
	name = name or "%error-id%"

	const colonPos = if storeCstData and token_type == 58 then vector.create(token_start_line, token_start_col) else nil
	const annotation = parseOptionalTypeImpl()

	return {
		name = { value = name },
		location = {
			begin = vector.create(startLine, startColumn),
			end_ = vector.create(endLine, endColumn),
		},
		annotation = annotation,
		colonPosition = colonPos,
		isConst = isConst == true,
	} :: Binding
end

const function parseVariadicArgumentTypePackImpl(): AstTypePackVariadic | AstTypePackGeneric
	-- Generic: a...
	if token_type == 281 and next_type == 262 then
		const name, startLine, startColumn = parseNameScalars("generic name")
		const endStartLine, endStartColumn = token_start_line, token_start_col
		const endLine, endColumn = token_end_line, token_end_col

		-- This will not fail because of the lookahead guard.
		expectAndConsume(262, "generic type pack annotation")

		const node = {
			kind = "TypePackGeneric",
			location = {
				begin = vector.create(startLine, startColumn),
				end_ = vector.create(endLine, endColumn),
			},
			genericName = name :: string,
		} :: AstTypePackGeneric

		if storeCstData then
			node.cstNode = {
				kind = "CstTypePackGeneric",
				ellipsisPosition = vector.create(endStartLine, endStartColumn),
			}
		end

		return node
	else -- Variadic: T
		const varTy = parseTypeImpl(false)

		return {
			kind = "TypePackVariadic",
			location = varTy.location,
			variadicType = varTy,
		}
	end
end

-- bindinglist ::= (binding | `...') [`,' bindinglist]
const function parseBindingList(
	result: { Binding },
	allowDot3: boolean,
	commaPositions: { Position }?,
	initialComma: Position?,
	varargAnnotColonPos: { Position? }?,
	isConst: boolean?
): (boolean, Location?, AstTypePack?)
	const localCommaPositions: { Position }? = if commaPositions then {} else nil

	if localCommaPositions and initialComma then
		table.insert(localCommaPositions, initialComma)
	end

	while true do
		if token_type == 262 and allowDot3 then
			const varargLocation = snapshot()
			nextLexeme()

			local tailAnnotation: AstTypePack? = nil
			if token_type == 58 then
				if varargAnnotColonPos then
					varargAnnotColonPos[1] = vector.create(token_start_line, token_start_col)
				end

				nextLexeme()
				tailAnnotation = parseVariadicArgumentTypePackImpl()
			end

			if commaPositions and localCommaPositions then
				for _, v in localCommaPositions do
					table.insert(commaPositions, v)
				end
			end

			return true, varargLocation, tailAnnotation
		end

		table.insert(result, parseBinding(isConst))

		if token_type ~= 44 then
			break
		end

		if localCommaPositions then
			table.insert(localCommaPositions, vector.create(token_start_line, token_start_col))
		end

		nextLexeme()
	end

	if commaPositions and localCommaPositions then
		for _, v in localCommaPositions do
			table.insert(commaPositions, v)
		end
	end

	return false, nil, nil
end

const function parseBlockNoScope(): AstStatBlock
	const body: { AstStat } = {}

	const prevPos = vector.create(prev_end_line, prev_end_col)

	while not BlockFollow[token_type] do
		const oldRecursion = recursionCounter
		incrementRecursionCounter("block")

		const stat = ParserFunctions.parseStat()

		recursionCounter = oldRecursion

		if token_type == 59 then
			nextLexeme()
			stat.hasSemicolon = true

			stat.location.end_ = vector.create(prev_end_line, prev_end_col)
		end

		table.insert(body, stat)

		if stat.kind == "StatBreak" or stat.kind == "StatContinue" or stat.kind == "StatReturn" then
			break
		end
	end

	return {
		kind = "StatBlock",
		location = {
			begin = prevPos,
			end_ = vector.create(token_start_line, token_start_col),
		},
		body = body,
		hasEnd = false,
	} :: AstStatBlock
end

-- chunk ::= {stat [`;']} [laststat [`;']]
-- block ::= chunk
const function parseBlock(): AstStatBlock
	const localsBegin = #localStack
	const result = parseBlockNoScope()
	restoreLocals(localsBegin)
	return result
end

-- if exp then block {elseif exp then block} [else block] end
const function parseIfImpl(): AstStatIf
	const startLine, startColumn = token_start_line, token_start_col

	nextLexeme()

	const cond = ParserFunctions.parseExpr()

	const Then_start_line, Then_start_col = token_start_line, token_start_col
	const Then_end_line, Then_end_col = token_end_line, token_end_col

	local thenLocation: Location? = nil
	if expectAndConsume(308, "if statement") then
		thenLocation = {
			begin = vector.create(Then_start_line, Then_start_col),
			end_ = vector.create(Then_end_line, Then_end_col),
		}
	end

	const thenbody = parseBlock()

	local elsebody: AstStat? = nil
	local endLine, endColumn = token_end_line, token_end_col
	local elseLocation: Location? = nil

	if token_type == 295 then
		thenbody.hasEnd = true
		const oldRecursionCount = recursionCounter
		incrementRecursionCounter("elseif")

		elseLocation = snapshot()
		elsebody = parseIfImpl()
		endLine, endColumn = elsebody.location.end_.x, elsebody.location.end_.y

		recursionCounter = oldRecursionCount
	else
		local ThenElse_type = token_type

		local ThenElse_start_line, ThenElse_start_col = token_start_line, token_start_col
		local ThenElse_end_line, ThenElse_end_col = token_end_line, token_end_col

		if token_type == 294 then
			thenbody.hasEnd = true
			elseLocation = snapshot()

			ThenElse_type = token_type

			ThenElse_start_line, ThenElse_start_col = token_start_line, token_start_col
			ThenElse_end_line, ThenElse_end_col = token_end_line, token_end_col

			nextLexeme()

			const body = parseBlock()
			body.location.begin = vector.create(ThenElse_end_line, ThenElse_end_col)
			elsebody = body
		end

		endLine, endColumn = token_end_line, token_end_col

		const hasEnd = expectMatchEndAndConsume(296, ThenElse_type, ThenElse_start_line, ThenElse_start_col)

		if elsebody then
			if elsebody.kind == "StatBlock" then
				elsebody.hasEnd = hasEnd
			end
		else
			thenbody.hasEnd = hasEnd
		end
	end

	return {
		kind = "StatIf",
		location = {
			begin = vector.create(startLine, startColumn),
			end_ = vector.create(endLine, endColumn),
		},
		condition = cond,
		thenbody = thenbody,
		elsebody = elsebody,
		thenLocation = thenLocation,
		elseLocation = elseLocation,
	} :: AstStatIf
end

-- while exp do block end
const function parseWhileImpl(): AstStatWhile
	const startLine, startColumn = token_start_line, token_start_col
	nextLexeme()

	const cond = ParserFunctions.parseExpr()

	const Do_type = token_type

	const Do_start_line, Do_start_col = token_start_line, token_start_col
	const Do_end_line, Do_end_col = token_end_line, token_end_col

	const hasDo = expectAndConsume(293, "while loop")

	functionStack[#functionStack].loopDepth += 1

	const body = parseBlock()

	functionStack[#functionStack].loopDepth -= 1

	const endLine, endColumn = token_end_line, token_end_col
	const hasEnd = expectMatchEndAndConsume(296, Do_type, Do_start_line, Do_start_col)

	body.hasEnd = hasEnd

	return {
		kind = "StatWhile",
		location = {
			begin = vector.create(startLine, startColumn),
			end_ = vector.create(endLine, endColumn),
		},
		condition = cond,
		body = body,
		hasDo = hasDo,
		doLocation = {
			begin = vector.create(Do_start_line, Do_start_col),
			end_ = vector.create(Do_end_line, Do_end_col),
		},
	} :: AstStatWhile
end

-- repeat block until exp
const function parseRepeatImpl(): AstStatRepeat
	const startLine, startColumn = token_start_line, token_start_col

	const Repeat_type = token_type
	const Repeat_start_line, Repeat_start_col = token_start_line, token_start_col

	nextLexeme() -- repeat

	const localsBegin = #localStack

	functionStack[#functionStack].loopDepth += 1

	const body = parseBlockNoScope()

	functionStack[#functionStack].loopDepth -= 1

	local untilLine, untilColumn = 0, 0
	const hasUntil = expectMatchEndAndConsume(310, Repeat_type, Repeat_start_line, Repeat_start_col)
	body.hasEnd = hasUntil
	if hasUntil then
		untilLine, untilColumn = prev_start_line, prev_start_col
	end

	const cond = ParserFunctions.parseExpr()

	restoreLocals(localsBegin)

	const node = {
		kind = "StatRepeat",
		location = {
			begin = vector.create(startLine, startColumn),
			end_ = cond.location.end_,
		},
		condition = cond,
		body = body,
		hasUntil = hasUntil,
	} :: AstStatRepeat

	if storeCstData then
		node.cstNode = {
			kind = "CstStatRepeat",
			untilPosition = vector.create(untilLine, untilColumn),
		}
	end

	return node
end

-- do block end
const function parseDoImpl(): AstStatBlock
	const startLine, startColumn = token_start_line, token_start_col

	const Do_type = token_type
	const Do_start_line, Do_start_col = token_start_line, token_start_col

	nextLexeme() -- do

	const statsStartLine, statsStartColumn = token_start_line, token_start_col

	const body = parseBlock()
	body.location.begin = vector.create(startLine, startColumn)

	const endStartLine, endStartColumn = token_start_line, token_start_col
	const endLine, endColumn = token_end_line, token_end_col
	body.hasEnd = expectMatchEndAndConsume(296, Do_type, Do_start_line, Do_start_col)

	if body.hasEnd then
		body.location.end_ = vector.create(endLine, endColumn)
	end

	if storeCstData then
		body.cstNode = {
			kind = "CstStatDo",
			statsStart = vector.create(statsStartLine, statsStartColumn),
			endPosition = if body.hasEnd
				then vector.create(endStartLine, endStartColumn)
				else vector.create(0, 0),
		} :: CstStatDo
	end

	return body
end

-- break
const function parseBreakImpl(): AstStatBreak | AstStatError
	const start = snapshot()
	nextLexeme() -- break

	if functionStack[#functionStack].loopDepth == 0 then
		return reportStatError(
			start,
			{},
			{ { kind = "StatBreak", location = start } },
			"break statement must be inside a loop"
		)
	end

	return {
		kind = "StatBreak",
		location = start,
	}
end

-- continue
const function parseContinueImpl(start: Location): AstStatContinue | AstStatError
	if functionStack[#functionStack].loopDepth == 0 then
		return reportStatError(
			start,
			{},
			{ { kind = "StatContinue", location = start } },
			"continue statement must be inside a loop"
		)
	end

	-- note: the token is already parsed for us!

	return {
		kind = "StatContinue",
		location = start,
	}
end

const function extractAnnotationColonPositions(bindings: { Binding }): { Position? }
	const positions: { Position? } = {}
	for i, binding in bindings do
		positions[i] = binding.colonPosition
	end
	return positions
end

-- explist ::= {exp `,'} exp
const function parseExprListImpl(result: { AstExpr }, commaPositions: { Position }?)
	table.insert(result, ParserFunctions.parseExpr())

	while token_type == 44 do
		if commaPositions then
			table.insert(commaPositions, vector.create(token_start_line, token_start_col))
		end

		nextLexeme()
		if token_type == 41 then
			report(snapshot(), "Expected expression after ',' but got ')' instead")

			break
		end

		table.insert(result, ParserFunctions.parseExpr())
	end
end

-- for binding `=' exp `,' exp [`,' exp] do block end |
-- for bindinglist in explist do block end |
const function parseForImpl(): AstStatFor | AstStatForIn
	const startLine, startColumn = token_start_line, token_start_col
	nextLexeme() -- for

	const varname = parseBinding()

	if token_type == 61 then
		const equalsPosition = if storeCstData then vector.create(token_start_line, token_start_col) else nil
		nextLexeme()

		const from = ParserFunctions.parseExpr()

		local endCommaPosition: Position? = if storeCstData then vector.create(0, 0) else nil
		if expectAndConsume(44, "index range") then
			if endCommaPosition then
				endCommaPosition = vector.create(prev_start_line, prev_start_col)
			end
		end

		const to = ParserFunctions.parseExpr()

		local stepCommaPosition: Position? = nil
		local step: AstExpr? = nil

		if token_type == 44 then
			if storeCstData then
				stepCommaPosition = vector.create(token_start_line, token_start_col)
			end
			nextLexeme()
			step = ParserFunctions.parseExpr()
		end

		const Do_type = token_type

		const Do_start_line, Do_start_col = token_start_line, token_start_col
		const Do_end_line, Do_end_col = token_end_line, token_end_col

		const hasDo = expectAndConsume(293, "for loop")

		const localsBegin = #localStack
		functionStack[#functionStack].loopDepth += 1

		const var = pushLocal(varname)

		const body = parseBlock()

		functionStack[#functionStack].loopDepth -= 1
		restoreLocals(localsBegin)

		const end_ = vector.create(token_end_line, token_end_col)
		const hasEnd = expectMatchEndAndConsume(296, Do_type, Do_start_line, Do_start_col)
		body.hasEnd = hasEnd

		const node = {
			kind = "StatFor",
			location = {
				begin = vector.create(startLine, startColumn),
				end_ = end_,
			},
			var = var,
			from = from,
			to = to,
			step = step,
			body = body,
			hasDo = hasDo,
			doLocation = {
				begin = vector.create(Do_start_line, Do_start_col),
				end_ = vector.create(Do_end_line, Do_end_col),
			},
		} :: AstStatFor

		if equalsPosition and endCommaPosition then
			node.cstNode = {
				kind = "CstStatFor",
				annotationColonPosition = varname.colonPosition,
				equalsPosition = equalsPosition,
				endCommaPosition = endCommaPosition,
				stepCommaPosition = stepCommaPosition,
			}
		end

		return node
	else
		const names = { varname }
		const varsCommaPosition: { Position }? = if storeCstData then {} else nil

		if token_type == 44 then
			const initialCommaPos = if storeCstData then vector.create(token_start_line, token_start_col) else nil
			nextLexeme()
			parseBindingList(names, false, varsCommaPosition, initialCommaPos)
		end

		const inLocation = snapshot()
		const hasIn = expectAndConsume(301, "for loop")

		const values: { AstExpr } = {}

		const valuesCommaPositions: { Position }? = if storeCstData then {} else nil
		parseExprListImpl(values, valuesCommaPositions)

		const Do_type = token_type

		const Do_start_line, Do_start_col = token_start_line, token_start_col
		const Do_end_line, Do_end_col = token_end_line, token_end_col

		const hasDo = expectAndConsume(293, "for loop")

		const localsBegin = #localStack
		functionStack[#functionStack].loopDepth += 1

		const vars = {} :: { AstLocal }
		for _, binding in names do
			table.insert(vars, pushLocal(binding))
		end

		const body = parseBlock()

		functionStack[#functionStack].loopDepth -= 1
		restoreLocals(localsBegin)

		const end_ = vector.create(token_end_line, token_end_col)

		const hasEnd = expectMatchEndAndConsume(296, Do_type, Do_start_line, Do_start_col)
		body.hasEnd = hasEnd

		const node = {
			kind = "StatForIn",
			location = {
				begin = vector.create(startLine, startColumn),
				end_ = end_,
			},
			vars = vars,
			values = values,
			body = body,
			hasIn = hasIn,
			inLocation = inLocation,
			hasDo = hasDo,
			doLocation = {
				begin = vector.create(Do_start_line, Do_start_col),
				end_ = vector.create(Do_end_line, Do_end_col),
			},
		} :: AstStatForIn

		if varsCommaPosition and valuesCommaPositions then
			node.cstNode = {
				kind = "CstStatForIn",
				varsAnnotationColonPositions = extractAnnotationColonPositions(names),
				varsCommaPositions = varsCommaPosition,
				valuesCommaPositions = valuesCommaPositions,
			}
		end

		return node
	end
end

-- NAME
const function parseNameExprImpl(context: string): AstExprLocal | AstExprGlobal | AstExprError
	const name, startLine, startColumn, endLine, endColumn = parseNameScalars(context)

	if not name then
		return {
			kind = "ExprError",
			location = snapshot(),
			expressions = {},
			messageIndex = #parseErrors,
		}
	end

	const nameLocation = {
		begin = vector.create(startLine, startColumn),
		end_ = vector.create(endLine, endColumn),
	}
	const local_ = localMap[name]

	if local_ then
		if local_.functionDepth < (typeFunctionDepth or 0) then
			return reportExprError(snapshot(), {}, "Type function cannot reference outer local '%s'", local_.name)
		end

		return {
			kind = "ExprLocal",
			location = nameLocation,
			["local"] = local_,
			upvalue = local_.functionDepth ~= (#functionStack - 1),
		}
	end

	return {
		kind = "ExprGlobal",
		location = nameLocation,
		name = name,
	}
end

-- funcname ::= Name {`.' Name} [`:' Name]
const function parseFunctionName(): (AstExprIndexName, boolean, string?)
	local hasSelf = false
	local debugname = if token_type == 281 then token_string else nil

	-- parse funcname into a chain of indexing operators
	local expr = parseNameExprImpl("function name")

	const oldRecursionCount = recursionCounter

	while token_type == 46 do
		const opPosition = vector.create(token_start_line, token_start_col)
		nextLexeme()

		local name, startLine, startColumn, endLine, endColumn = parseNameScalars("field name")
		name = name or "%error-id%"
		const nameLocation = {
			begin = vector.create(startLine, startColumn),
			end_ = vector.create(endLine, endColumn),
		}

		-- while we could concatenate the name chain, for now let's just write the short name
		debugname = name

		expr = {
			kind = "ExprIndexName",
			location = {
				begin = expr.location.begin,
				end_ = nameLocation.end_,
			},
			expr = expr,
			index = name,
			indexLocation = nameLocation,
			opPosition = opPosition,
			op = 46,
		}

		-- note: while the parser isn't recursive here, we're generating recursive structures of unbounded depth
		incrementRecursionCounter("function name")
	end

	recursionCounter = oldRecursionCount

	-- finish with :
	if token_type == 58 then
		const opPosition = vector.create(token_start_line, token_start_col)
		nextLexeme()

		local name, startLine, startColumn, endLine, endColumn = parseNameScalars("method name")
		name = name or "%error-id%"
		const nameLocation = {
			begin = vector.create(startLine, startColumn),
			end_ = vector.create(endLine, endColumn),
		}

		-- while we could concatenate the name chain, for now let's just write the short name
		debugname = name

		expr = {
			kind = "ExprIndexName",
			location = {
				begin = expr.location.begin,
				end_ = nameLocation.end_,
			},
			expr = expr,
			index = name,
			indexLocation = nameLocation,
			opPosition = opPosition,
			op = 58,
		}

		hasSelf = true
	end

	return expr :: AstExprIndexName, hasSelf, debugname
end

const function shouldParseTypePack()
	const t = token_type

	if t == 262 then
		return true
	end

	if t == 281 and next_type == 262 then
		return true
	end

	return false
end

const function parseTypePackImpl(): AstTypePackVariadic | AstTypePackGeneric
	-- Variadic: ...T
	if token_type == 262 then
		const startLine, startColumn = token_start_line, token_start_col
		nextLexeme()
		const varTy = parseTypeImpl(false)
		return {
			kind = "TypePackVariadic",
			location = {
				begin = vector.create(startLine, startColumn),
				end_ = varTy.location.end_,
			},
			variadicType = varTy,
		}

		-- Generic: a...
	elseif token_type == 281 and next_type == 262 then
		const name, startLine, startColumn = parseNameScalars("generic name")
		const endStartLine, endStartColumn = token_start_line, token_start_col
		const endLine, endColumn = token_end_line, token_end_col

		-- This will not fail because of the lookahead guard.
		expectAndConsume(262, "generic type pack annotation")

		const node = {
			kind = "TypePackGeneric",
			location = {
				begin = vector.create(startLine, startColumn),
				end_ = vector.create(endLine, endColumn),
			},
			genericName = name :: string,
		}

		if storeCstData then
			node.cstNode = {
				kind = "CstTypePackGeneric",
				ellipsisPosition = vector.create(endStartLine, endStartColumn),
			}
		end

		return node :: AstTypePackGeneric
	end

	-- TODO: shouldParseTypePack can be removed and parseTypePack can be called unconditionally instead
	error("parseTypePack can't be called if shouldParseTypePack() returned false")
end

const function parseSimpleTypeOrPackImpl(): (AstType?, AstTypePack?)
	const oldRec = recursionCounter
	-- recursion counter is incremented in parseSimpleType

	const beginLine, beginColumn = token_start_line, token_start_col

	const type_, typePack = ParserFunctions.parseSimpleType(true, false)

	if typePack then
		return nil, typePack
	end

	recursionCounter = oldRec

	return parseTypeSuffixImpl(type_, beginLine, beginColumn), nil
end

const function parseGenericTypeListImpl(
	withDefaultValues: boolean,
	openPosRef: { Position }?,
	commaPosRef: { Position }?,
	closePosRef: { Position }?
): ({ AstGenericType }, { AstGenericTypePack })
	if token_type ~= 60 then
		return EmptyArray :: { AstGenericType }, EmptyArray :: { AstGenericTypePack }
	end

	const names: { AstGenericType } = {}
	const namePacks: { AstGenericTypePack } = {}
	const localCommaPositions: { Position }? = if commaPosRef then {} else nil

	if token_type == 60 then
		const begin_type = token_type
		const begin_start_line, begin_start_col = token_start_line, token_start_col

		if openPosRef then
			openPosRef[1] = vector.create(begin_start_line, begin_start_col)
		end

		nextLexeme()

		local seenPack = false
		local seenDefault = false

		while true do
			const nameLoc = snapshot()
			local name = parseNameScalars()
			name = name or "%error-id%"

			if token_type == 262 or seenPack then
				seenPack = true
				local ellipsisLine, ellipsisColumn = 0, 0

				if token_type ~= 262 then
					report(snapshot(), "Generic types come before generic type packs")
				else
					ellipsisLine, ellipsisColumn = token_start_line, token_start_col
					nextLexeme()
				end

				if withDefaultValues and token_type == 61 then
					seenDefault = true
					const equalsLine, equalsColumn = token_start_line, token_start_col
					nextLexeme()

					local typePack: AstTypePack? = nil
					if shouldParseTypePack() then
						typePack = parseTypePackImpl()
					else
						const type_, pack_ = parseSimpleTypeOrPackImpl()
						if type_ then
							report(type_.location, "Expected type pack after '=', got type")
						end
						typePack = pack_
					end

					const node = {
						kind = "GenericTypePack",
						location = nameLoc,
						name = name,
						defaultValue = typePack,
					} :: AstGenericTypePack

					if storeCstData then
						node.cstNode = {
							kind = "CstGenericTypePack",
							ellipsisPosition = vector.create(ellipsisLine, ellipsisColumn),
							defaultEqualsPosition = vector.create(equalsLine, equalsColumn),
						} :: CstGenericTypePack
					end

					table.insert(namePacks, node)
				else
					if seenDefault then
						report(snapshot(), "Expected default type pack after type pack name")
					end

					const node = {
						kind = "GenericTypePack",
						location = nameLoc,
						name = name,
						defaultValue = nil,
					} :: AstGenericTypePack

					if storeCstData then
						node.cstNode = {
							kind = "CstGenericTypePack",
							ellipsisPosition = vector.create(ellipsisLine, ellipsisColumn),
							defaultEqualsPosition = nil,
						} :: CstGenericTypePack
					end

					table.insert(namePacks, node)
				end
			else
				if withDefaultValues and token_type == 61 then
					seenDefault = true
					const equalsLine, equalsColumn = token_start_line, token_start_col
					nextLexeme()

					const defaultType = parseTypeImpl()

					const node = {
						kind = "GenericType",
						location = nameLoc,
						name = name,
						defaultValue = defaultType,
					} :: AstGenericType

					if storeCstData then
						node.cstNode = {
							kind = "CstGenericType",
							defaultEqualsPosition = vector.create(equalsLine, equalsColumn),
						} :: CstGenericType
					end
					table.insert(names, node)
				else
					if seenDefault then
						report(snapshot(), "Expected default type after type name")
					end

					const node = {
						kind = "GenericType",
						location = nameLoc,
						name = name,
						defaultValue = nil,
					} :: AstGenericType

					if storeCstData then
						node.cstNode = {
							kind = "CstGenericType",
							defaultEqualsPosition = nil,
						} :: CstGenericType
					end
					table.insert(names, node)
				end
			end

			if token_type == 44 then
					if localCommaPositions then
						table.insert(localCommaPositions, vector.create(token_start_line, token_start_col))
				end
				nextLexeme()

				if token_type == 62 then
					report(snapshot(), "Expected type after ',' but got '>' instead")
					break
				end
			else
				break
			end
		end

		if expectMatchAndConsume(62, begin_type, begin_start_line, begin_start_col) and closePosRef then
			closePosRef[1] = vector.create(prev_start_line, prev_start_col)
		end
	end

	if commaPosRef and localCommaPositions then
		for _, v in localCommaPositions do
			table.insert(commaPosRef, v)
		end
	end

	return names, namePacks
end

const function parseOptionalReturnTypeImpl(returnSpecifierPosRef: { Position }?): AstTypePack?
	if token_type == 58 or token_type == 263 then
		if token_type == 263 then
			report(snapshot(), "Function return type annotations are written after ':' instead of '->'")
		end

		if returnSpecifierPosRef then
			returnSpecifierPosRef[1] = vector.create(token_start_line, token_start_col)
		end

		nextLexeme()

		const oldRecursion = recursionCounter
		const res = ParserFunctions.parseReturnType()
		recursionCounter = oldRecursion

		-- At this point, if we find a , character, it indicates that there are multiple return types
		-- in this type annotation, but the list wasn't wrapped in parentheses.
		if token_type == 44 then
			report(
				snapshot(),
				"Expected a statement, got ','; did you forget to wrap the list of return types in parentheses?"
			)
			nextLexeme()
		end

		return res
	end

	return nil
end

const function prepareFunctionArgumentsImpl(start: Location, hasself: boolean, args: { Binding }): (AstLocal?, { AstLocal })
	local selfLocal: AstLocal? = nil
	if hasself then
		selfLocal = pushLocal({
			name = { value = "self" },
			location = start,
			annotation = nil,
			colonPosition = nil,
		})
	end

	if #args == 0 then
		return selfLocal, EmptyArray :: { AstLocal }
	end

	const vars: { AstLocal } = {}
	for _, arg in args do
		table.insert(vars, pushLocal(arg))
	end

	return selfLocal, vars
end

-- funcbody ::= `(' [parlist] `)' [`:' ReturnType] block end
-- parlist ::= bindinglist [`,' `...'] | `...'
const function parseFunctionBodyImpl(
	hasself: boolean,
	matchFunctionType: number,
	matchFunctionLine: number,
	matchFunctionColumn: number,
	matchFunctionEndLine: number,
	matchFunctionEndColumn: number,
	debugname: string?,
	localName: string?,
	localNameLocation: Location?,
	attributes: Attrs,
	cstAttrLists: { CstAttrList }?,
	isConst: boolean?
): (AstExprFunction, AstLocal?)
	const matchFunctionLocation = {
		begin = vector.create(matchFunctionLine, matchFunctionColumn),
		end_ = vector.create(matchFunctionEndLine, matchFunctionEndColumn),
	}
	local start = matchFunctionLocation
	if #attributes > 0 then
		start = attributes[1].location
	end

	local cstNode: CstExprFunction? = nil
	if storeCstData then
		cstNode = {
			kind = "CstExprFunction",
			attrLists = cstAttrLists or {},
			functionKeywordPosition = matchFunctionLocation.begin,
			openGenericsPosition = vector.create(0, 0),
			genericsCommaPositions = {},
			closeGenericsPosition = vector.create(0, 0),
			argsAnnotationColonPositions = {},
			argsCommaPositions = {},
			varargAnnotationColonPosition = vector.create(0, 0),
			returnSpecifierPosition = vector.create(0, 0),
		} :: CstExprFunction
	end

	const openGenPosRef = cstNode and { cstNode.openGenericsPosition } or nil
	const genCommaPosRef = cstNode and cstNode.genericsCommaPositions or nil
	const closeGenPosRef = cstNode and { cstNode.closeGenericsPosition } or nil

	const generics, genericPacks = parseGenericTypeListImpl(false, openGenPosRef, genCommaPosRef, closeGenPosRef)

	if cstNode and openGenPosRef then
		cstNode.openGenericsPosition = openGenPosRef[1]
	end
	if cstNode and closeGenPosRef then
		cstNode.closeGenericsPosition = closeGenPosRef[1]
	end

	const Paren_type = token_type
	const Paren_line = token_start_line
	const Paren_col = token_start_col

	expectAndConsume(40, "function")

	-- NOTE: This was added in conjunction with passing `searchForMissing` to
	-- `expectMatchAndConsume` inside `parseTableType` so that the behavior of
	-- parsing code like below (note the missing `}`):

	-- function (t: { a: number  ) end

	-- ... will still parse as (roughly):

	-- function (t: { a: number }) end

	matchRecovery[41] += 1

	local args = EmptyArray :: { Binding }
	local vararg = false
	local varargLocation: Location? = nil
	local varargAnnotation: AstTypePack? = nil

	if token_type ~= 41 then
		args = {}
		const vaAnnotPosRef = cstNode and { cstNode.varargAnnotationColonPosition :: Position? } or nil

		vararg, varargLocation, varargAnnotation =
			parseBindingList(args, true, if cstNode then cstNode.argsCommaPositions else nil, nil, vaAnnotPosRef, false)

		if cstNode and vaAnnotPosRef then
			cstNode.varargAnnotationColonPosition = vaAnnotPosRef[1]
		end
	end

	local argLocation: Location? = nil
	if Paren_type == 40 and token_type == 41 then
		argLocation = {
			begin = vector.create(Paren_line, Paren_col),
			end_ = vector.create(token_end_line, token_end_col),
		}
	end

	expectMatchAndConsume(41, Paren_type, Paren_line, Paren_col, true)
	matchRecovery[41] -= 1

	const retSpecPosRef = cstNode and { cstNode.returnSpecifierPosition } or nil
	const typelist = parseOptionalReturnTypeImpl(retSpecPosRef)
	if cstNode and retSpecPosRef then
		cstNode.returnSpecifierPosition = retSpecPosRef[1]
	end

	local funLocal: AstLocal? = nil
	if localName then
		const bindingLocation = localNameLocation or start
		funLocal = pushLocal({
			name = { value = localName },
			location = bindingLocation,
			annotation = nil,
			colonPosition = nil,
			isConst = isConst == true,
		} :: Binding)
	end

	const localsBegin = #localStack

	const fun = { vararg = vararg, loopDepth = 0 } :: FunctionState
	table.insert(functionStack, fun)

	const selfLocal, vars = prepareFunctionArgumentsImpl(start, hasself, args)

	const body = parseBlock()

	table.remove(functionStack)

	restoreLocals(localsBegin)

	const endPosition = vector.create(token_end_line, token_end_col)
	const hasEnd = expectMatchEndAndConsume(
		296,
		matchFunctionType,
		matchFunctionLine,
		matchFunctionColumn
	)
	body.hasEnd = hasEnd

	const node = {
		kind = "ExprFunction",
		location = { begin = start.begin, end_ = endPosition },
		attributes = attributes,
		generics = generics,
		genericPacks = genericPacks,
		self = selfLocal,
		args = vars,
		vararg = vararg,
		varargLocation = varargLocation,
		body = body,
		functionDepth = #functionStack,
		debugname = debugname,
		returnAnnotation = typelist,
		varargAnnotation = varargAnnotation,
		argLocation = argLocation,
	} :: AstExprFunction

	if storeCstData and cstNode then
		cstNode.argsAnnotationColonPositions = extractAnnotationColonPositions(args)
		node.cstNode = cstNode
	end

	return node, funLocal
end

-- function funcname funcbody
const function parseFunctionStatImpl(
	attributes: Attrs,
	attributeStartLocation: Location?,
	cstAttrLists: { CstAttrList }?
): AstStatFunction
	local startPosition = vector.create(token_start_line, token_start_col)
	if attributeStartLocation ~= nil then
		startPosition = attributeStartLocation.begin
	elseif #attributes > 0 then
		startPosition = attributes[1].location.begin
	end

	const matchFunctionType = token_type
	const matchFunctionLine, matchFunctionColumn = token_start_line, token_start_col
	const matchFunctionEndLine, matchFunctionEndColumn = token_end_line, token_end_col
	nextLexeme()

	local expr: AstExpr, hasSelf, debugname = parseFunctionName()

	if not isExprLValue(expr) then
		expr = if Flags.LuauExportValueSyntax
			then reportLValueError(expr)
			else reportExprError(expr.location, { expr }, "Assigned expression must be a variable or a field")
	end

	matchRecovery[296] += 1

	const body = parseFunctionBodyImpl(
		hasSelf,
		matchFunctionType,
		matchFunctionLine,
		matchFunctionColumn,
		matchFunctionEndLine,
		matchFunctionEndColumn,
		debugname,
		nil,
		nil,
		attributes,
		nil,
		false
	)

	matchRecovery[296] -= 1

	const node = {
		kind = "StatFunction",
		location = {
			begin = startPosition,
			end_ = body.location.end_,
		},
		name = expr,
		func = body,
	} :: AstStatFunction

	if storeCstData then
		node.cstNode = {
			kind = "CstStatFunction",
			attrLists = cstAttrLists or {},
			functionKeywordPosition = vector.create(matchFunctionLine, matchFunctionColumn),
		}
	end

	return node
end

const function validateAttribute(
	loc: Location,
	attributeName: string,
	attributes: Attrs,
	args: { AstExpr }
)
	-- check if the attribute name is valid
	const entry = kAttributeEntries[attributeName]
	local type_: string? = nil
	local argsValidator: ((Location, { AstExpr }) -> { ParseError })? = nil

	if entry then
		type_ = entry.type
		argsValidator = entry.argsValidator
	elseif Flags.DebugLuauNoInline and kDebugAttributeEntries[attributeName] then
		type_ = kDebugAttributeEntries[attributeName].type
	else
		if #attributeName == 0 then
			report(loc, "Attribute name is missing")
		else
			report(loc, "Invalid attribute '@%s'", attributeName)
		end
	end

	if type_ then
		-- check that attribute is not duplicated
		for _, attr in attributes do
			if attr.type == type_ then
				report(loc, "Cannot duplicate attribute '@%s'", attributeName)
			end
		end

		if argsValidator then
			const validator = argsValidator :: (Location, { AstExpr }) -> { ParseError }
			const errors = validator(loc, args)
			for _, err in errors do
				report(err.location, "%s", err.message)
			end
		end
	end

	return type_
end

const function tableSeparator(): number?
	if token_type == 44 then
		return 0
	elseif token_type == 59 then
		return 1
	else
		return nil
	end
end

const function cstSeparatorPosition(separator: number?): Position
	return if separator == nil then vector.create(0, 0) else vector.create(token_start_line, token_start_col)
end

-- tableconstructor ::= `{' [fieldlist] `}'
-- fieldlist ::= field {fieldsep field} [fieldsep]
-- field ::= `[' exp `]' `=' exp | Name `=' exp | exp
-- fieldsep ::= `,' | `;'
const function parseTableConstructorImpl(): AstExprTable
	const items = {} :: { AstExprTableItem }
	const cstItems: { CstExprTableItem }? = if storeCstData then {} else nil

	const startLine, startColumn = token_start_line, token_start_col

	const brace_type, brace_line, brace_col = token_type, token_start_line, token_start_col
	expectAndConsume(123, "table literal")

	while token_type ~= 125 do
		local indexerOpenPos: Position? = nil
		local indexerClosePos: Position? = nil
		local equalsPos: Position? = nil

		if token_type == 91 then
			if cstItems then
				indexerOpenPos = vector.create(token_start_line, token_start_col)
			end
			const bracket_type, bracket_line, bracket_col = token_type, token_start_line, token_start_col
			nextLexeme()

			const key = ParserFunctions.parseExpr()

			if expectMatchAndConsume(93, bracket_type, bracket_line, bracket_col) then
				if cstItems then
					indexerClosePos = vector.create(prev_start_line, prev_start_col)
				end
			end

			if expectAndConsume(61, "table field") then
				if cstItems then
					equalsPos = vector.create(prev_start_line, prev_start_col)
				end
			end

			const value = ParserFunctions.parseExpr()

			table.insert(
				items,
				{
					kind = "General",
					key = key,
					value = value,
				} :: AstExprTableItem
			)

			if cstItems then
				const separator = tableSeparator()
				table.insert(
					cstItems,
					{
						kind = "General",
						indexerOpenPosition = indexerOpenPos,
						indexerClosePosition = indexerClosePos,
						equalsPosition = equalsPos,
						separator = separator,
						separatorPosition = cstSeparatorPosition(separator),
					} :: CstExprTableItem
				)
			end
		elseif token_type == 281 and next_type == 61 then
			const name, nameStartLine, nameStartColumn, nameEndLine, nameEndColumn =
				parseNameScalars("table field")
			const fieldName = name :: string

			if expectAndConsume(61, "table field") then
				if cstItems then
					equalsPos = vector.create(prev_start_line, prev_start_col)
				end
			end

			const key = {
				kind = "ExprConstantString",
				location = {
					begin = vector.create(nameStartLine, nameStartColumn),
					end_ = vector.create(nameEndLine, nameEndColumn),
				},
				value = fieldName,
				quoteStyle = QuoteStyle.Unquoted,
			}

			const value = ParserFunctions.parseExpr()

			if value.kind == "ExprFunction" then
				value.debugname = fieldName
			end

			table.insert(
				items,
				{
					kind = "Record",
					key = key,
					value = value,
				} :: AstExprTableItem
			)

			if cstItems then
				const separator = tableSeparator()
				table.insert(
					cstItems,
					{
						kind = "Record",
						equalsPosition = equalsPos,
						separator = separator,
						separatorPosition = cstSeparatorPosition(separator),
					} :: CstExprTableItem
				)
			end
		else
			const expr = ParserFunctions.parseExpr()
			table.insert(
				items,
				{
					kind = "List",
					value = expr,
				} :: AstExprTableItem
			)

			if cstItems then
				const separator = tableSeparator()
				table.insert(
					cstItems,
					{
						kind = "List",
						separator = separator,
						separatorPosition = cstSeparatorPosition(separator),
					} :: CstExprTableItem
				)
			end
		end

		if token_type == 44 or token_type == 59 then
			nextLexeme()
		elseif token_type == 91 or token_type == 281 then
			report(snapshot(), "Expected ',' after table constructor element")
		elseif token_type ~= 125 then
			break
		end
	end

	local endLine, endColumn = token_end_line, token_end_col
	if not expectMatchAndConsume(125, brace_type, brace_line, brace_col) then
		endLine, endColumn = prev_end_line, prev_end_col
	end

	const node = {
		kind = "ExprTable",
		location = {
			begin = vector.create(startLine, startColumn),
			end_ = vector.create(endLine, endColumn),
		},
		items = items,
	} :: AstExprTable

	if cstItems then
		node.cstNode = {
			kind = "CstExprTable",
			items = cstItems,
		} :: CstExprTable
	end

	return node
end

const function extractStringDetails()
	local style = 0
	local depth = 0

	if token_type == 279 then
		style = token_aux == 0 and CstQuotes.QuotedSingle or CstQuotes.QuotedDouble
	elseif token_type == 269 then
		style = CstQuotes.QuotedInterp
	elseif token_type == 278 then
		style = CstQuotes.QuotedRaw
		depth = token_aux or 0
	end

	return style, depth
end

const function parseCharArrayImpl(): string?
	const t = token_type
	local data = token_string or ""

	if t == 279 or t == 269 then
		const ok, fixed = fixupQuotedString(data)
		if not ok then
			nextLexeme()
			return nil
		end
		data = fixed :: string
	else
		data = fixupMultilineString(data)
	end

	nextLexeme()
	return data
end

const function parseStringImpl(): AstExprConstantString | AstExprError
	const location = snapshot()
	local quoteStyle = QuoteStyle.QuotedSimple

	if token_type == 279 then
		if token_aux == 0 then
			quoteStyle = QuoteStyle.QuotedSingle
		else
			quoteStyle = QuoteStyle.QuotedSimple
		end
	elseif token_type == 269 then
		quoteStyle = QuoteStyle.QuotedSimple
	elseif token_type == 278 then
		quoteStyle = QuoteStyle.QuotedRaw
	end

	local fullStyle = 0
	local blockDepth = 0
	if storeCstData then
		fullStyle, blockDepth = extractStringDetails()
	end

	local originalString: string? = nil
	if storeCstData then
		originalString = token_string
	end

	const value = parseCharArrayImpl()

	if value then
		const node = {
			kind = "ExprConstantString",
			location = location,
			value = value,
			quoteStyle = quoteStyle,
		} :: AstExprConstantString

		if storeCstData then
			node.cstNode = {
				kind = "CstExprConstantString",
				sourceString = originalString,
				quoteStyle = fullStyle,
				blockDepth = blockDepth,
			}
		end

		return node :: AstExprConstantString
	else
		return reportExprError(location, {}, "String literal contains malformed escape sequence")
	end
end

const function parseCallListImpl(commaPositions: { Position }?): (
	{ AstExpr },
	Location,
	Location,
	Position?
)
	if token_type == 40 then
		const argStart = vector.create(token_end_line, token_end_col)
		const paren_type, paren_line, paren_col = token_type, token_start_line, token_start_col

		nextLexeme()

		const args: { AstExpr } = {}

		if token_type ~= 41 then
			parseExprListImpl(args, commaPositions)
		end

		const endStartLine, endStartColumn = token_start_line, token_start_col
		const endLine, endColumn = token_end_line, token_end_col
		local closeParenPosition: Position? = nil
		if expectMatchAndConsume(41, paren_type, paren_line, paren_col) then
			if commaPositions then
				closeParenPosition = vector.create(endStartLine, endStartColumn)
			end
		end

		return args,
			{
				begin = argStart,
				end_ = vector.create(endLine, endColumn),
			},
			{
				begin = vector.create(paren_line, paren_col),
				end_ = vector.create(prev_start_line, prev_start_col),
			},
			closeParenPosition
	elseif token_type == 123 then
		const argStart = vector.create(token_end_line, token_end_col)
		const expr = parseTableConstructorImpl()

		return { expr } :: { AstExpr },
			{
				begin = argStart,
				end_ = vector.create(prev_end_line, prev_end_col),
			},
			expr.location,
			nil
	else
		const argLoc = snapshot()
		const expr = parseStringImpl()
		return { expr } :: { AstExpr }, argLoc, expr.location, nil
	end
end

-- attribute ::= '@' NAME
const function parseAttribute(attributes: Attrs): (Location, CstAttrList?)
	if token_type == 284 then
		const loc = snapshot()
		const name = token_string or ""
		const type_ = validateAttribute(loc, name, attributes, EmptyArray :: { AstExpr })
		nextLexeme()
		const attr = {
			kind = "Attr",
			location = loc,
			type = type_ or "Unknown",
			args = EmptyArray :: { AstExpr },
			name = name,
		} :: AstAttr

		if storeCstData then
			attr.cstNode = {
				kind = "CstAttr",
				hasAt = true,
			}
		end

		table.insert(attributes, attr)

		return loc, nil
	else
		const open_type = token_type
		const open_start_line, open_start_col = token_start_line, token_start_col
		const openLocation = {
			begin = vector.create(open_start_line, open_start_col),
			end_ = vector.create(open_start_line, open_start_col),
		}
		const commaPositions: { Position }? = if storeCstData then {} else nil

		nextLexeme()
		if token_type ~= 93 then
			while true do
				local attrName, nameStartLine, nameStartColumn, nameEndLine, nameEndColumn =
					parseNameScalars("attribute name")
				if not attrName then
					attrName = "%error-id%"
					nameEndLine, nameEndColumn = nameStartLine, nameStartColumn
				end
				const nameLoc = {
					begin = vector.create(nameStartLine, nameStartColumn),
					end_ = vector.create(nameEndLine, nameEndColumn),
				}
				local args: { AstExpr } = {}
				local argsLocation = nameLoc
				local hasArgs = false
				local openParenLine, openParenColumn = 0, 0
				local closeParenLine, closeParenColumn = 0, 0
				const argsCommaPositions: { Position }? = if storeCstData then {} else nil

				if token_type == 278 or token_type == 279 or token_type == 123 or token_type == 40 then
					const argOpenType = token_type
					if argOpenType == 40 then
						openParenLine, openParenColumn = token_start_line, token_start_col
					end

					const args_, argsLoc_, _, parsedCloseParenPosition =
						parseCallListImpl(argsCommaPositions)
					args = args_
					argsLocation = argsLoc_
					hasArgs = true
					if argOpenType == 40 and parsedCloseParenPosition then
						closeParenLine = parsedCloseParenPosition.x
						closeParenColumn = parsedCloseParenPosition.y
					end

					for _, arg in args do
						if not ConstantLiteral[arg.kind] and not isLiteralTable(arg) then
							report(argsLocation, "Only literals can be passed as arguments for attributes")
						end
					end
				end

				const type_ = validateAttribute(nameLoc, attrName, attributes, args)
				local attrLocation = nameLoc
				if hasArgs then
					attrLocation = {
						begin = nameLoc.begin,
						end_ = argsLocation.end_,
					}
				end

				const attr = {
					kind = "Attr",
					location = attrLocation,
					type = type_ or "Unknown",
					args = args,
					name = attrName,
				} :: AstAttr

				if storeCstData then
					attr.cstNode = if hasArgs
						then {
							kind = "CstParametrizedAttr",
							openParenPosition = vector.create(openParenLine, openParenColumn),
							closeParenPosition = vector.create(closeParenLine, closeParenColumn),
							argsCommaPositions = argsCommaPositions :: { Position },
						}
						else {
							kind = "CstAttr",
							hasAt = false,
						}
				end

				table.insert(attributes, attr)

				if token_type == 44 then
					if commaPositions then
						table.insert(commaPositions, vector.create(token_start_line, token_start_col))
					end
					nextLexeme()
				else
					break
				end
			end
		else
			const errorLocation = {
				begin = vector.create(open_start_line, open_start_col),
				end_ = vector.create(token_end_line, token_end_col),
			}

			report(errorLocation, "Attribute list cannot be empty")

			const attr = {
				kind = "Attr",
				location = errorLocation,
				type = "Unknown",
				args = EmptyArray :: { AstExpr },
				name = "%error-id%",
			} :: AstAttr

			if storeCstData then
				attr.cstNode = {
					kind = "CstAttr",
					hasAt = false,
				}
			end

			table.insert(attributes, attr)
		end

		const closeBracketLine = if token_type == 93 then token_start_line else 0
		const closeBracketColumn = if token_type == 93 then token_start_col else 0
		expectMatchAndConsume(93, open_type, open_start_line, open_start_col)

		const cstList: CstAttrList? = if storeCstData
			then {
				kind = "CstAttrList",
				atBracketPosition = openLocation.begin,
				closeBracketPosition = vector.create(closeBracketLine, closeBracketColumn),
				commaPositions = commaPositions :: { Position },
			}
			else nil

		return openLocation, cstList
	end
end

-- attributes ::= {attribute}
const function parseAttributes(): (Attrs, Location?, { CstAttrList }?)
	const attributes: Attrs = {}
	local startLocation: Location? = nil
	const cstAttrLists: { CstAttrList }? = if storeCstData then {} else nil

	while token_type == 284 or token_type == 285 do
		const attributeStart, cstAttrList = parseAttribute(attributes)
		if startLocation == nil then
			startLocation = attributeStart
		end
		if cstAttrLists and cstAttrList then
			table.insert(cstAttrLists, cstAttrList)
		end
	end

	return attributes, startLocation, cstAttrLists
end

const function isEnoughValues(values: { AstExpr }, expected: number): boolean
	if #values > 0 then
		const last = values[#values]
		if last.kind == "ExprCall" or last.kind == "ExprVarargs" then
			return true
		end
	end

	return #values == expected
end

const function parseLocalImpl(
	start: Location,
	keywordPosition: Position,
	attributes: Attrs?,
	cstAttrLists: { CstAttrList }?,
	isConst: boolean
): AstStatLocal | AstStatLocalFunction | AstStatError
	if not isConst then
		nextLexeme() -- local
	end

	if token_type == 299 then
		const matchFunctionType = token_type
		const matchFunctionLine = token_start_line
		local matchFunctionColumn = token_start_col
		const matchFunctionEndLine, matchFunctionEndColumn = token_end_line, token_end_col
		nextLexeme()

		-- matchFunction is only used for diagnostics; to make it suitable for detecting missed indentation between
		-- `local function` and `end`, we patch the token to begin at the column where `local` starts
		if matchFunctionLine == start.begin.x then
			matchFunctionColumn = start.begin.y
		end

		local name, nameStartLine, nameStartColumn, nameEndLine, nameEndColumn =
			parseNameScalars("variable name")
		name = name or "%error-id%"
		const nameLocation = {
			begin = vector.create(nameStartLine, nameStartColumn),
			end_ = vector.create(nameEndLine, nameEndColumn),
		}

		matchRecovery[296] += 1

		const body, var = parseFunctionBodyImpl(
			false,
			matchFunctionType,
			matchFunctionLine,
			matchFunctionColumn,
			matchFunctionEndLine,
			matchFunctionEndColumn,
			name,
			name,
			nameLocation,
			attributes or (EmptyArray :: Attrs),
			nil,
			isConst
		)

		matchRecovery[296] -= 1

		const node = {
			kind = "StatLocalFunction",
			location = { begin = start.begin, end_ = body.location.end_ },
			name = var,
			func = body,
			isConst = isConst,
			constKeywordBegin = if isConst and Flags.LuauStoreConstKeywordBegin then keywordPosition else nil,
		} :: AstStatLocalFunction

		if storeCstData then
			node.cstNode = {
				kind = "CstStatLocalFunction",
				attrLists = cstAttrLists or {},
				localKeywordPosition = keywordPosition,
				functionKeywordPosition = vector.create(matchFunctionLine, matchFunctionColumn),
			}
		end

		return node
	else
		if attributes and #attributes ~= 0 then
			return reportStatError(
				snapshot(),
				{},
				{},
				"Expected 'function' after local declaration with attribute, but got %s instead",
				ToString(token_type, token_string, token_codepoint)
			)
		end

		matchRecovery[61] += 1

		const names: { Binding } = {}
		const varsCommaPositions: { Position }? = if storeCstData then {} else nil
		parseBindingList(names, false, varsCommaPositions, nil, nil, isConst)

		matchRecovery[61] -= 1

		const vars: { AstLocal } = {}
		const values: { AstExpr } = {}
		const valuesCommaPositions: { Position }? = if storeCstData then {} else nil
		local equalsSignLocation: Location? = nil

		if token_type == 61 then
			equalsSignLocation = snapshot()
			nextLexeme()
			parseExprListImpl(values, valuesCommaPositions)
		end

		for _, binding in names do
			table.insert(vars, pushLocal(binding))
		end

		local end_
		if #values == 0 then
			end_ = vector.create(prev_end_line, prev_end_col)
		else
			end_ = values[#values].location.end_
		end

		if isConst and not isEnoughValues(values, #vars) then
			report({ begin = start.begin, end_ = end_ }, "Missing initializer in const declaration")
		end

		const node = {
			kind = "StatLocal",
			location = { begin = start.begin, end_ = end_ },
			vars = vars,
			values = values,
			equalsSignLocation = equalsSignLocation,
			isConst = isConst,
			isExported = false,
		} :: AstStatLocal

		if varsCommaPositions and valuesCommaPositions then
			node.cstNode = {
				kind = "CstStatLocal",
				varsAnnotationColonPositions = extractAnnotationColonPositions(names),
				varsCommaPositions = varsCommaPositions,
				valuesCommaPositions = valuesCommaPositions,
			}
		end

		return node
	end
end

const function checkDuplicateExport(name: string, location: Location): boolean
	if declaredExportBindings[name] then
		return false
	end

	if declaredExportBindings == EmptyArray then
		declaredExportBindings = {}
	end
	declaredExportBindings[name] = location
	return true
end

const function exportLocalStat(stat: AstStat, keywordLocation: Location): AstStat
	if stat.kind == "StatLocal" then
		stat.isExported = true

		for _, local_ in stat.vars do
			if not checkDuplicateExport(local_.name, local_.location) then
				report(local_.location, "Duplicate exported identifier '%s'", local_.name)
			else
				local_.isExported = true
			end
		end

		stat.keywordLocation = keywordLocation
	end

	return stat
end

-- classrefexp -> NAME { `.' NAME | `[' exp `]' }
const function parseClassRefExprImpl(): AstExpr
	const start = snapshot().begin
	const name = parseNameExprImpl("class reference expression")

	if token_type == 46 then
		const opPosition = snapshot().begin
		nextLexeme()
		const index, indexStartLine, indexStartColumn, indexEndLine, indexEndColumn =
			parseNameScalars("class reference expression")
		const indexName = index or "%error-id%"
		return {
			kind = "ExprIndexName",
			location = {
				begin = start,
				end_ = vector.create(indexEndLine, indexEndColumn),
			},
			expr = name,
			index = indexName,
			indexLocation = {
				begin = vector.create(indexStartLine, indexStartColumn),
				end_ = vector.create(indexEndLine, indexEndColumn),
			},
			opPosition = opPosition,
			op = 46,
		} :: AstExprIndexName
	elseif token_type == 91 then
		nextLexeme()
		const key = ParserFunctions.parseExpr()
		local endPosition = key.location.end_
		if expectAndConsume(93, "class reference expression") then
			endPosition = vector.create(prev_end_line, prev_end_col)
		end
		return {
			kind = "ExprIndexExpr",
			location = { begin = start, end_ = endPosition },
			expr = name,
			index = key,
		} :: AstExprIndexExpr
	end

	return name
end

const function parseClassStatImpl(
	start: Location,
	exported: boolean,
	open: boolean
): AstStatClass | AstStatError
	local name = parseNameOptImpl("type name")

	if not name then
		name = {
			name = { value = "%error-id%" },
			location = snapshot(),
		} :: Binding
	end
	const className = name :: Binding
	local superExpr: AstExpr? = nil
	if token_type == 281 and token_string == "extends" then
		nextLexeme()
		superExpr = parseClassRefExprImpl()
	end

	const nameLocal = {
		name = className.name.value,
		location = className.location,
		shadow = nil,
		functionDepth = #functionStack - 1,
		loopDepth = functionStack[#functionStack].loopDepth,
		annotation = nil,
		isConst = true,
		isExported = false,
	} :: AstLocal

	const members = {} :: { AstClassMember }
	const memberNames: { [string]: boolean } = {}

	while token_type ~= 296 and token_type ~= 0 do
		local qualifierLocation = nil :: Location?
		if token_type == 281 and token_string == "public" then
			qualifierLocation = snapshot()
			nextLexeme()
		end

		if qualifierLocation and token_type ~= 299 then
			const propName = parseNameOptImpl("class property name")
			if not propName then
				continue
			end

			local propType = nil :: AstType?
			local typeColonLocation = nil :: Location?

			if token_type == 58 then
				typeColonLocation = snapshot()
				nextLexeme()
				propType = parseTypeImpl()
			end

			if propName.name.value == "new" then
				report(propName.location, "Class properties cannot be named 'new'. Define a method named '__init' to define a constructor.")
			elseif string.sub(propName.name.value, 1, 2) == "__" then
				report(propName.location, "Class properties cannot start with '__'")
			elseif memberNames[propName.name.value] then
				report(propName.location, "Duplicate class member '%s'", propName.name.value)
			else
				memberNames[propName.name.value] = true
				table.insert(
					members,
					{
						kind = "ClassProperty",
						qualifierLocation = qualifierLocation,
						name = propName.name,
						nameLocation = propName.location,
						typeColonLocation = typeColonLocation,
						type = propType,
					} :: AstClassProperty
				)
			end
		elseif token_type == 299 then
			const matchFunctionType = token_type
			const matchFunctionLine, matchFunctionColumn = token_start_line, token_start_col
			const matchFunctionEndLine, matchFunctionEndColumn = token_end_line, token_end_col
			nextLexeme()

			local methodName, nameStartLine, nameStartColumn, nameEndLine, nameEndColumn =
				parseNameScalars("method name")
			methodName = methodName or "%error-id%"
			const methodNameLocation = {
				begin = vector.create(nameStartLine, nameStartColumn),
				end_ = vector.create(nameEndLine, nameEndColumn),
			}

			matchRecovery[296] += 1
			const body = parseFunctionBodyImpl(
				false,
				matchFunctionType,
				matchFunctionLine,
				matchFunctionColumn,
				matchFunctionEndLine,
				matchFunctionEndColumn,
				methodName,
				nil,
				nil,
				EmptyArray :: Attrs,
				nil,
				false
			)
			matchRecovery[296] -= 1

			const selfAnnotation = if #body.args > 0 and body.args[1].name == "self" then body.args[1].annotation else nil
			if selfAnnotation then
				report(selfAnnotation.location, "The 'self' parameter cannot have a type annotation")
			end

			if methodName == "new" then
				report(methodNameLocation, "Class methods cannot be named 'new'.  Name it '__init' to define a constructor.")
			elseif string.sub(methodName, 1, 2) == "__" then
				if DisallowedClassMetamethods[methodName] then
					report(methodNameLocation, "Classes cannot define '%s' as a metamethod", methodName)
				elseif not AllowedClassMetamethods[methodName] then
					report(
						methodNameLocation,
						"Cannot use '%s' as a method name: names starting with '__' are reserved",
						methodName
					)
				end
			end

			if methodName == "__init" then
				if #body.args < 1 then
					report(methodNameLocation, "__init must have at least one parameter")
				elseif body.args[1].name ~= "self" then
					report(body.args[1].location, "__init's first parameter must be named self")
				end
			end

			if memberNames[methodName] then
				report(methodNameLocation, "Duplicate class member '%s'", methodName)
			else
				memberNames[methodName] = true
				table.insert(
					members,
					{
						kind = "ClassMethod",
						qualifierLocation = qualifierLocation,
						keywordLocation = {
							begin = vector.create(matchFunctionLine, matchFunctionColumn),
							end_ = vector.create(matchFunctionEndLine, matchFunctionEndColumn),
						},
						functionName = { value = methodName },
						nameLocation = methodNameLocation,
						func = body,
					} :: AstClassMethod
				)
			end
		else
			report(snapshot(), "Only class properties and functions can be declared within a class")
			nextLexeme()
		end
	end

	const endLine, endColumn = token_end_line, token_end_col
	expectAndConsume(296, "class")

	const node = {
		kind = "StatClass",
		location = {
			begin = start.begin,
			end_ = vector.create(endLine, endColumn),
		},
		name = nameLocal,
		super = superExpr,
		members = members,
		exported = exported,
		open = open,
	} :: AstStatClass

	if recursionCounter > 1 then
		report(nameLocal.location, "Cannot declare class '%s' inside another statement or expression", nameLocal.name)
	end

	if classesWithinModule[nameLocal.name] then
		return reportStatError(
			nameLocal.location,
			{},
			{ node },
			"A class named '%s' has already been declared in this module",
			nameLocal.name
		)
	end

	if classesWithinModule == EmptyArray then
		classesWithinModule = {}
	end
	classesWithinModule[nameLocal.name] = node
	return node
end

const function parseExportValueImpl(
	start: Location,
	keywordPosition: Position,
	attributes: Attrs,
	cstAttrLists: { CstAttrList }?
): AstStat
	if #functionStack ~= 1 or recursionCounter ~= 1 then
		report(start, "'export' may only be applied to top-level statements")
	end

	if hasModuleReturn then
		report(start, "Exporting values is not compatible with top-level return (export/return conflict)")
	end

	if #attributes ~= 0 and token_type ~= 299 then
		report(
			snapshot(),
			"Expected 'function' after export declaration with attribute, but got %s instead",
			ToString(token_type, token_string, token_codepoint)
		)
	end

	if token_type == 302 then
		const localKeywordLocation = snapshot()

		if next_type == 299 then
			report(start, "'export' must be followed by an identifier or 'function'; try removing 'local'")
			return parseLocalImpl(start, localKeywordLocation.begin, nil, nil, true)
		end

		return exportLocalStat(parseLocalImpl(start, keywordPosition, nil, nil, false), localKeywordLocation)
	elseif token_type == 299 then
		const stat = parseLocalImpl(start, keywordPosition, attributes, cstAttrLists, true)

		if stat.kind == "StatLocalFunction" and stat.name then
			if not checkDuplicateExport(stat.name.name, stat.name.location) then
				report(stat.name.location, "Duplicate exported identifier '%s'", stat.name.name)
			end

			stat.name.isExported = true
			stat.name.isConst = true
		end

		return stat
	elseif token_type == 281 and token_string == "const" then
		const constKeywordLocation = snapshot()
		nextLexeme()

		if token_type == 299 then
			report(start, "'export' must be followed by an identifier or 'function'")
			return parseLocalImpl(start, constKeywordLocation.begin, nil, nil, true)
		end

		return exportLocalStat(parseLocalImpl(start, constKeywordLocation.begin, nil, nil, true), constKeywordLocation)
	elseif Flags.DebugLuauUserDefinedClasses and token_type == 281 and (token_string == "class" or token_string == "open") then
		const open = token_string == "open"
		nextLexeme()
		if open then
			if token_type ~= 281 or token_string ~= "class" then
				return reportStatError(start, {}, {}, "Incomplete statement: expected a class definition after 'open'")
			end
			nextLexeme()
		end
		const stat = parseClassStatImpl(start, true, open)

		if stat.kind == "StatClass" then
			if not checkDuplicateExport(stat.name.name, stat.name.location) then
				report(stat.name.location, "Duplicate exported class '%s'", stat.name.name)
			end

			stat.name.isExported = true
		end

		return stat
	end

	return reportStatError(start, {}, {}, "'export' must be followed by an identifier or 'function'")
end

-- prefixexp -> NAME | '(' expr ')'
const function parsePrefixExprImpl(): AstExpr
	if token_type == 40 then
		const start = vector.create(token_start_line, token_start_col)
		const Paren_type = token_type
		const Paren_line = token_start_line
		const Paren_col = token_start_col
		nextLexeme()

		const expr = ParserFunctions.parseExpr()

		local end_ = vector.create(token_end_line, token_end_col)
		local closeLine, closeColumn = 0, 0
		if token_type ~= 41 then
			expectMatchAndConsumeFail(

				41,
				Paren_type,
				Paren_line,
				Paren_col,
				token_type == 61 and "; did you mean to use '{' when defining a table?" or nil
			)

			end_ = vector.create(prev_end_line, prev_end_col)
		else
			closeLine, closeColumn = token_start_line, token_start_col
			nextLexeme()
		end

		const node = {
			kind = "ExprGroup",
			location = {
				begin = start,
				end_ = end_,
			},
			expr = expr,
		} :: AstExprGroup

		if storeCstData then
			node.cstNode = {
				kind = "CstExprGroup",
				closePosition = vector.create(closeLine, closeColumn),
			}
		end

		return node
	else
		return parseNameExprImpl("expression")
	end
end

const function parseIndexNameScalars(context: string?, prev: Position): (string?, number, number, number, number)
	if token_type == 281 then
		return parseNameScalars(context)
	end

	reportNameError(context)

	if token_type >= 291 and token_type < 312 and token_start_line == prev.x then
		const name = token_string
		const startLine, startColumn = token_start_line, token_start_col
		const endLine, endColumn = token_end_line, token_end_col
		nextLexeme()
		return name, startLine, startColumn, endLine, endColumn
	end

	return "%error-id%", token_start_line, token_start_col, token_end_line, token_end_col
end

const function parseTypeParamsImpl(
	openingPosRef: { Position }?,
	commaPosRef: { Position }?,
	closingPosRef: { Position }?
): { AstTypeOrPack }
	const params = {} :: { AstTypeOrPack }

	if token_type == 60 then
		const beginType = token_type
		const beginLine, beginColumn = token_start_line, token_start_col
		if openingPosRef then
			openingPosRef[1] = vector.create(beginLine, beginColumn)
		end

		nextLexeme()

		while true do
			if shouldParseTypePack() then
				const pack = parseTypePackImpl()
				table.insert(params, { typePack = pack, type = nil })
			elseif token_type == 40 then
				const beginParenLine, beginParenColumn = token_start_line, token_start_col
				local type_: AstType? = nil
				local typePack: AstTypePack? = nil
				const t = token_type

				if t ~= 124 and t ~= 38 then
					type_, typePack = ParserFunctions.parseSimpleType(true, false)
				end

				--/ Consider the following type:

				--  X<(T)>

				-- Is this a type pack or a parenthesized type? The
				-- assumption will be a type pack, as that's what allows one
				-- to express either a singular type pack or a potential
				-- complex type.

				if typePack then
					if
						typePack.kind == "TypePackExplicit"
						and #typePack.types == 1
						and not typePack.tailType
						and (token_type == 124 or token_type == 63 or token_type == 38)
					then
						-- If we parsed an explicit type pack with a single
						-- type in it (something of the form `(T)`), and
						-- the next lexeme is one that follows a type
						-- (&, |, ?), then assume that this was actually a
						-- parenthesized type.

						const parenTy = typePack.types[1]

						const node = {
							kind = "TypeGroup",
							location = parenTy.location,
							type = parenTy,
						} :: AstTypeGroup

						if storeCstData then
							local closePosition = parenTy.location.end_
							if typePack.cstNode and typePack.cstNode.closeParenthesesPosition then
								closePosition = typePack.cstNode.closeParenthesesPosition
							end

							node.cstNode = {
								kind = "CstTypeGroup",
								closePosition = closePosition,
							}
						end

						table.insert(
							params,
							{ type = parseTypeSuffixImpl(node, beginParenLine, beginParenColumn), typePack = nil }
						)
					else
						-- Otherwise, it's a type pack.
						table.insert(params, { type = nil, typePack = typePack })
					end
				else
					table.insert(
						params,
						{ type = parseTypeSuffixImpl(type_, beginParenLine, beginParenColumn), typePack = nil }
					)
				end
			elseif token_type == 62 and #params == 0 then
				break
			else
				table.insert(params, { type = parseTypeImpl(false), typePack = nil })
			end

			if token_type == 44 then
				if commaPosRef then
					table.insert(commaPosRef, vector.create(token_start_line, token_start_col))
				end
				nextLexeme()
			else
				break
			end
		end

		if expectMatchAndConsume(62, beginType, beginLine, beginColumn, false) and closingPosRef then
			closingPosRef[1] = vector.create(prev_start_line, prev_start_col)
		end
	end
	return params
end

-- // Explicit Type Instantiation

const function parseTypeInstantiationExpr(): ({ AstTypeOrPack }, CstTypeInstantiation?, Position)
	const begin_type, begin_line, begin_col = token_type, token_start_line, token_start_col
	const leftArrow1 = if storeCstData then vector.create(token_start_line, token_start_col) else nil
	nextLexeme()

	const leftArrow2Ref: { Position }? = if storeCstData then {} else nil
	const commaPositions: { Position }? = if storeCstData then {} else nil
	const rightArrow1Ref: { Position }? = if storeCstData then {} else nil

	const typesOrPacks = parseTypeParamsImpl(leftArrow2Ref, commaPositions, rightArrow1Ref)

	const endStartLine, endStartColumn = token_start_line, token_start_col
	const endPosition = vector.create(token_end_line, token_end_col)
	const rightArrow2 = if storeCstData
		then if token_type == 62
			then vector.create(endStartLine, endStartColumn)
			else vector.create(0, 0)
		else nil
	expectMatchAndConsume(62, begin_type, begin_line, begin_col)

	local cstData: CstTypeInstantiation? = nil
	if leftArrow1 and leftArrow2Ref and commaPositions and rightArrow1Ref and rightArrow2 then
		cstData = {
			kind = "CstTypeInstantiation",
			leftArrow1Position = leftArrow1,
			leftArrow2Position = leftArrow2Ref[1],
			commaPositions = commaPositions,
			rightArrow1Position = rightArrow1Ref[1],
			rightArrow2Position = rightArrow2,
		}
	end

	if cstData then
		return typesOrPacks, cstData :: CstTypeInstantiation, endPosition
	end

	return typesOrPacks, nil, endPosition
end

const function reportAmbiguousCallError()
	report(
		snapshot(),
		"Ambiguous syntax: this looks like an argument list for a function call, but could also be a start of new statement; use ';' to separate statements"
	)
end

const function reportFunctionArgsErrorImpl(func: AstExpr, selfCall: boolean): AstExpr
	if selfCall and token_start_line ~= func.location.end_.x then
		return reportExprError(func.location :: Location, { func }, "Expected function call arguments after '('")
	else
		return reportExprError(
			{
				begin = func.location.begin,
				end_ = vector.create(token_start_line, token_start_col),
			},
			{ func },
			"Expected '(', '{' or <string> when parsing function call, got %s",
			ToString(token_type, token_string, token_codepoint)
		)
	end
end

-- args ::=  `(' [explist] `)' | tableconstructor | String
const function parseFunctionArgsImpl(func: AstExpr, selfCall: boolean): AstExpr
	if token_type == 40 then
		const argStart = vector.create(token_end_line, token_end_col)
		if func.location.end_.x ~= token_start_line then
			reportAmbiguousCallError()
		end

		const paren_type, paren_line, paren_col = token_type, token_start_line, token_start_col
		nextLexeme()

		local args = EmptyArray :: { AstExpr }
		const commaPositions: { Position }? = if storeCstData then {} else nil
		if token_type ~= 41 then
			args = {}
			parseExprListImpl(args, commaPositions)
		end

		const endLine, endColumn = token_end_line, token_end_col
		local closeParen: Position? = if storeCstData then vector.create(0, 0) else nil
		if expectMatchAndConsume(41, paren_type, paren_line, paren_col) then
			if closeParen then
				closeParen = vector.create(prev_start_line, prev_start_col)
			end
		end

		const endPosition = vector.create(endLine, endColumn)
		const result = {
			kind = "ExprCall",
			location = { begin = func.location.begin, end_ = endPosition },
			func = func,
			args = args,
			self = selfCall,
			typeArguments = EmptyArray :: { AstTypeOrPack },
			argLocation = { begin = argStart, end_ = endPosition },
		} :: AstExprCall

		if commaPositions and closeParen then
			result.cstNode = {
				kind = "CstExprCall",
				openParens = vector.create(paren_line, paren_col),
				closeParens = closeParen,
				commaPositions = commaPositions,
				explicitTypes = nil,
			}
		end

		return result
	elseif token_type == 123 then
		const argStart = vector.create(token_end_line, token_end_col)
		const expr = parseTableConstructorImpl()
		const argEnd = vector.create(prev_end_line, prev_end_col)

		const result = {
			kind = "ExprCall",
			location = {
				begin = func.location.begin,
				end_ = expr.location.end_,
			},
			func = func,
			args = { expr },
			self = selfCall,
			typeArguments = EmptyArray :: { AstTypeOrPack },
			argLocation = {
				begin = argStart,
				end_ = argEnd,
			},
		} :: AstExprCall

		if storeCstData then
			result.cstNode = {
				kind = "CstExprCall",
				commaPositions = {},
				explicitTypes = nil,
			}
		end

		return result
	elseif token_type == 278 or token_type == 279 then
		const argLocation = snapshot()
		const expr = parseStringImpl()

		const result = {
			kind = "ExprCall",
			location = {
				begin = func.location.begin,
				end_ = expr.location.end_,
			},
			func = func,
			args = { expr },
			self = selfCall,
			typeArguments = EmptyArray :: { AstTypeOrPack },
			argLocation = argLocation,
		} :: AstExprCall

		if storeCstData then
			result.cstNode = {
				kind = "CstExprCall",
				commaPositions = {},
				explicitTypes = nil,
			}
		end

		return result
	else
		return reportFunctionArgsErrorImpl(func, selfCall)
	end
end

const function parseExplicitTypeInstantiationExpr(
	start: Position,
	basedOnExpr: AstExpr
): AstExprInstantiate
	const typesOrPacks, cstInstantiation, endPosition = parseTypeInstantiationExpr()

	const expr = {
		kind = "ExprInstantiate",
		location = { begin = start, end_ = endPosition },
		expr = basedOnExpr,
		typeArguments = typesOrPacks,
	} :: AstExprInstantiate

	if cstInstantiation then
		expr.cstNode = {
			kind = "CstExprExplicitTypeInstantiation",
			instantiation = cstInstantiation,
		}
	end

	return expr
end

-- primaryexp -> prefixexp { `.' NAME | `[' exp `]' | `:' NAME funcargs | funcargs }
const function parsePrimaryExprImpl(asStatement: boolean): AstExpr
	local expr: AstExpr = parsePrefixExprImpl()

	const oldRecursion = recursionCounter

	while true do
		if token_type == 46 then
			const opPosition = vector.create(token_start_line, token_start_col)
			nextLexeme()

			const index, indexStartLine, indexStartColumn, indexEndLine, indexEndColumn =
				parseIndexNameScalars(nil, opPosition)
			const indexLocation = {
				begin = vector.create(indexStartLine, indexStartColumn),
				end_ = vector.create(indexEndLine, indexEndColumn),
			}

			expr = {
				kind = "ExprIndexName",
				location = { begin = expr.location.begin, end_ = indexLocation.end_ },
				expr = expr,
				index = index,
				indexLocation = indexLocation,
				opPosition = opPosition,
				op = 46,
			} :: AstExprIndexName
		elseif token_type == 91 then
			const bracket_type, bracket_line, bracket_col = token_type, token_start_line, token_start_col
			nextLexeme()

			const index = ParserFunctions.parseExpr()
			const end_ = vector.create(token_end_line, token_end_col)
			local closeBracketLine, closeBracketColumn = 0, 0

			if expectMatchAndConsume(93, bracket_type, bracket_line, bracket_col) then
				closeBracketLine, closeBracketColumn = prev_start_line, prev_start_col
			end

			expr = {
				kind = "ExprIndexExpr",
				location = { begin = expr.location.begin, end_ = end_ },
				expr = expr,
				index = index,
			} :: AstExprIndexExpr

			if storeCstData then
				expr.cstNode = {
					kind = "CstExprIndexExpr",
					openBracketPosition = vector.create(bracket_line, bracket_col),
					closeBracketPosition = vector.create(closeBracketLine, closeBracketColumn),
				}
			end
		elseif token_type == 58 then
			const opPosition = vector.create(token_start_line, token_start_col)
			nextLexeme()

			const index, indexStartLine, indexStartColumn, indexEndLine, indexEndColumn =
				parseIndexNameScalars("method name", opPosition)
			const indexLocation = {
				begin = vector.create(indexStartLine, indexStartColumn),
				end_ = vector.create(indexEndLine, indexEndColumn),
			}

			const func = {
				kind = "ExprIndexName",
				location = { begin = expr.location.begin, end_ = indexLocation.end_ },
				expr = expr,
				index = index,
				indexLocation = indexLocation,
				opPosition = opPosition,
				op = 58,
			} :: AstExprIndexName

			local typeArgs: { AstTypeOrPack } = {}
			local cstInstantiation: CstTypeInstantiation? = nil

			if token_type == 60 and next_type == 60 then
				typeArgs, cstInstantiation = parseTypeInstantiationExpr()
			end

			const callExpr = parseFunctionArgsImpl(func, true)
			expr = callExpr

			if #typeArgs > 0 and callExpr.kind == "ExprCall" then
				callExpr.typeArguments = typeArgs
			end

			if storeCstData and cstInstantiation and (callExpr :: AstExprCall).cstNode then
				(callExpr.cstNode :: CstExprCall).explicitTypes = cstInstantiation
			end
		elseif token_type == 40 then
			-- This error is handled inside 'parseFunctionArgs' as well, but for better error recovery we need to break out the current loop here
			if not asStatement and expr.location.end_.x ~= token_start_line then
				reportAmbiguousCallError()
				break
			end
			expr = parseFunctionArgsImpl(expr, false)
		elseif token_type == 123 or token_type == 278 or token_type == 279 then
			expr = parseFunctionArgsImpl(expr, false)
		elseif token_type == 60 and next_type == 60 then
			expr = parseExplicitTypeInstantiationExpr(expr.location.begin, expr)
		else
			break
		end

		-- note: while the parser isn't recursive here, we're generating recursive structures of unbounded depth
		incrementRecursionCounter("expression")
	end

	recursionCounter = oldRecursion
	return expr
end

const function emptyReturnTypePack(location: Location): AstTypePackExplicit
	return {
		kind = "TypePackExplicit",
		location = location,
		types = EmptyArray :: { AstType },
		tailType = nil,
	} :: AstTypePackExplicit
end

const function parseDeclaredExternTypeMethodImpl(attributes: Attrs): AstDeclaredExternTypeProperty
	const startLine, startColumn = token_start_line, token_start_col
	const startEndLine, startEndColumn = token_end_line, token_end_col
	nextLexeme()

	local fnName, nameStartLine, nameStartColumn, nameEndLine, nameEndColumn =
		parseNameScalars("function name")
	fnName = fnName or "%error-id%"
	const fnNameLocation = {
		begin = vector.create(nameStartLine, nameStartColumn),
		end_ = vector.create(nameEndLine, nameEndColumn),
	}

	const matchParenType = token_type
	const matchParenLine, matchParenColumn = token_start_line, token_start_col
	expectAndConsume(40, "function parameter list start")

	const args = {} :: { Binding }
	local vararg = false
	local varargAnnotation = nil :: AstTypePack?

	if token_type ~= 41 then
		vararg, _, varargAnnotation = parseBindingList(args, true)
	end

	expectMatchAndConsume(41, matchParenType, matchParenLine, matchParenColumn)

	local retTypes = parseOptionalReturnTypeImpl(nil)
	if not retTypes then
		retTypes = emptyReturnTypePack(snapshot())
	end

	const methodLocation = {
		begin = vector.create(startLine, startColumn),
		end_ = vector.create(prev_end_line, prev_end_col),
	}

	if #args == 0 or args[1].name.value ~= "self" or args[1].annotation ~= nil then
		return {
			kind = "DeclaredExternTypeProperty",
			name = { value = fnName },
			nameLocation = fnNameLocation,
			type = reportTypeError(methodLocation, {}, "'self' must be present as the unannotated first parameter"),
			isMethod = true,
			location = methodLocation,
			access = "ReadWrite",
		} :: AstDeclaredExternTypeProperty
	end

	const params = {} :: { AstType }
	const paramNames = {} :: { AstArgumentName | boolean }

	for i = 2, #args do
		const arg = args[i]
		table.insert(paramNames, { name = arg.name.value, location = arg.location })

		if arg.annotation then
			table.insert(params, arg.annotation)
		else
			table.insert(
				params,
				reportTypeError(methodLocation, {}, "All declaration parameters aside from 'self' must be annotated")
			)
		end
	end

	if vararg and not varargAnnotation then
		report(
			{
				begin = vector.create(startLine, startColumn),
				end_ = vector.create(startEndLine, startEndColumn),
			},
			"All declaration parameters aside from 'self' must be annotated"
		)
	end

	const fnType = {
		kind = "TypeFunction",
		location = methodLocation,
		attributes = attributes,
		generics = EmptyArray :: { AstGenericType },
		genericPacks = EmptyArray :: { AstGenericTypePack },
		argTypes = {
			types = params,
			tailType = varargAnnotation,
		},
		argNames = paramNames,
		returnTypes = retTypes,
	} :: AstTypeFunction

	return {
		kind = "DeclaredExternTypeProperty",
		name = { value = fnName },
		nameLocation = fnNameLocation,
		type = fnType,
		isMethod = true,
		location = methodLocation,
		access = "ReadWrite",
	} :: AstDeclaredExternTypeProperty
end

-- TableIndexer ::= `[' Type `]' `:' Type
const function parseTableIndexerImpl(
	access: AstTableAccess,
	accessLoc: Location?,
	beginType: number,
	beginLine: number,
	beginColumn: number
): (AstTableIndexer, number, number, number, number)
	const index = parseTypeImpl(false)

	local indexerCloseLine, indexerCloseColumn = 0, 0
	if expectMatchAndConsume(93, beginType, beginLine, beginColumn) then
		indexerCloseLine, indexerCloseColumn = prev_start_line, prev_start_col
	end

	local colonLine, colonColumn = 0, 0
	if expectAndConsume(58, "table field") then
		colonLine, colonColumn = prev_start_line, prev_start_col
	end

	const result = parseTypeImpl(false)
	const beginPosition = vector.create(beginLine, beginColumn)

	const node = {
		kind = "TableIndexer",
		location = {
			begin = beginPosition,
			end_ = result.location.end_,
		},
		indexType = index,
		resultType = result,
		access = access,
		accessLocation = accessLoc,
	} :: AstTableIndexer

	return node, indexerCloseLine, indexerCloseColumn, colonLine, colonColumn
end

const function parseDeclarationImpl(start: Location, attributes: Attrs): AstStat
	if #attributes ~= 0 and token_type ~= 299 then
		return reportStatError(
			snapshot(),
			{},
			{},
			"Expected a function type declaration after attribute, but got %s instead",
			ToString(token_type, token_string, token_codepoint)
		)
	end

	if token_type == 299 then
		nextLexeme()

		local globalName, nameStartLine, nameStartColumn, nameEndLine, nameEndColumn =
			parseNameScalars("global function name")
		globalName = globalName or "%error-id%"
		const globalNameLocation = {
			begin = vector.create(nameStartLine, nameStartColumn),
			end_ = vector.create(nameEndLine, nameEndColumn),
		}
		const generics, genericPacks = parseGenericTypeListImpl(false)

		const matchParenType = token_type
		const matchParenLine, matchParenColumn = token_start_line, token_start_col
		expectAndConsume(40, "global function declaration")

		const args = {} :: { Binding }
		local vararg = false
		local varargLocation = nil :: Location?
		local varargAnnotation = nil :: AstTypePack?

		if token_type ~= 41 then
			vararg, varargLocation, varargAnnotation = parseBindingList(args, true)
		end

		expectMatchAndConsume(41, matchParenType, matchParenLine, matchParenColumn)

		local retTypes = parseOptionalReturnTypeImpl(nil)
		const endStartLine, endStartColumn = token_start_line, token_start_col
		const endLine, endColumn = token_end_line, token_end_col
		if not retTypes then
			retTypes = emptyReturnTypePack({
				begin = vector.create(endStartLine, endStartColumn),
				end_ = vector.create(endLine, endColumn),
			})
		end

		const params = {} :: { AstType }
		const paramNames = {} :: { AstArgumentName }
		const declLocation = {
			begin = start.begin,
			end_ = vector.create(endLine, endColumn),
		}

		for _, arg in args do
			if not arg.annotation then
				return reportStatError(declLocation, {}, {}, "All declaration parameters must be annotated")
			end

			table.insert(params, arg.annotation)
			table.insert(paramNames, { name = arg.name.value, location = arg.location })
		end

		if vararg and not varargAnnotation then
			return reportStatError(declLocation, {}, {}, "All declaration parameters must be annotated")
		end

		return {
			kind = "StatDeclareFunction",
			location = declLocation,
			attributes = attributes,
			name = globalName,
			nameLocation = globalNameLocation,
			generics = generics,
			genericPacks = genericPacks,
			params = {
				types = params,
				tailType = varargAnnotation,
			},
			paramNames = paramNames,
			vararg = vararg,
			varargLocation = varargLocation,
			retTypes = retTypes,
		} :: AstStatDeclareFunction
	elseif
		token_type == 281
		and (
			if Flags.LuauDisallowExternClassInTypeDefinitions
				then token_string == "extern"
				else (
					token_string == "extern"
					or (
						token_string == "class"
						and (if Flags.LuauAllowGlobalDeclarationToBeCalledClass then next_type ~= 58 else true)
					)
				)
		)
	then
		local foundExtern = false

		if token_string == "extern" then
			if not Flags.LuauDisallowExternClassInTypeDefinitions then
				foundExtern = true
			end

			nextLexeme()

			if token_type ~= 281 or token_string ~= "type" then
				return reportStatError(
					snapshot(),
					{},
					{},
					"Expected `type` keyword after `extern`, but got %s instead",
					ToString(token_type, token_string, token_codepoint)
				)
			end
		end

		nextLexeme()

		const typeStartLine, typeStartColumn = token_start_line, token_start_col
		local typeName = parseNameScalars("type name")
		typeName = typeName or "%error-id%"
		local superName = nil :: string?

		if token_type == 281 and token_string == "extends" then
			nextLexeme()
			superName = parseNameScalars("supertype name")
			superName = superName or "%error-id%"
		end

		if Flags.LuauDisallowExternClassInTypeDefinitions or foundExtern then
			if token_type == 281 and token_string == "with" then
				nextLexeme()
			else
				report(
					snapshot(),
					"Expected `with` keyword before listing properties of the external type, but got %s instead",
					ToString(token_type, token_string, token_codepoint)
				)
			end
		end

		const props = {} :: { AstDeclaredExternTypeProperty }
		local indexer = nil :: AstTableIndexer?

		while token_type ~= 296 and token_type ~= 0 do
			local methodAttributes = {} :: Attrs

			if token_type == 284 or token_type == 285 then
				methodAttributes = parseAttributes()

				if token_type ~= 299 then
					return reportStatError(
						snapshot(),
						{},
						{},
						"Expected a method type declaration after attribute, but got %s instead",
						ToString(token_type, token_string, token_codepoint)
					)
				end
			end

			if token_type == 299 then
				table.insert(props, parseDeclaredExternTypeMethodImpl(methodAttributes))
			elseif token_type == 91 then
				const beginType = token_type
				const beginLine, beginColumn = token_start_line, token_start_col
				const beginEndLine, beginEndColumn = token_end_line, token_end_col
				nextLexeme()

				if (token_type == 278 or token_type == 279) and next_type == 93 then
					const beginLocation = {
						begin = vector.create(beginLine, beginColumn),
						end_ = vector.create(beginEndLine, beginEndColumn),
					}
					const nameLocation = snapshot()
					const chars = parseCharArrayImpl()
					const nameEnd = getprev()

					expectMatchAndConsume(93, beginType, beginLine, beginColumn)
					expectAndConsume(58, "property type annotation")
					const propType = parseTypeImpl(true)

					if chars and string.find(chars, "\0", 1, true) == nil then
						table.insert(
							props,
							{
								kind = "DeclaredExternTypeProperty",
								name = { value = chars },
								nameLocation = { begin = nameLocation.begin, end_ = nameEnd.end_ },
								type = propType,
								isMethod = false,
								location = { begin = beginLocation.begin, end_ = propType.location.end_ },
								access = "ReadWrite",
							} :: AstDeclaredExternTypeProperty
						)
					else
						report(beginLocation, "String literal contains malformed escape sequence or \\0")
					end
				elseif indexer then
					const badIndexer = parseTableIndexerImpl("ReadWrite", nil, beginType, beginLine, beginColumn)
					report(badIndexer.location, "Cannot have more than one indexer on an extern type")
				else
					indexer = parseTableIndexerImpl("ReadWrite", nil, beginType, beginLine, beginColumn)
				end
			else
				local access: AstTableAccess = "ReadWrite"
				local accessLocation = nil :: Location?

				if token_type == 281 and next_type ~= 58 then
					if token_string == "read" then
						access = "Read"
						accessLocation = snapshot()
						nextLexeme()
					elseif token_string == "write" then
						access = "Write"
						accessLocation = snapshot()
						nextLexeme()
					else
						report(snapshot(), "Expected blank or 'read' or 'write' attribute, got '%s'", token_string or "")
						nextLexeme()
					end
				end

				const propStart = snapshot()
				const propName = parseNameOptImpl("property name")
				if not propName then
					break
				end

				expectAndConsume(58, "property type annotation")
				const propType = parseTypeImpl(true)

				table.insert(
					props,
					{
						kind = "DeclaredExternTypeProperty",
						name = propName.name,
						nameLocation = propName.location,
						type = propType,
						isMethod = false,
						location = { begin = propStart.begin, end_ = propType.location.end_ },
						access = access,
					} :: AstDeclaredExternTypeProperty
				)

				if accessLocation then
					props[#props].location.begin = accessLocation.begin
				end
			end

			if token_type == 44 or token_type == 59 then
				nextLexeme()
			end
		end

		const typeEndLine, typeEndColumn = token_end_line, token_end_col
		expectAndConsume(296, "extern type")

		return {
			kind = "StatDeclareExternType",
			location = {
				begin = vector.create(typeStartLine, typeStartColumn),
				end_ = vector.create(typeEndLine, typeEndColumn),
			},
			name = typeName,
			superName = superName,
			props = props,
			indexer = indexer,
		} :: AstStatDeclareExternType
	end

	const globalName = parseNameOptImpl("global variable name")
	if globalName then
		expectAndConsume(58, "global variable declaration")
		const type_ = parseTypeImpl(true)

		return {
			kind = "StatDeclareGlobal",
			location = { begin = start.begin, end_ = type_.location.end_ },
			name = globalName.name.value,
			nameLocation = globalName.location,
			type = type_,
		} :: AstStatDeclareGlobal
	end

	return reportStatError(start, {}, {}, "declare must be followed by an identifier, 'function', or 'extern type'")
end

-- attributes local function Name funcbody
-- attributes function funcname funcbody
-- attributes `declare function' Name`(' [parlist] `)' [`:` Type]
-- declare Name '{' Name ':' attributes `(' [parlist] `)' [`:` Type] '}'
const function parseAttributeStatImpl(): AstStat
	const attributes, attributeStartLocation, cstAttrLists = parseAttributes()
	const type_ = token_type

	if type_ == 299 then
		return parseFunctionStatImpl(attributes, attributeStartLocation, cstAttrLists)
	elseif type_ == 302 then
		const keywordLocation = snapshot()
		return parseLocalImpl(
			attributeStartLocation or keywordLocation,
			keywordLocation.begin,
			attributes,
			cstAttrLists,
			false
		)
	elseif type_ == 281 and token_string == "const" then
		const keywordLocation = snapshot()
		nextLexeme()
		return parseLocalImpl(
			attributeStartLocation or keywordLocation,
			keywordLocation.begin,
			attributes,
			cstAttrLists,
			true
		)
	elseif Flags.LuauExportValueSyntax and type_ == 281 and token_string == "export" then
		const keywordLocation = snapshot()
		nextLexeme()
		return parseExportValueImpl(
			attributeStartLocation or keywordLocation,
			keywordLocation.begin,
			attributes,
			cstAttrLists
		)
	elseif options.allowDeclarationSyntax and type_ == 281 and token_string == "declare" then
		const expr = parsePrimaryExprImpl(true)
		return parseDeclarationImpl(expr.location, attributes)
	end

	return reportStatError(
		snapshot(),
		{},
		{},
		"Expected 'function', 'local function', 'const function', 'declare function' or a function type declaration after attribute, but got %s instead",
		ToString(token_type, token_string, token_codepoint)
	)
end

-- return [explist]
const function parseReturnImpl(): AstStatReturn
	const startLine, startColumn = token_start_line, token_start_col
	const startEndLine, startEndColumn = token_end_line, token_end_col
	nextLexeme()

	const list: { AstExpr } = {}
	const commaPositions: { Position }? = if storeCstData then {} else nil

	if not BlockFollow[token_type] and token_type ~= 59 then
		parseExprListImpl(list, commaPositions)
	end

	local end_: Position = vector.create(startEndLine, startEndColumn)
	if #list > 0 then
		end_ = list[#list].location.end_
	end

	const node = {
		kind = "StatReturn",
		location = {
			begin = vector.create(startLine, startColumn),
			end_ = end_,
		},
		list = list,
	} :: AstStatReturn

	if commaPositions then
		node.cstNode = {
			kind = "CstStatReturn",
			commaPositions = commaPositions,
		}
	end

	if Flags.LuauExportValueSyntax and #functionStack == 1 then
		if next(declaredExportBindings) then
			report(node.location, "Exporting values is not compatible with top-level return (export/return conflict)")
		end
		hasModuleReturn = true
	end

	return node
end

-- type function Name `(' arglist `)' `=' funcbody `end'
const function parseTypeFunctionImpl(
	start: Location,
	exported: boolean,
	typeKeywordLine: number,
	typeKeywordColumn: number
): AstStatTypeFunction
	const matchFunctionType = token_type
	const matchFunctionLine, matchFunctionColumn = token_start_line, token_start_col
	const matchFunctionEndLine, matchFunctionEndColumn = token_end_line, token_end_col
	nextLexeme()

	const errorsAtStart = #parseErrors

	-- parse the name of the type function
	const fnNameOpt = parseNameOptImpl("type function name")
	local fnName = fnNameOpt :: Binding

	if fnName == nil then
		fnName = {
			name = { value = "%error-id%" },
			location = snapshot(),
		} :: Binding
	end

	matchRecovery[296] += 1

	const oldTypeFunctionDepth = typeFunctionDepth
	typeFunctionDepth = #functionStack

	const body = parseFunctionBodyImpl(
		false,
		matchFunctionType,
		matchFunctionLine,
		matchFunctionColumn,
		matchFunctionEndLine,
		matchFunctionEndColumn,
		fnName.name.value,
		nil,
		nil,
		{},
		nil,
		false
	)

	typeFunctionDepth = oldTypeFunctionDepth
	matchRecovery[296] -= 1

	const hasErrors = #parseErrors > errorsAtStart

	const node = {
		kind = "StatTypeFunction",
		location = {
			begin = start.begin,
			end_ = body.location.end_,
		},
		name = fnName.name.value,
		nameLocation = fnName.location,
		body = body,
		exported = exported,
		hasErrors = hasErrors,
	} :: AstStatTypeFunction

	if storeCstData then
		node.cstNode = {
			kind = "CstStatTypeFunction",
			typeKeywordPosition = vector.create(typeKeywordLine, typeKeywordColumn),
			functionKeywordPosition = vector.create(matchFunctionLine, matchFunctionColumn),
		}
	end

	return node
end

-- type Name [`<' varlist `>'] `=' Type
const function parseTypeAliasImpl(
	start: Location,
	exported: boolean,
	typeKeywordLine: number,
	typeKeywordColumn: number
): AstStatTypeAlias | AstStatTypeFunction
	-- parsing a type function
	if token_type == 299 then
		return parseTypeFunctionImpl(start, exported, typeKeywordLine, typeKeywordColumn)
	end

	-- parsing a type alias

	-- note: `type` token is already parsed for us, so we just need to parse the rest

	const nameOpt = parseNameOptImpl("type name")
	local name = nameOpt :: Binding

	-- Use error name if the name is missing
	if not name then
		name = {
			name = { value = "%error-id%" },
			location = snapshot(),
		} :: Binding
	end

	const genericsCommaPos: { Position }? = if storeCstData then {} else nil
	const genericsClosePos: { Position }? = if storeCstData then { vector.create(0, 0) } else nil
	const genericsOpenPos: { Position }? = if storeCstData then { vector.create(0, 0) } else nil

	const generics, genericPacks =
		parseGenericTypeListImpl(true, genericsOpenPos, genericsCommaPos, genericsClosePos)

	local equalsPosition: Position? = if storeCstData then vector.create(0, 0) else nil
	if expectAndConsume(61, "type alias") then
		if equalsPosition then
			equalsPosition = vector.create(prev_start_line, prev_start_col)
		end
	end

	const type_ = parseTypeImpl()

	const node = {
		kind = "StatTypeAlias",
		location = { begin = start.begin, end_ = type_.location.end_ },
		name = name.name.value,
		nameLocation = name.location,
		generics = generics,
		genericPacks = genericPacks,
		type = type_,
		exported = exported,
	} :: AstStatTypeAlias

	if genericsOpenPos and genericsCommaPos and genericsClosePos and equalsPosition then
		node.cstNode = {
			kind = "CstStatTypeAlias",
			typeKeywordPosition = vector.create(typeKeywordLine, typeKeywordColumn),
			genericsOpenPosition = genericsOpenPos[1],
			genericsCommaPositions = genericsCommaPos,
			genericsClosePosition = genericsClosePos[1],
			equalsPosition = equalsPosition,
		}
	end

	return node
end

-- varlist `=' explist
const function parseAssignmentImpl(initial: AstExpr): AstStatAssign
	if not isExprLValue(initial) then
		initial = if Flags.LuauExportValueSyntax
			then reportLValueError(initial)
			else reportExprError(initial.location, { initial }, "Assigned expression must be a variable or a field")
	end

	const vars: { AstExpr } = { initial }
	const varsCommaPositions: { Position }? = if storeCstData then {} else nil

	while token_type == 44 do
		if varsCommaPositions then
			table.insert(varsCommaPositions, vector.create(token_start_line, token_start_col))
		end
		nextLexeme()

		local expr = parsePrimaryExprImpl(true)
		if not isExprLValue(expr) then
			expr = if Flags.LuauExportValueSyntax
				then reportLValueError(expr)
				else reportExprError(expr.location, { expr }, "Assigned expression must be a variable or a field")
		end
		table.insert(vars, expr)
	end

	local equalsLine, equalsColumn = 0, 0
	if expectAndConsume(61, "assignment") then
		equalsLine, equalsColumn = prev_start_line, prev_start_col
	end

	const values: { AstExpr } = {}
	const valuesCommaPositions: { Position }? = if storeCstData then {} else nil
	parseExprListImpl(values, valuesCommaPositions)

	const end_ = values[#values].location

	const node = {
		kind = "StatAssign",
		location = { begin = initial.location.begin, end_ = end_.end_ },
		vars = vars,
		values = values,
	} :: AstStatAssign

	if varsCommaPositions and valuesCommaPositions then
		node.cstNode = {
			kind = "CstStatAssign",
			varsCommaPositions = varsCommaPositions,
			equalsPosition = vector.create(equalsLine, equalsColumn),
			valuesCommaPositions = valuesCommaPositions,
		}
	end

	return node
end

-- var [`+=' | `-=' | `*=' | `/=' | `%=' | `^=' | `..='] exp
const function parseCompoundAssignmentImpl(initial: AstExpr, op: number): AstStatCompoundAssign
	if not isExprLValue(initial) then
		initial = if Flags.LuauExportValueSyntax
			then reportLValueError(initial)
			else reportExprError(initial.location, { initial }, "Assigned expression must be a variable or a field")
	end

	const opLine, opColumn = token_start_line, token_start_col
	nextLexeme()

	const value = ParserFunctions.parseExpr()

	const node = {
		kind = "StatCompoundAssign",
		location = { begin = initial.location.begin, end_ = value.location.end_ },
		op = op,
		var = initial,
		value = value,
	} :: AstStatCompoundAssign

	if storeCstData then
		node.cstNode = {
			kind = "CstStatCompoundAssign",
			opPosition = vector.create(opLine, opColumn),
		}
	end

	return node
end

-- TypeList ::= Type [`,' TypeList] | ...Type
const function parseTypeListImpl(
	result: { AstType },
	resultNames: { AstArgumentName | boolean },
	commaPositions: { Position }?,
	nameColonPositions: { Position | boolean }?
): AstTypePack?
	while true do
		if shouldParseTypePack() then
			return parseTypePackImpl()
		end

		if token_type == 281 and next_type == 58 then
			-- Fill in previous argument names with empty slots
			while #resultNames < #result do
				table.insert(resultNames, false)
				if nameColonPositions then
					table.insert(nameColonPositions, false)
				end
			end

			const name = {
				name = token_string :: string,
				location = snapshot(),
			}

			table.insert(resultNames, name)
			nextLexeme()

			if nameColonPositions then
				table.insert(nameColonPositions, vector.create(token_start_line, token_start_col))
			end

			expectAndConsume(58)
		elseif #resultNames > 0 then
			-- If we have a type with named arguments, provide elements for all types
			table.insert(resultNames, false)
			if nameColonPositions then
				table.insert(nameColonPositions, false)
			end
		end

		table.insert(result, parseTypeImpl(false))

		if token_type ~= 44 then
			break
		end

		if commaPositions then
			table.insert(commaPositions, vector.create(token_start_line, token_start_col))
		end
		nextLexeme()

		if token_type == 41 then
			report(snapshot(), "Expected type after ',' but got ')' instead")

			break
		end
	end
	return nil
end

-- TableProp ::= Name `:' Type
-- TablePropOrIndexer ::= TableProp | TableIndexer
-- PropList ::= TablePropOrIndexer {fieldsep TablePropOrIndexer} [fieldsep]
-- TableType ::= `{' PropList `}'
const function parseTableTypeImpl(inDeclarationContext: boolean): AstTypeTable
	incrementRecursionCounter("type annotation")

	const props: { AstTableProp } = {}
	const cstItems: { CstTypeTableItem }? = if storeCstData then {} else nil
	local indexer: AstTableIndexer? = nil

	const startLine, startColumn = token_start_line, token_start_col
	const matchBraceType = token_type
	const matchBraceLine, matchBraceColumn = token_start_line, token_start_col
	expectAndConsume(123, "table type")

	local isArray = false

	while token_type ~= 125 do
		local access: AstTableAccess = "ReadWrite"
		local accessLoc: Location? = nil

		if token_type == 281 and next_type ~= 58 then
			if token_string == "read" then
				accessLoc = snapshot()
				access = "Read"
				nextLexeme()
			elseif token_string == "write" then
				accessLoc = snapshot()
				access = "Write"
				nextLexeme()
			end
		end

		if token_type == 91 then
			const beginType = token_type
			const beginLine, beginColumn = token_start_line, token_start_col
			const beginEndLine, beginEndColumn = token_end_line, token_end_col
			nextLexeme()

			if (token_type == 278 or token_type == 279) and next_type == 93 then
				const beginLocation = {
					begin = vector.create(beginLine, beginColumn),
					end_ = vector.create(beginEndLine, beginEndColumn),
				}
				local style = 0
				local depth = 0
				if storeCstData then
					style, depth = extractStringDetails()
				end

				const stringLine, stringColumn = token_start_line, token_start_col
				local sourceString: string? = nil
				if storeCstData then
					sourceString = token_string
				end

				const chars = parseCharArrayImpl()

				local indexerCloseLine, indexerCloseColumn = 0, 0
				if expectMatchAndConsume(93, beginType, beginLine, beginColumn) then
					indexerCloseLine, indexerCloseColumn = prev_start_line, prev_start_col
				end

				local colonLine, colonColumn = 0, 0
				if expectAndConsume(58, "table field") then
					colonLine, colonColumn = prev_start_line, prev_start_col
				end

				const type_ = parseTypeImpl()

				if chars and string.find(chars, "\0", 1, true) == nil then
					table.insert(
						props,
						{
							kind = "TableProp",
							name = { value = chars },
							location = beginLocation,
							type = type_,
							access = access,
							accessLocation = accessLoc,
						} :: AstTableProp
					)

					if cstItems then
						const separator = tableSeparator()
						const cstString = {
							kind = "CstExprConstantString",
							sourceString = sourceString,
							quoteStyle = style,
							blockDepth = depth,
						}

						table.insert(
							cstItems,
							{
								kind = "StringProperty",
								indexerOpenPosition = beginLocation.begin,
								indexerClosePosition = vector.create(indexerCloseLine, indexerCloseColumn),
								colonPosition = vector.create(colonLine, colonColumn),
								separator = separator,
								separatorPosition = cstSeparatorPosition(separator),
								stringInfo = cstString,
								stringPosition = vector.create(stringLine, stringColumn),
							} :: CstTypeTableItem
						)
					end
				else
					report(beginLocation, "String literal contains malformed escape sequence or \\0")
				end
			else
				if indexer then
					const badIndexerRes = parseTableIndexerImpl(access, accessLoc, beginType, beginLine, beginColumn)
					report(badIndexerRes.location, "Cannot have more than one table indexer")
				else
					const idxNode, indexerCloseLine, indexerCloseColumn, colonLine, colonColumn =
						parseTableIndexerImpl(access, accessLoc, beginType, beginLine, beginColumn)
					indexer = idxNode

					if cstItems then
						const separator = tableSeparator()
						table.insert(
							cstItems,
							{
								kind = "Indexer",

								indexerOpenPosition = vector.create(beginLine, beginColumn),
								indexerClosePosition = vector.create(indexerCloseLine, indexerCloseColumn),
								colonPosition = vector.create(colonLine, colonColumn),
								separator = separator,
								separatorPosition = cstSeparatorPosition(separator),
							} :: CstTypeTableItem
						)
					end
				end
			end
		elseif #props == 0 and not indexer and not (token_type == 281 and next_type == 58) then
			const type_ = parseTypeImpl()
			isArray = true

			-- array-like table type: {T} desugars into {[number]: T}
			const index = {
				kind = "TypeReference",
				location = type_.location,
				name = "number",
				nameLocation = type_.location,
				hasParameterList = false,
				parameters = EmptyArray :: { AstTypeOrPack },
			} :: AstTypeReference

			indexer = {
				kind = "TableIndexer",
				location = type_.location,
				indexType = index,
				resultType = type_,
				access = access,
				accessLocation = accessLoc,
			} :: AstTableIndexer
			break
		else
			const nameOpt = parseNameOptImpl("table field")
			if not nameOpt then
				break
			end

			local colonLine, colonColumn = 0, 0
			if expectAndConsume(58, "table field") then
				colonLine, colonColumn = prev_start_line, prev_start_col
			end

			const type_ = parseTypeImpl(inDeclarationContext)

			table.insert(
				props,
				{
					kind = "TableProp",
					name = nameOpt.name,
					location = nameOpt.location,
					type = type_,
					access = access,
					accessLocation = accessLoc,
				} :: AstTableProp
			)

			if cstItems then
				const separator = tableSeparator()
				table.insert(
					cstItems,
					{
						kind = "Property",
						colonPosition = vector.create(colonLine, colonColumn),
						separator = separator,
						separatorPosition = cstSeparatorPosition(separator),
					} :: CstTypeTableItem
				)
			end
		end

		if token_type == 44 or token_type == 59 then
			nextLexeme()
		elseif token_type ~= 125 then
			break
		end
	end

	local endLine, endColumn = token_end_line, token_end_col
	if
		not expectMatchAndConsume(
			125,
			matchBraceType,
			matchBraceLine,
			matchBraceColumn,
			true
		)
	then
		endLine, endColumn = prev_end_line, prev_end_col
	end

	const node = {
		kind = "TypeTable",
		location = {
			begin = vector.create(startLine, startColumn),
			end_ = vector.create(endLine, endColumn),
		},
		props = props,
		indexer = indexer,
	} :: AstTypeTable

	if cstItems then
		node.cstNode = {
			kind = "CstTypeTable",
			items = cstItems,
			isArray = isArray,
		}
	end

	return node
end

const function parseFunctionTypeTailImpl(
	beginType: number,
	beginLocation: Location,
	attributes: Attrs,
	generics: { AstGenericType },
	genericPacks: { AstGenericTypePack },
	params: { AstType },
	paramNames: { AstArgumentName | boolean },
	varargAnnotation: AstTypePack?
): AstType
	incrementRecursionCounter("type annotation")

	if token_type == 58 then
		report(snapshot(), "Return types in function type annotations are written after '->' instead of ':'")

		nextLexeme()

		-- Users occasionally write '()' as the 'unit' type when they actually want to use 'nil', here we'll try to give a more specific error
	elseif token_type ~= 263 and #generics == 0 and #genericPacks == 0 and #params == 0 then
		report({
			begin = beginLocation.begin,
			end_ = vector.create(prev_end_line, prev_end_col),
		}, "Expected '->' after '()' when parsing function type; did you mean 'nil'?")

		return {
			kind = "TypeReference",
			location = beginLocation,
			name = "nil",
			nameLocation = beginLocation,
			hasParameterList = false,
			parameters = EmptyArray :: { AstTypeOrPack },
		} :: AstTypeReference
	else
		expectAndConsume(263, "function type")
	end

	const returnType = ParserFunctions.parseReturnType()

	return {
		kind = "TypeFunction",
		location = {
			begin = beginLocation.begin,
			end_ = returnType.location.end_,
		},
		attributes = attributes,
		generics = generics,
		genericPacks = genericPacks,
		argTypes = {
			types = params,
			tailType = varargAnnotation,
		},
		argNames = paramNames,
		returnTypes = returnType,
	}
end

-- ReturnType ::= Type | `(' TypeList `)'
-- FunctionType ::= [`<' varlist `>'] `(' [TypeList] `)' `->` ReturnType
const function parseFunctionTypeImpl(
allowPack: boolean, attributes: Attrs
): (AstType?, AstTypePack?)
	incrementRecursionCounter("type annotation")

	local forceFunctionType = (token_type == 60)
	const beginType = token_type
	const beginLocation = {
		begin = vector.create(token_start_line, token_start_col),
		end_ = vector.create(token_end_line, token_end_col),
	}

	const openGenPos: { Position }? = if storeCstData then { vector.create(0, 0) } else nil
	const genCommaPos: { Position }? = if storeCstData then {} else nil
	const closeGenPos: { Position }? = if storeCstData then { vector.create(0, 0) } else nil

	const generics, genericPacks = parseGenericTypeListImpl(false, openGenPos, genCommaPos, closeGenPos)

	const paramStartType = token_type
	const paramStartLine, paramStartColumn = token_start_line, token_start_col
	const openArgsFound = expectAndConsume(40, "function parameters")
	const openArgsPosition = if storeCstData
		then if openArgsFound
			then vector.create(paramStartLine, paramStartColumn)
			else vector.create(0, 0)
		else nil

	matchRecovery[263] += 1

	local params = EmptyArray :: { AstType }
	local names = EmptyArray :: { AstArgumentName | boolean }
	const argCommaPos: { Position }? = if storeCstData then {} else nil
	const nameColonPos: { Position | boolean }? = if storeCstData then {} else nil

	local varargAnnotation: AstTypePack? = nil

	if token_type ~= 41 then
		params = {}
		names = {}
		varargAnnotation = parseTypeListImpl(params, names, argCommaPos, nameColonPos)
	end

	const closeArgsStartLine, closeArgsStartColumn = token_start_line, token_start_col
	const closeArgsEndLine, closeArgsEndColumn = token_end_line, token_end_col
	local closeArgsPosition: Position? = if storeCstData then vector.create(0, 0) else nil
	if expectMatchAndConsume(41, paramStartType, paramStartLine, paramStartColumn, true) then
		if closeArgsPosition then
			closeArgsPosition = vector.create(closeArgsStartLine, closeArgsStartColumn)
		end
	end

	matchRecovery[263] -= 1

	const paramTypes = params
	if #names > 0 then
		forceFunctionType = true
	end

	const returnTypeIntroducer = (token_type == 263 or token_type == 58)

	-- ot a function at all. Just a parenthesized type. Or maybe a type pack with a single element
	if #params == 1 and not varargAnnotation and not forceFunctionType and not returnTypeIntroducer then
		if allowPack then
			const node = {
				kind = "TypePackExplicit",
				location = beginLocation,
				types = paramTypes,
			} :: AstTypePackExplicit

			if argCommaPos and openArgsPosition and closeArgsPosition then
				node.cstNode = {
					kind = "CstTypePackExplicit",
					openParenthesesPosition = openArgsPosition,
					closeParenthesesPosition = closeArgsPosition,
					commaPositions = argCommaPos,
				}
			end

			return nil, node
		else
			const node = {
				kind = "TypeGroup",
				location = {
					begin = vector.create(paramStartLine, paramStartColumn),
					end_ = vector.create(closeArgsEndLine, closeArgsEndColumn),
				},
				type = params[1],
			} :: AstTypeGroup

			if closeArgsPosition then
				node.cstNode = {
					kind = "CstTypeGroup",
					closePosition = closeArgsPosition,
				}
			end

			return node, nil
		end
	end

	if not forceFunctionType and not returnTypeIntroducer and allowPack then
		const node = {
			kind = "TypePackExplicit",
			location = beginLocation,
			types = paramTypes,
			tailType = varargAnnotation,
		} :: AstTypePackExplicit

		if argCommaPos and openArgsPosition and closeArgsPosition then
			node.cstNode = {
				kind = "CstTypePackExplicit",
				openParenthesesPosition = openArgsPosition,
				closeParenthesesPosition = closeArgsPosition,
				commaPositions = argCommaPos,
			}
		end

		return nil, node
	end

	const returnArrowPosition =
		if storeCstData then vector.create(token_start_line, token_start_col) else nil
	const node = parseFunctionTypeTailImpl(
		beginType,
		beginLocation,
		attributes,
		generics,
		genericPacks,
		paramTypes,
		names,
		varargAnnotation
	)

	if
		openGenPos
		and genCommaPos
		and closeGenPos
		and nameColonPos
		and argCommaPos
		and openArgsPosition
		and closeArgsPosition
		and returnArrowPosition
		and node.kind == "TypeFunction"
	then
		node.cstNode = {
			kind = "CstTypeFunction",
			openGenericsPosition = openGenPos[1],
			genericsCommaPositions = genCommaPos,
			closeGenericsPosition = closeGenPos[1],
			openArgsPosition = openArgsPosition,
			argumentNameColonPositions = nameColonPos,
			argumentsCommaPositions = argCommaPos,
			closeArgsPosition = closeArgsPosition,
			returnArrowPosition = returnArrowPosition,
		}
	end

	return node, nil
end

const function checkUnaryConfusables(): number?
	-- early-out: need to check if this is a possible confusable quickly
	if token_type ~= 33 then
		return nil
	end

	report(snapshot(), "Unexpected '!'; did you mean 'not'?")

	return 0 -- UnaryOp.Not
end

const function checkBinaryConfusables(limit: number): number?
	const currentType = token_type

	-- arly-out: need to check if this is a possible confusable quickly
	if currentType ~= 38 and currentType ~= 124 and currentType ~= 33 then
		return nil
	end

	-- slow path: possible confusable
	const startLine, startColumn = token_start_line, token_start_col
	const endLine, endColumn = token_end_line, token_end_col

	if
		currentType == 38
		and next_type == 38
		and endLine == next_start_line
		and endColumn == next_start_col
		and BinaryPriority[BinaryOp.And][1] > limit
	then
		nextLexeme()

		report({
			begin = vector.create(startLine, startColumn),
			end_ = vector.create(token_end_line, token_end_col),
		}, "Unexpected '&&'; did you mean 'and'?")

		return BinaryOp.And
	elseif
		currentType == 124
		and next_type == 124
		and endLine == next_start_line
		and endColumn == next_start_col
		and BinaryPriority[BinaryOp.Or][1] > limit
	then
		nextLexeme()

		report({
			begin = vector.create(startLine, startColumn),
			end_ = vector.create(token_end_line, token_end_col),
		}, "Unexpected '||'; did you mean 'or'?")

		return BinaryOp.Or
	elseif
		currentType == 33
		and next_type == 61
		and endLine == next_start_line
		and endColumn == next_start_col
		and BinaryPriority[BinaryOp.CompareNe][1] > limit
	then
		nextLexeme()

		report({
			begin = vector.create(startLine, startColumn),
			end_ = vector.create(token_end_line, token_end_col),
		}, "Unexpected '!='; did you mean '~='?")

		return BinaryOp.CompareNe
	end

	return nil
end

const function digitValue(ch: number): number?
	if ch >= 48 and ch <= 57 then
		return ch - 48
	elseif ch >= 65 and ch <= 70 then
		return ch - 55
	elseif ch >= 97 and ch <= 102 then
		return ch - 87
	end

	return nil
end

type NumberParseResult = "Ok" | "Imprecise" | "HexOverflow" | "BinOverflow" | "IntOverflow" | "Malformed"

const ParseResultOk: NumberParseResult = "Ok"
const ParseResultImprecise: NumberParseResult = "Imprecise"
const ParseResultHexOverflow: NumberParseResult = "HexOverflow"
const ParseResultBinOverflow: NumberParseResult = "BinOverflow"
const ParseResultIntOverflow: NumberParseResult = "IntOverflow"
const ParseResultMalformed: NumberParseResult = "Malformed"

const function parseInteger64Words(data: string, base: number, allowFullUint64: boolean): (number, number, NumberParseResult)
	local low = 0
	local high = 0

	if #data == 0 then
		return 0, 0, ParseResultMalformed
	end

	for i = 1, #data do
		const ch = string.byte(data, i)
		const digit = digitValue(ch)
		if digit == nil or digit >= base then
			return 0, 0, ParseResultMalformed
		end

		if base == 2 then
			const lowCarry = bit32.rshift(low, 31)
			low = bit32.band(low * 2 + digit, 0xFFFFFFFF)

			if bit32.rshift(high, 31) ~= 0 then
				return 0, 0, ParseResultBinOverflow
			end

			high = bit32.band(high * 2 + lowCarry, 0xFFFFFFFF)
		else
			const lowCarry = bit32.rshift(low, 28)
			low = bit32.band(low * 16 + digit, 0xFFFFFFFF)

			if bit32.rshift(high, 28) ~= 0 then
				return 0, 0, ParseResultHexOverflow
			end

			high = bit32.band(high * 16 + lowCarry, 0xFFFFFFFF)
		end
	end

	if not allowFullUint64 and (high > 2147483647 or (high == 2147483647 and low > 4294967295)) then
		return 0, 0, ParseResultIntOverflow
	end

	return low, high, ParseResultOk
end

const function makeNumberNode(
	location: Location,
	value: number,
	parseResult: NumberParseResult,
	sourceData: string?
): AstExprConstantNumber
	const node: AstExprConstantNumber = {
		kind = "ExprConstantNumber",
		location = location,
		value = value,
		parseResult = parseResult,
	}

	if storeCstData then
		node.cstNode = { kind = "CstExprConstantNumber", value = sourceData }
	end

	return node
end

const function parseNumberImpl(): AstExprConstantNumber | AstExprConstantInteger | AstExprError
	const start = snapshot()
	const data = token_string or ""

	local sourceData: string? = nil
	if storeCstData then
		sourceData = data
	end

	-- Remove internal '_'
	const cleanData = string.gsub(data, "_", "")

	if Flags.LuauIntegerType2 and string.sub(cleanData, -1) == "i" then
		const integerData = string.sub(cleanData, 1, -2)
		local low = 0
		local high = 0
		local parseResult: NumberParseResult = ParseResultOk

		if string.find(integerData, "^0[xX]") then
			low, high, parseResult = parseInteger64Words(string.sub(integerData, 3), 16, true)
		elseif string.find(integerData, "^0[bB]") then
			low, high, parseResult = parseInteger64Words(string.sub(integerData, 3), 2, true)
		else
			low, high, parseResult = parseInteger64Words(integerData, 10, false)
		end

		nextLexeme()

		if parseResult == ParseResultMalformed then
			return reportExprError(start, {}, "Malformed integer")
		end

		if parseResult ~= ParseResultOk then
			return reportExprError(start, {}, "Integer overflow")
		end

		const node = {
			kind = "ExprConstantInteger",
			location = start,
			low = low,
			high = high,
			parseResult = parseResult,
		} :: AstExprConstantInteger

		if storeCstData then
			node.cstNode = { kind = "CstExprConstantInteger", value = sourceData }
		end

		return node
	end

	local value = 0
	local parseResult: NumberParseResult = ParseResultOk

	-- Hexadecimal check (0x...)
	if string.find(cleanData, "^0[xX]") then
		const content = string.sub(cleanData, 3)
		const significant = string.match(content, "^0*(.+)") or "0"

		-- 16 Hex digits * 4 bits = 64 bits. Anything more is overflow for uint64.
		if #significant > 16 then
			parseResult = ParseResultHexOverflow
			value = 0
		else
			const v = tonumber(cleanData)
			if v then
				value = v
				if significant ~= "0" then
					const firstNibble = HexVal[string.byte(significant, 1)]
					if firstNibble then
						const headBits = if firstNibble >= 8
							then 4
							elseif firstNibble >= 4 then 3
							elseif firstNibble >= 2 then 2
							else 1
						const bitLength = (#significant - 1) * 4 + headBits

						if bitLength > 53 then
							const requiredTrailingZeros = bitLength - 53
							local trailingZeros = 0

							for i = #significant, 1, -1 do
								const nibble = HexVal[string.byte(significant, i)]
								if nibble == nil then
									trailingZeros = -1
									break
								end

								if nibble == 0 then
									trailingZeros += 4
								else
									trailingZeros += nibble == 0 and 32 or 31 - bit32.countlz(
										bit32.band(nibble, -nibble)
									)
									break
								end
							end

							if trailingZeros < requiredTrailingZeros then
								parseResult = ParseResultImprecise
							end
						end
					else
						parseResult = ParseResultImprecise
					end
				end
			else
				parseResult = ParseResultMalformed
				value = 0
			end
		end
	elseif string.find(cleanData, "^0[bB][01]+") then
		const content = string.sub(cleanData, 3)
		const significant = string.match(content, "^0*(.+)") or "0"

		-- Some runtimes accept a second binary prefix when parsing base 2.
		-- The lexer already consumed the first one, so reject it explicitly.
		if Flags.LuauNoDuplicateBinaryPrefix and string.find(content, "^0[bB]") then
			parseResult = ParseResultMalformed
			value = 0
		-- 64 bits max for uint64
		elseif #significant > 64 then
			parseResult = ParseResultBinOverflow
			value = 0
		else
			const v = tonumber(content, 2)
			if v then
				value = v
				const bitLength = #significant

				if bitLength > 53 then
					const requiredTrailingZeros = bitLength - 53
					local precise = true

					for i = bitLength, bitLength - requiredTrailingZeros + 1, -1 do
						if string.byte(significant, i) ~= 48 then -- '0'
							precise = false
							break
						end
					end

					if not precise then
						parseResult = ParseResultImprecise
					end
				end
			else
				parseResult = ParseResultMalformed
				value = 0
			end
		end
	else
		const v = tonumber(cleanData)
		value = v or 0

		if v then
			if value >= 9007199254740992 and string.find(cleanData, "^%d+$") then
				const repr = string.format("%.0f", value)
				if repr ~= cleanData then
					parseResult = ParseResultImprecise
				end
			end
		else
			parseResult = ParseResultMalformed
			value = 0
		end
	end

	nextLexeme()

	if parseResult == ParseResultMalformed then
		return reportExprError(start, {}, "Malformed number")
	end

	return makeNumberNode(start, value, parseResult, sourceData)
end

const function parseInterpStringImpl(): AstExprInterpString | AstExprError
	const strings: { string } = {}
	const sourceStrings: { string }? = if storeCstData then {} else nil
	const stringPositions: { Position }? = if storeCstData then {} else nil
	const expressions: { AstExpr } = {}

	const startLine, startColumn = token_start_line, token_start_col
	local endLine, endColumn = token_end_line, token_end_col

	while true do
		const currentType = token_type
		const currentStartLine, currentStartColumn = token_start_line, token_start_col
		endLine, endColumn = token_end_line, token_end_col

		const data = token_string or ""

		if sourceStrings and stringPositions then
			table.insert(sourceStrings, data)
			table.insert(stringPositions, vector.create(currentStartLine, currentStartColumn))
		end

		const ok, fixedData = fixupQuotedString(data)
		if not ok then
			nextLexeme()
			return reportExprError(
				{
					begin = vector.create(startLine, startColumn),
					end_ = vector.create(endLine, endColumn),
				},
				{},
				"Interpolated string literal contains malformed escape sequence"
			)
		end

		nextLexeme()
		table.insert(strings, fixedData :: string)

		if currentType == 268 or currentType == 269 then
			break
		end

		local errorWhileChecking = false
		local t = token_type

		if t == 267 or t == 268 then
			errorWhileChecking = true
			nextLexeme()
			table.insert(
				expressions,
				reportExprError(
					{
						begin = vector.create(currentStartLine, currentStartColumn),
						end_ = vector.create(endLine, endColumn),
					},
					{},
					"Malformed interpolated string, expected expression inside '{}'"
				)
			)
		elseif t == 286 then
			errorWhileChecking = true
			nextLexeme()
			table.insert(
				expressions,
				reportExprError(
					{
						begin = vector.create(currentStartLine, currentStartColumn),
						end_ = vector.create(endLine, endColumn),
					},
					{},
					"Malformed interpolated string; did you forget to add a '`'?"
				)
			)
		else
			table.insert(expressions, ParserFunctions.parseExpr())
		end

		if errorWhileChecking then
			break
		end

		t = token_type

		if t == 266 or t == 267 or t == 268 then
		elseif token_type == 289 then
			nextLexeme()
			return reportExprError(
				{
					begin = vector.create(currentStartLine, currentStartColumn),
					end_ = vector.create(endLine, endColumn),
				},
				{},
				"Double braces are not permitted within interpolated strings; did you mean '\\{'?"
			)
		elseif token_type == 286 or token_type == 0 then
			if token_type == 286 then
				nextLexeme()
			end

			const node = {
				kind = "ExprInterpString",
				location = {
					begin = vector.create(startLine, startColumn),
					end_ = vector.create(prev_end_line, prev_end_col),
				},
				strings = strings,
				expressions = expressions,
			} :: AstExprInterpString

			if sourceStrings and stringPositions then
				node.cstNode =
					{ kind = "CstExprInterpString", sourceStrings = sourceStrings, stringPositions = stringPositions }
			end

			const top = if braceStackSize > 0 then braceStack[braceStackSize] else nil

			if top then
				if top == BraceType.InterpolatedString then
					report(getprev(), "Malformed interpolated string; did you forget to add a '}'?")
				end
			else
				report(getprev(), "Malformed interpolated string; did you forget to add a '`'?")
			end

			return node :: AstExprInterpString
		else
			return reportExprError(
				{
					begin = vector.create(currentStartLine, currentStartColumn),
					end_ = vector.create(endLine, endColumn),
				},
				{},
				"Malformed interpolated string, got %s",
				ToString(token_type, token_string, token_codepoint)
			)
		end
	end

	const node = {
		kind = "ExprInterpString",
		location = {
			begin = vector.create(startLine, startColumn),
			end_ = vector.create(endLine, endColumn),
		},
		strings = strings,
		expressions = expressions,
	} :: AstExprInterpString

	if sourceStrings and stringPositions then
		node.cstNode =
			{ kind = "CstExprInterpString", sourceStrings = sourceStrings, stringPositions = stringPositions }
	end

	return node :: AstExprInterpString
end

const function parseIfElseExprImpl(): AstExprIfElse
	local hasElse = false
	const startLine, startColumn = token_start_line, token_start_col

	nextLexeme() -- skip if / elseif

	const condition = ParserFunctions.parseExpr()

	local thenLine, thenColumn = 0, 0
	const hasThen = expectAndConsume(308, "if then else expression")
	if hasThen then
		thenLine, thenColumn = prev_start_line, prev_start_col
	end

	const trueExpr = ParserFunctions.parseExpr()
	local falseExpr: AstExpr? = nil

	const elseLine, elseColumn = token_start_line, token_start_col
	local isElseIf = false

	if token_type == 295 then
		const oldRecursion = recursionCounter
		incrementRecursionCounter("expression")
		hasElse = true
		falseExpr = parseIfElseExprImpl()
		recursionCounter = oldRecursion
		isElseIf = true
	else
		hasElse = expectAndConsume(294, "if then else expression")
		falseExpr = ParserFunctions.parseExpr()
	end

	const resolvedFalseExpr = falseExpr :: AstExpr

	const node = {
		kind = "ExprIfElse",
		location = {
			begin = vector.create(startLine, startColumn),
			end_ = resolvedFalseExpr.location.end_,
		},
		condition = condition,
		hasThen = hasThen,
		trueExpr = trueExpr,
		hasElse = hasElse,
		falseExpr = resolvedFalseExpr,
	} :: AstExprIfElse

	if storeCstData then
		node.cstNode = {
			kind = "CstExprIfElse",
			thenPosition = vector.create(thenLine, thenColumn),
			elsePosition = vector.create(elseLine, elseColumn),
			isElseIf = isElseIf,
		}
	end

	return node
end

-- simpleexp -> NUMBER | STRING | NIL | true | boolean | ... | constructor | [attributes] FUNCTION body | primaryexp
const function parseSimpleExprImpl(): AstExpr
	local attributes: Attrs? = nil
	local attributeStartLocation: Location? = nil
	local cstAttrLists: { CstAttrList }? = nil

	if token_type == 284 or token_type == 285 then
		attributes, attributeStartLocation, cstAttrLists = parseAttributes()

		if token_type ~= 299 then
			return reportExprError(
				attributeStartLocation :: Location,
				{},
				"Expected 'function' declaration after attribute, but got %s instead",
				ToString(token_type, token_string, token_codepoint)
			)
		end
	end

	if token_type == 303 then
		const location = snapshot()
		nextLexeme()
		return {
			kind = "ExprConstantNil",
			location = location,
		}
	elseif token_type == 309 then
		const location = snapshot()
		nextLexeme()
		return {
			kind = "ExprConstantBool",
			location = location,
			value = true,
		}
	elseif token_type == 297 then
		const location = snapshot()
		nextLexeme()
		return {
			kind = "ExprConstantBool",
			location = location,
			value = false,
		}
	elseif token_type == 299 then
		const matchFunctionType = token_type
		const matchFunctionLine, matchFunctionColumn = token_start_line, token_start_col
		const matchFunctionEndLine, matchFunctionEndColumn = token_end_line, token_end_col
		nextLexeme()
		const node = parseFunctionBodyImpl(
			false,
			matchFunctionType,
			matchFunctionLine,
			matchFunctionColumn,
			matchFunctionEndLine,
			matchFunctionEndColumn,
			nil,
			nil,
			nil,
			attributes or (EmptyArray :: Attrs),
			cstAttrLists,
			false
		)
		return node
	elseif token_type == 280 then
		return parseNumberImpl()
	elseif token_type == 278 or token_type == 279 or token_type == 269 then
		return parseStringImpl()
	elseif token_type == 266 then
		return parseInterpStringImpl()
	elseif token_type == 286 then
		const location = snapshot()
		nextLexeme()
		return reportExprError(location, {}, "Malformed string; did you forget to finish it?")
	elseif token_type == 289 then
		const location = snapshot()
		nextLexeme()
		return reportExprError(
			location,
			{},
			"Double braces are not permitted within interpolated strings; did you mean '\\{'?"
		)
	elseif token_type == 262 then
		const location = snapshot()
		if functionStack[#functionStack].vararg then
			nextLexeme()
			return {
				kind = "ExprVarargs",
				location = location,
			}
		else
			nextLexeme()
			return reportExprError(location, {}, "Cannot use '...' outside of a vararg function")
		end
	elseif token_type == 123 then
		return parseTableConstructorImpl()
	elseif token_type == 300 then
		return parseIfElseExprImpl()
	else
		return parsePrimaryExprImpl(false)
	end
end

-- asexp -> simpleexp [`::' Type]
const function parseAssertionExprImpl(): AstExpr
	const startLine, startColumn = token_start_line, token_start_col
	const expr = parseSimpleExprImpl()

	if token_type == 264 then
		const opLine, opColumn = token_start_line, token_start_col
		nextLexeme()
		const annotation = parseTypeImpl()
		const node = {
			kind = "ExprTypeAssertion",
			location = {
				begin = vector.create(startLine, startColumn),
				end_ = annotation.location.end_,
			},
			expr = expr,
			annotation = annotation,
		} :: AstExprTypeAssertion

		if storeCstData then
			node.cstNode = {
				kind = "CstExprTypeAssertion",
				opPosition = vector.create(opLine, opColumn),
			}
		end

		return node
	else
		return expr
	end
end

-- stat ::=
-- varlist `=' explist |
-- functioncall |
-- do block end |
-- while exp do block end |
-- repeat block until exp |
-- if exp then block {elseif exp then block} [else block] end |
-- for binding `=' exp `,' exp [`,' exp] do block end |
-- for namelist in explist do block end |
-- function funcname funcbody |
-- attributes function funcname funcbody |
-- local function Name funcbody |
-- local attributes function Name funcbody |
-- local namelist [`=' explist]
-- laststat ::= return [explist] | break
const function parseStat(): AstStat
	const type_ = token_type

	if type_ == 300 then
		return parseIfImpl()
	elseif type_ == 311 then
		return parseWhileImpl()
	elseif type_ == 293 then
		return parseDoImpl()
	elseif type_ == 298 then
		return parseForImpl()
	elseif type_ == 306 then
		return parseRepeatImpl()
	elseif type_ == 299 then
		return parseFunctionStatImpl(EmptyArray :: Attrs, nil, nil)
	elseif type_ == 302 then
		const start = snapshot()
		return parseLocalImpl(start, start.begin, nil, nil, false)
	elseif type_ == 307 then
		return parseReturnImpl()
	elseif type_ == 292 then
		return parseBreakImpl()
	elseif type_ == 284 or type_ == 285 then
		return parseAttributeStatImpl()
	end

	const start_line, start_column = token_start_line, token_start_col
	const start_end_line, start_end_column = token_end_line, token_end_col
	const expr = parsePrimaryExprImpl(true)

	if expr.kind == "ExprCall" then
		return {
			kind = "StatExpr",
			location = expr.location,
			expr = expr,
		}
	end

	if token_type == 44 or token_type == 61 then
		return parseAssignmentImpl(expr)
	end

	const operator = CompoundLookup[token_type]
	if operator then
		return parseCompoundAssignmentImpl(expr, operator)
	end

	local ident = nil :: string?
	if expr.kind == "ExprGlobal" then
		ident = expr.name
	elseif expr.kind == "ExprLocal" then
		ident = expr["local"] and expr["local"].name
	end

	if ident == "type" then
		return parseTypeAliasImpl(expr.location, false, expr.location.begin.x, expr.location.begin.y)
	end

	if Flags.DebugLuauUserDefinedClasses and ident == "class" then
		return parseClassStatImpl(expr.location, false, false)
	elseif Flags.DebugLuauUserDefinedClasses and ident == "open" then
		if token_type ~= 281 or token_string ~= "class" then
			return reportStatError(expr.location, { expr }, {}, "Incomplete statement: expected a class definition after 'open'")
		end
		nextLexeme()
		return parseClassStatImpl(expr.location, false, true)
	end

	if ident == "export" then
		if
			Flags.LuauExportValueSyntax
			and (
				token_type == 302
				or token_type == 299
				or (
					token_type == 281
					and (
						token_string == "const"
						or (Flags.DebugLuauUserDefinedClasses and (token_string == "class" or token_string == "open"))
					)
				)
			)
		then
			return parseExportValueImpl(expr.location, expr.location.begin, EmptyArray :: Attrs, nil)
		elseif token_type == 281 and token_string == "type" then
			const typeKeywordLine, typeKeywordColumn = token_start_line, token_start_col
			nextLexeme()
			return parseTypeAliasImpl(expr.location, true, typeKeywordLine, typeKeywordColumn)
		elseif not Flags.LuauExportValueSyntax and Flags.DebugLuauUserDefinedClasses and token_type == 281 and token_string == "class" then
			nextLexeme()
			return parseClassStatImpl(expr.location, true, false)
		elseif not Flags.LuauExportValueSyntax and Flags.DebugLuauUserDefinedClasses and token_type == 281 and token_string == "open" then
			nextLexeme()
			if token_type ~= 281 or token_string ~= "class" then
				return reportStatError(expr.location, { expr }, {}, "Incomplete statement: expected a class definition after 'open'")
			end
			nextLexeme()
			return parseClassStatImpl(expr.location, true, true)
		end
	end

	if ident == "continue" then
		return parseContinueImpl(expr.location)
	end

	if ident == "const" then
		return parseLocalImpl(expr.location, expr.location.begin, nil, nil, true)
	end

	if options.allowDeclarationSyntax and ident == "declare" then
		return parseDeclarationImpl(expr.location, EmptyArray :: Attrs)
	end

	if
		start_line == token_start_line
		and start_column == token_start_col
		and start_end_line == token_end_line
		and start_end_column == token_end_col
	then
		nextLexeme()
	end

	return reportStatError(expr.location, { expr }, {}, "Incomplete statement: expected assignment or a function call")
end

-- ReturnType ::= Type | `(' TypeList `)'
const function isTypeFollow(type_: number): boolean
	return type_ == 124 or type_ == 63 or type_ == 38
end

const function parseReturnTypeImpl(): AstTypePack
	incrementRecursionCounter("type annotation")

	const begin_type, begin_line, begin_col = token_type, token_start_line, token_start_col
	const beginLocation = {
		begin = vector.create(begin_line, begin_col),
		end_ = vector.create(token_end_line, token_end_col),
	}

	if token_type ~= 40 then
		if shouldParseTypePack() then
			return parseTypePackImpl()
		else
			const type_ = parseTypeImpl(false)

			const node = {
				kind = "TypePackExplicit",
				location = type_.location,
				types = { type_ },
			} :: AstTypePackExplicit

			if storeCstData then
				node.cstNode = {
					kind = "CstTypePackExplicit",
				}
			end
			return node
		end
	end

	nextLexeme()

	matchRecovery[263] += 1

	const result: { AstType } = {}
	const resultNames: { AstArgumentName | boolean } = {}
	const commaPositions: { Position }? = if storeCstData then {} else nil
	const nameColonPositions: { Position | boolean }? = if storeCstData then {} else nil

	local varargAnnotation: AstTypePack? = nil

	-- possibly () -> ReturnType
	if token_type ~= 41 then
		varargAnnotation = parseTypeListImpl(result, resultNames, commaPositions, nameColonPositions)
	end

	const endStartLine, endStartColumn = token_start_line, token_start_col
	const endLine, endColumn = token_end_line, token_end_col
	local closeParenPos: Position? = if storeCstData then vector.create(0, 0) else nil

	if expectMatchAndConsume(41, begin_type, begin_line, begin_col, true) then
		if closeParenPos then
			closeParenPos = vector.create(endStartLine, endStartColumn)
		end
	end

	matchRecovery[263] -= 1

	if token_type ~= 263 and #resultNames == 0 then
		-- If it turns out that it's just '(A)', it's possible that there are unions/intersections to follow, so fold over it.
		if #result == 1 then
			-- TODO(CLI-140667): stop parsing type suffix when varargAnnotation != nullptr - this should be a parse error
			local inner: AstType
			local parensBelongToInnerGroup = false
			if Flags.LuauSingleTypeOptionalPackReturnsAttributeParens then
				if varargAnnotation == nil and isTypeFollow(token_type) then
					const typeGroup = {
						kind = "TypeGroup",
						location = {
							begin = beginLocation.begin,
							end_ = vector.create(endLine, endColumn),
						},
						type = result[1],
					} :: AstTypeGroup

					if storeCstData then
						typeGroup.cstNode = {
							kind = "CstTypeGroup",
							closePosition = closeParenPos :: Position,
						}
					end

					inner = typeGroup
					parensBelongToInnerGroup = true
				else
					inner = result[1]
				end
			elseif varargAnnotation == nil then
				const typeGroup = {
					kind = "TypeGroup",
					location = {
						begin = beginLocation.begin,
						end_ = vector.create(endLine, endColumn),
					},
					type = result[1],
				} :: AstTypeGroup

				if storeCstData then
					typeGroup.cstNode = {
						kind = "CstTypeGroup",
						closePosition = closeParenPos :: Position,
					}
				end

				inner = typeGroup
			else
				inner = result[1]
			end

			const returnType = parseTypeSuffixImpl(inner, begin_line, begin_col)

			-- If parseType parses nothing, then returnType->location.end only points at the last non-type-pack
			-- type to successfully parse.  We need the span of the whole annotation.
			const endPos = if #result == 1
				then vector.create(endLine, endColumn)
				else returnType.location.end_

			const node = {
				kind = "TypePackExplicit",
				location = {
					begin = beginLocation.begin,
					end_ = endPos,
				},
				types = { returnType },
				tailType = varargAnnotation,
			} :: AstTypePackExplicit

			if storeCstData then
				if Flags.LuauSingleTypeOptionalPackReturnsAttributeParens and not parensBelongToInnerGroup then
					node.cstNode = {
						kind = "CstTypePackExplicit",
						openParenthesesPosition = beginLocation.begin,
						closeParenthesesPosition = closeParenPos :: Position,
						commaPositions = commaPositions or {},
					}
				else
					node.cstNode = {
						kind = "CstTypePackExplicit",
					}
				end
			end
			return node
		end

		const node = {
			kind = "TypePackExplicit",
			location = {
				begin = beginLocation.begin,
				end_ = vector.create(endLine, endColumn),
			},
			types = result,
			tailType = varargAnnotation,
		} :: AstTypePackExplicit

		if commaPositions then
			node.cstNode = {
				kind = "CstTypePackExplicit",
				openParenthesesPosition = beginLocation.begin,
				closeParenthesesPosition = closeParenPos :: Position,
				commaPositions = commaPositions,
			}
		end
		return node
	end

	const returnArrowLine, returnArrowColumn = token_start_line, token_start_col
	const tail = parseFunctionTypeTailImpl(
		begin_type,
		beginLocation,
		EmptyArray :: Attrs,
		EmptyArray :: { AstGenericType },
		EmptyArray :: { AstGenericTypePack },
		result,
		resultNames,
		varargAnnotation
	)

	if commaPositions and nameColonPositions and tail.kind == "TypeFunction" then
		tail.cstNode = {
			kind = "CstTypeFunction",
			openGenericsPosition = vector.create(0, 0),
			genericsCommaPositions = {},
			closeGenericsPosition = vector.create(0, 0),
			openArgsPosition = beginLocation.begin,
			argumentNameColonPositions = nameColonPositions,
			argumentsCommaPositions = commaPositions,
			closeArgsPosition = closeParenPos :: Position,
			returnArrowPosition = vector.create(returnArrowLine, returnArrowColumn),
		}
	end

	const node = {
		kind = "TypePackExplicit",
		location = {
			begin = beginLocation.begin,
			end_ = tail.location.end_,
		},
		types = { tail },
	} :: AstTypePackExplicit

	if storeCstData then
		node.cstNode = {
			kind = "CstTypePackExplicit",
		}
	end

	return node
end

-- Type ::= nil | Name[`.' Name] [ `<' Type [`,' ...] `>' ] | `typeof' `(' expr `)' | `{' [PropList] `}'
--   | [`<' varlist `>'] `(' [TypeList] `)' `->` ReturnType
const function parseSimpleTypeImpl(allowPack: boolean, inDeclarationContext: boolean): (AstType?, AstTypePack?)
	incrementRecursionCounter("type annotation")

	const startLine, startColumn = token_start_line, token_start_col
	const startEndLine, startEndColumn = token_end_line, token_end_col

	if token_type == 284 or token_type == 285 then
		if not inDeclarationContext then
			return reportTypeError(
				{
					begin = vector.create(startLine, startColumn),
					end_ = vector.create(startEndLine, startEndColumn),
				},
				{},
				"attributes are not allowed in declaration context"
			),
				nil
		else
			const attributes = parseAttributes()

			return parseFunctionTypeImpl(allowPack, attributes), nil
		end
	elseif token_type == 303 then
		const location = {
			begin = vector.create(startLine, startColumn),
			end_ = vector.create(startEndLine, startEndColumn),
		}
		nextLexeme()

		return {
			kind = "TypeReference",
			location = location,
			name = "nil",
			nameLocation = location,
			hasParameterList = false,
			parameters = EmptyArray :: { AstTypeOrPack },
		} :: AstTypeReference,
			nil
	elseif token_type == 309 then
		const location = {
			begin = vector.create(startLine, startColumn),
			end_ = vector.create(startEndLine, startEndColumn),
		}
		nextLexeme()

		return {
			kind = "TypeSingletonBool",
			location = location,
			value = true,
		} :: AstTypeSingletonBool,
			nil
	elseif token_type == 297 then
		const location = {
			begin = vector.create(startLine, startColumn),
			end_ = vector.create(startEndLine, startEndColumn),
		}
		nextLexeme()

		return {
			kind = "TypeSingletonBool",
			location = location,
			value = false,
		} :: AstTypeSingletonBool,
			nil
	elseif token_type == 278 or token_type == 279 then
		local style = 0
		local depth = 0
		local sourceString = nil :: string?
		if storeCstData then
			style, depth = extractStringDetails()
			sourceString = token_string
		end

		const location = {
			begin = vector.create(startLine, startColumn),
			end_ = vector.create(startEndLine, startEndColumn),
		}
		const chars = parseCharArrayImpl()
		if chars then
			const node = {
				kind = "TypeSingletonString",
				location = location,
				value = chars,
			} :: AstTypeSingletonString

			if storeCstData then
				node.cstNode = {
					kind = "CstTypeSingletonString",
					sourceString = sourceString,
					quoteStyle = style,
					blockDepth = depth,
				}
			end

			return node, nil
		else
			return reportTypeError(location, {}, "String literal contains malformed escape sequence"), nil
		end
	elseif token_type == 266 or token_type == 269 then
		const location = {
			begin = vector.create(startLine, startColumn),
			end_ = vector.create(startEndLine, startEndColumn),
		}
		parseInterpStringImpl()

		return reportTypeError(location, {}, "Interpolated string literals cannot be used as types"), nil
	elseif token_type == 286 then
		const location = {
			begin = vector.create(startLine, startColumn),
			end_ = vector.create(startEndLine, startEndColumn),
		}
		nextLexeme()
		return reportTypeError(location, {}, "Malformed string; did you forget to finish it?"), nil
	elseif token_type == 281 then
		local name, nameStartLine, nameStartColumn, nameEndLine, nameEndColumn = parseNameScalars("type name")
		name = name or "%error-id%"
		local nameLocation = {
			begin = vector.create(nameStartLine, nameStartColumn),
			end_ = vector.create(nameEndLine, nameEndColumn),
		}
		local prefix: string? = nil
		local prefixLoc: Location? = nil
		local prefixPointPos: Position? = nil
		local prefixLocal: AstLocal? = nil

		if token_type == 46 then
			if storeCstData then
				prefixPointPos = vector.create(token_start_line, token_start_col)
			end
			nextLexeme()
			prefix = name
			prefixLoc = nameLocation
			if Flags.LuauTrackPrefixLocal then
				prefixLocal = localMap[name]
			end
			name, nameStartLine, nameStartColumn, nameEndLine, nameEndColumn =
				parseIndexNameScalars("field name", nameLocation.end_)
			name = name or "%error-id%"
			nameLocation = {
				begin = vector.create(nameStartLine, nameStartColumn),
				end_ = vector.create(nameEndLine, nameEndColumn),
			}
		elseif token_type == 262 then
			report(snapshot(), "Unexpected '...' after type name; type pack is not allowed in this context")

			nextLexeme()
		elseif name == "typeof" then
			const typeofBeginType = token_type
			const typeofBeginLine, typeofBeginColumn = token_start_line, token_start_col
			const openParenFound = expectAndConsume(40, "typeof type")
			const expr = ParserFunctions.parseExpr()
			const endStartLine, endStartColumn = token_start_line, token_start_col
			const endLine, endColumn = token_end_line, token_end_col
			local closeLine, closeColumn = 0, 0
			if expectMatchAndConsume(
				41,
				typeofBeginType,
				typeofBeginLine,
				typeofBeginColumn,
				false
			) then
				closeLine, closeColumn = endStartLine, endStartColumn
			end

			const node = {
				kind = "TypeTypeof",
				location = {
					begin = vector.create(startLine, startColumn),
					end_ = vector.create(endLine, endColumn),
				},
				expr = expr,
			} :: AstTypeTypeof

			if storeCstData then
				node.cstNode = {
					kind = "CstTypeTypeof",
					openPosition = if openParenFound
						then vector.create(typeofBeginLine, typeofBeginColumn)
						else vector.create(0, 0),
					closePosition = vector.create(closeLine, closeColumn),
				}
			end
			return node, nil
		end

		local hasParams = false
		local params = EmptyArray :: { AstTypeOrPack }

		const openPosRef = if storeCstData then { vector.create(0, 0) } else nil
		const commaPosRef = if storeCstData then {} else nil
		const closePosRef = if storeCstData then { vector.create(0, 0) } else nil

		if token_type == 60 then
			hasParams = true
			params = parseTypeParamsImpl(openPosRef, commaPosRef, closePosRef)
		end

		const node = {
			kind = "TypeReference",
			location = {
				begin = vector.create(startLine, startColumn),
				end_ = vector.create(prev_end_line, prev_end_col),
			},
			prefix = prefix,
			name = name,
			prefixLocation = prefixLoc,
			prefixLocal = prefixLocal,
			nameLocation = nameLocation,
			hasParameterList = hasParams,
			parameters = params,
		} :: AstTypeReference

		if storeCstData then
			node.cstNode = {
				kind = "CstTypeReference",
				prefixPointPosition = prefixPointPos,
				openParametersPosition = openPosRef and openPosRef[1] or nil,
				parametersCommaPositions = commaPosRef or {},
				closeParametersPosition = closePosRef and closePosRef[1] or nil,
			}
		end

		return node, nil
	elseif token_type == 123 then
		return parseTableTypeImpl(inDeclarationContext), nil
	elseif token_type == 40 or token_type == 60 then
		return parseFunctionTypeImpl(allowPack, EmptyArray :: Attrs)
	elseif token_type == 299 then
		const location = {
			begin = vector.create(startLine, startColumn),
			end_ = vector.create(startEndLine, startEndColumn),
		}
		nextLexeme()

		return reportTypeError(location, {}, "Using 'function' as a type annotation is not supported..."), nil
	else
		const astErrorLocation = {
			begin = vector.create(prev_end_line, prev_end_col),
			end_ = vector.create(startLine, startColumn),
		}
		const parseErrorLocation = {
			begin = vector.create(prev_end_line, prev_end_col),
			end_ = vector.create(startEndLine, startEndColumn),
		}

		return reportMissingTypeError(
			parseErrorLocation,
			astErrorLocation,
			"Expected type, got %s",
			ToString(token_type, token_string, token_codepoint)
		),
			nil
	end
end

-- subexpr -> (asexp | unop subexpr) { binop subexpr }
-- where `binop' is any binary operator with a priority higher than `limit'
const function parseExprImpl(limit_val: number?): AstExpr
	const limit: number = limit_val or 0
	const oldRecursion = recursionCounter

	-- this handles recursive calls to parseSubExpr/parseExpr
	incrementRecursionCounter("expression")

	const startLine, startColumn = token_start_line, token_start_col
	local startPosition: Position? = nil
	local expr: AstExpr? = nil

	local uop: number? = UnaryOpLookup[token_type] -- Fix: Lookup based on token type
	if not uop then
		uop = checkUnaryConfusables()
	end

	if uop then
		const opLine, opColumn = token_start_line, token_start_col
		startPosition = vector.create(startLine, startColumn)
		nextLexeme()

		const subexpr = ParserFunctions.parseExpr(8)

		expr = {
			kind = "ExprUnary",
			location = {
				begin = startPosition,
				end_ = subexpr.location.end_,
			},
			op = uop :: number,
			expr = subexpr,
		} :: AstExprUnary

		if storeCstData then
			expr.cstNode = {
				kind = "CstExprOp",
				opPosition = vector.create(opLine, opColumn),
			}
		end
	else
		expr = parseAssertionExprImpl()
	end

	-- expand while operators have priorities higher than `limit'
	local op: number? = BinaryOpLookup[token_type] or checkBinaryConfusables(limit)

	-- expand while operators have priorities higher than `limit'
	while op and BinaryPriority[op][1] > limit do
		const opLine, opColumn = token_start_line, token_start_col
		if not startPosition then
			startPosition = vector.create(startLine, startColumn)
		end
		nextLexeme()

		-- read sub-expression with higher priority
		const nextExpr = ParserFunctions.parseExpr(BinaryPriority[op][2])

		expr = {
			kind = "ExprBinary",
			location = {
				begin = startPosition,
				end_ = nextExpr.location.end_,
			},
			op = op :: number,
			left = expr :: AstExpr,
			right = nextExpr,
		} :: AstExprBinary

		if storeCstData then
			expr.cstNode = {
				kind = "CstExprOp",
				opPosition = vector.create(opLine, opColumn),
			}
		end

		op = BinaryOpLookup[token_type] or checkBinaryConfusables(limit) -- Fix: Lookup based on token type

		-- note: while the parser isn't recursive here, we're generating recursive structures of unbounded depth
		incrementRecursionCounter("expression")
	end

	recursionCounter = oldRecursion
	return expr
end

ParserFunctions.parseStat = parseStat
ParserFunctions.parseReturnType = parseReturnTypeImpl
ParserFunctions.parseSimpleType = parseSimpleTypeImpl
ParserFunctions.parseExpr = parseExprImpl

const function parseChunk(sourceText: string, parseOptions: Options): AstStatBlock
	options = parseOptions
	captureComments = parseOptions.captureComments == true
	storeCstData = parseOptions.storeCstData == true

	buff_data = buffer.fromstring(sourceText)
	size = #sourceText

	offset = 0

	if parseOptions.parseFragment and parseOptions.parseFragment.resumePosition then
		line = parseOptions.parseFragment.resumePosition.x
		lineOffset = 0 - parseOptions.parseFragment.resumePosition.y
	else
		line = 0
		lineOffset = 0
	end

	const startColumn = 0 - lineOffset

	braceStack = {}
	braceStackSize = 0

	token_type = 0

	token_start_line = line
	token_start_col = startColumn
	token_end_line = line
	token_end_col = startColumn

	prev_start_line = line
	prev_start_col = startColumn
	prev_end_line = line
	prev_end_col = startColumn

	token_string = nil
	token_aux = nil
	token_codepoint = nil

	recursionCounter = 0

	commentLocations = EmptyArray :: { Comment }
	hotcomments = EmptyArray :: { HotComment }
	parseErrors = EmptyArray :: { ParseError }
	declaredExportBindings = EmptyArray :: { [string]: Location }
	hasModuleReturn = false
	classesWithinModule = EmptyArray :: { [string]: AstStatClass }

	hotcommentHeader = true

	suspect_type = 0
	suspect_line = 0

	matchRecovery = table.create(312, 0)
	matchRecovery[0] = 1

	functionStack = {
		{ vararg = true, loopDepth = 0 },
	}

	if parseOptions.parseFragment then
		localStack = table.clone(parseOptions.parseFragment.localStack)
		localMap = table.clone(parseOptions.parseFragment.localMap)
	else
		localStack = {}
		localMap = {}
	end

	fillNext()
	nextLexeme()
	hotcommentHeader = false

	const localsBegin = #localStack
	const result = parseBlockNoScope()
	restoreLocals(localsBegin)

	if token_type ~= 0 then
		expectAndConsumeFail(0)
	end

	return result
end

return {
	parse = function(source: string, options: Options?, observe: ((number, number, number) -> ())?, checkpoint: (() -> ())?): (boolean, Result)
		const parseOptions = options or {} :: Options
		onLexeme = observe
		lexerCheckpoint = checkpoint
		nextCheckpoint = if checkpoint then 16384 else math.huge
		const success, result = pcall(function()
			local root = parseChunk(source, parseOptions)
			if observe then
				while token_type ~= 0 do nextLexeme() end
			end
			return root
		end)
		onLexeme = nil
		lexerCheckpoint = nil
		const root = if success then result else nil
		const lines = if success then token_end_line + if size > 0 and buffer.readu8(buff_data, size - 1) ~= 10 then 1 else 0 else 0

		return success and #parseErrors == 0,
			{
				root = if success then root else nil,
				lines = lines,
				commentLocations = commentLocations,
				hotcomments = hotcomments,
				errors = parseErrors,
			}
	end,

	BraceType = BraceType,
	QuoteStyle = QuoteStyle,
	
	UnaryOp = {
		Not = 0,
		Minus = 1,
		Len = 2,
	},
	
	BinaryOp = BinaryOp,
	CstQuotes = CstQuotes,
}

end
return { New = New }
end
return { Main = Main }
