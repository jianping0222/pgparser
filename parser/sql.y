// Portions Copyright (c) 1996-2015, PostgreSQL Global Development Group
// Portions Copyright (c) 1994, Regents of the University of California

// Portions of this file are additionally subject to the following
// license and copyright.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
// implied. See the License for the specific language governing
// permissions and limitations under the License.

// Going to add a new statement?
// Consider taking a look at our codelab guide to learn what is needed to add a statement.
// https://github.com/ruiaylin/pgparser/blob/master/docs/codelabs/01-sql-statement.md

%{
package parser

import (
    "fmt"
    "strings"

    "go/constant"

    "github.com/ruiaylin/pgparser/types/geo/geopb"
    "github.com/ruiaylin/pgparser/roachpb"
    "github.com/ruiaylin/pgparser/lex"
    "github.com/ruiaylin/pgparser/privilege"
    "github.com/ruiaylin/pgparser/roleoption"
    "github.com/ruiaylin/pgparser/ast"
    "github.com/ruiaylin/pgparser/types"
)

// MaxUint is the maximum value of an uint.
const MaxUint = ^uint(0)
// MaxInt is the maximum value of an int.
const MaxInt = int(MaxUint >> 1)

func unimplemented(sqllex sqlLexer, feature string) int {
    sqllex.(*lexer).Unimplemented(feature)
    return 1
}

func purposelyUnimplemented(sqllex sqlLexer, feature string, reason string) int {
    sqllex.(*lexer).PurposelyUnimplemented(feature, reason)
    return 1
}

func setErr(sqllex sqlLexer, err error) int {
    sqllex.(*lexer).setErr(err)
    return 1
}

func unimplementedWithIssue(sqllex sqlLexer, issue int) int {
    sqllex.(*lexer).UnimplementedWithIssue(issue)
    return 1
}

func unimplementedWithIssueDetail(sqllex sqlLexer, issue int, detail string) int {
    sqllex.(*lexer).UnimplementedWithIssueDetail(issue, detail)
    return 1
}
%}

%{
// sqlSymUnion represents a union of types, providing accessor methods
// to retrieve the underlying type stored in the union's empty interface.
// The purpose of the sqlSymUnion struct is to reduce the memory footprint of
// the sqlSymType because only one value (of a variety of types) is ever needed
// to be stored in the union field at a time.
//
// By using an empty interface, we lose the type checking previously provided
// by yacc and the Go compiler when dealing with union values. Instead, runtime
// type assertions must be relied upon in the methods below, and as such, the
// parser should be thoroughly tested whenever new syntax is added.
//
// It is important to note that when assigning values to sqlSymUnion.val, all
// nil values should be typed so that they are stored as nil instances in the
// empty interface, instead of setting the empty interface to nil. This means
// that:
//     $$ = []String(nil)
// should be used, instead of:
//     $$ = nil
// to assign a nil string slice to the union.
type sqlSymUnion struct {
    val interface{}
}

// The following accessor methods come in three forms, depending on the
// type of the value being accessed and whether a nil value is admissible
// for the corresponding grammar rule.
// - Values and pointers are directly type asserted from the empty
//   interface, regardless of whether a nil value is admissible or
//   not. A panic occurs if the type assertion is incorrect; no panic occurs
//   if a nil is not expected but present. (TODO(knz): split this category of
//   accessor in two; with one checking for unexpected nils.)
//   Examples: bool(), tableIndexName().
//
// - Interfaces where a nil is admissible are handled differently
//   because a nil instance of an interface inserted into the empty interface
//   becomes a nil instance of the empty interface and therefore will fail a
//   direct type assertion. Instead, a guarded type assertion must be used,
//   which returns nil if the type assertion fails.
//   Examples: expr(), stmt().
//
// - Interfaces where a nil is not admissible are implemented as a direct
//   type assertion, which causes a panic to occur if an unexpected nil
//   is encountered.
//   Examples: tblDef().
//
func (u *sqlSymUnion) numVal() *ast.NumVal {
    return u.val.(*ast.NumVal)
}
func (u *sqlSymUnion) strVal() *ast.StrVal {
    if stmt, ok := u.val.(*ast.StrVal); ok {
        return stmt
    }
    return nil
}
func (u *sqlSymUnion) placeholder() *ast.Placeholder {
    return u.val.(*ast.Placeholder)
}
func (u *sqlSymUnion) auditMode() ast.AuditMode {
    return u.val.(ast.AuditMode)
}
func (u *sqlSymUnion) bool() bool {
    return u.val.(bool)
}
func (u *sqlSymUnion) strPtr() *string {
    return u.val.(*string)
}
func (u *sqlSymUnion) strs() []string {
    return u.val.([]string)
}
func (u *sqlSymUnion) newTableIndexName() *ast.TableIndexName {
    tn := u.val.(ast.TableIndexName)
    return &tn
}
func (u *sqlSymUnion) tableIndexName() ast.TableIndexName {
    return u.val.(ast.TableIndexName)
}
func (u *sqlSymUnion) newTableIndexNames() ast.TableIndexNames {
    return u.val.(ast.TableIndexNames)
}
func (u *sqlSymUnion) shardedIndexDef() *ast.ShardedIndexDef {
  return u.val.(*ast.ShardedIndexDef)
}
func (u *sqlSymUnion) nameList() ast.NameList {
    return u.val.(ast.NameList)
}
func (u *sqlSymUnion) unresolvedName() *ast.UnresolvedName {
    return u.val.(*ast.UnresolvedName)
}
func (u *sqlSymUnion) unresolvedObjectName() *ast.UnresolvedObjectName {
    return u.val.(*ast.UnresolvedObjectName)
}
func (u *sqlSymUnion) unresolvedObjectNames() []*ast.UnresolvedObjectName {
    return u.val.([]*ast.UnresolvedObjectName)
}
func (u *sqlSymUnion) functionReference() ast.FunctionReference {
    return u.val.(ast.FunctionReference)
}
func (u *sqlSymUnion) tablePatterns() ast.TablePatterns {
    return u.val.(ast.TablePatterns)
}
func (u *sqlSymUnion) tableNames() ast.TableNames {
    return u.val.(ast.TableNames)
}
func (u *sqlSymUnion) indexFlags() *ast.IndexFlags {
    return u.val.(*ast.IndexFlags)
}
func (u *sqlSymUnion) arraySubscript() *ast.ArraySubscript {
    return u.val.(*ast.ArraySubscript)
}
func (u *sqlSymUnion) arraySubscripts() ast.ArraySubscripts {
    if as, ok := u.val.(ast.ArraySubscripts); ok {
        return as
    }
    return nil
}
func (u *sqlSymUnion) stmt() ast.Statement {
    if stmt, ok := u.val.(ast.Statement); ok {
        return stmt
    }
    return nil
}
func (u *sqlSymUnion) cte() *ast.CTE {
    if cte, ok := u.val.(*ast.CTE); ok {
        return cte
    }
    return nil
}
func (u *sqlSymUnion) ctes() []*ast.CTE {
    return u.val.([]*ast.CTE)
}
func (u *sqlSymUnion) with() *ast.With {
    if with, ok := u.val.(*ast.With); ok {
        return with
    }
    return nil
}
func (u *sqlSymUnion) slct() *ast.Select {
    return u.val.(*ast.Select)
}
func (u *sqlSymUnion) selectStmt() ast.SelectStatement {
    return u.val.(ast.SelectStatement)
}
func (u *sqlSymUnion) colDef() *ast.ColumnTableDef {
    return u.val.(*ast.ColumnTableDef)
}
func (u *sqlSymUnion) constraintDef() ast.ConstraintTableDef {
    return u.val.(ast.ConstraintTableDef)
}
func (u *sqlSymUnion) tblDef() ast.TableDef {
    return u.val.(ast.TableDef)
}
func (u *sqlSymUnion) tblDefs() ast.TableDefs {
    return u.val.(ast.TableDefs)
}
func (u *sqlSymUnion) likeTableOption() ast.LikeTableOption {
    return u.val.(ast.LikeTableOption)
}
func (u *sqlSymUnion) likeTableOptionList() []ast.LikeTableOption {
    return u.val.([]ast.LikeTableOption)
}
func (u *sqlSymUnion) colQual() ast.NamedColumnQualification {
    return u.val.(ast.NamedColumnQualification)
}
func (u *sqlSymUnion) colQualElem() ast.ColumnQualification {
    return u.val.(ast.ColumnQualification)
}
func (u *sqlSymUnion) colQuals() []ast.NamedColumnQualification {
    return u.val.([]ast.NamedColumnQualification)
}
func (u *sqlSymUnion) storageParam() ast.StorageParam {
    return u.val.(ast.StorageParam)
}
func (u *sqlSymUnion) storageParams() []ast.StorageParam {
    if params, ok := u.val.([]ast.StorageParam); ok {
        return params
    }
    return nil
}
func (u *sqlSymUnion) persistenceType() bool {
 return u.val.(bool)
}
func (u *sqlSymUnion) colType() *types.T {
    if colType, ok := u.val.(*types.T); ok && colType != nil {
        return colType
    }
    return nil
}
func (u *sqlSymUnion) tableRefCols() []ast.ColumnID {
    if refCols, ok := u.val.([]ast.ColumnID); ok {
        return refCols
    }
    return nil
}
func (u *sqlSymUnion) colTypes() []*types.T {
    return u.val.([]*types.T)
}
func (u *sqlSymUnion) int32() int32 {
    return u.val.(int32)
}
func (u *sqlSymUnion) int64() int64 {
    return u.val.(int64)
}
func (u *sqlSymUnion) seqOpt() ast.SequenceOption {
    return u.val.(ast.SequenceOption)
}
func (u *sqlSymUnion) seqOpts() []ast.SequenceOption {
    return u.val.([]ast.SequenceOption)
}
func (u *sqlSymUnion) expr() ast.Expr {
    if expr, ok := u.val.(ast.Expr); ok {
        return expr
    }
    return nil
}
func (u *sqlSymUnion) exprs() ast.Exprs {
    return u.val.(ast.Exprs)
}
func (u *sqlSymUnion) selExpr() ast.SelectExpr {
    return u.val.(ast.SelectExpr)
}
func (u *sqlSymUnion) selExprs() ast.SelectExprs {
    return u.val.(ast.SelectExprs)
}
func (u *sqlSymUnion) retClause() ast.ReturningClause {
        return u.val.(ast.ReturningClause)
}
func (u *sqlSymUnion) aliasClause() ast.AliasClause {
    return u.val.(ast.AliasClause)
}
func (u *sqlSymUnion) asOfClause() ast.AsOfClause {
    return u.val.(ast.AsOfClause)
}
func (u *sqlSymUnion) tblExpr() ast.TableExpr {
    return u.val.(ast.TableExpr)
}
func (u *sqlSymUnion) tblExprs() ast.TableExprs {
    return u.val.(ast.TableExprs)
}
func (u *sqlSymUnion) from() ast.From {
    return u.val.(ast.From)
}
func (u *sqlSymUnion) int32s() []int32 {
    return u.val.([]int32)
}
func (u *sqlSymUnion) joinCond() ast.JoinCond {
    return u.val.(ast.JoinCond)
}
func (u *sqlSymUnion) when() *ast.When {
    return u.val.(*ast.When)
}
func (u *sqlSymUnion) whens() []*ast.When {
    return u.val.([]*ast.When)
}
func (u *sqlSymUnion) lockingClause() ast.LockingClause {
    return u.val.(ast.LockingClause)
}
func (u *sqlSymUnion) lockingItem() *ast.LockingItem {
    return u.val.(*ast.LockingItem)
}
func (u *sqlSymUnion) lockingStrength() ast.LockingStrength {
    return u.val.(ast.LockingStrength)
}
func (u *sqlSymUnion) lockingWaitPolicy() ast.LockingWaitPolicy {
    return u.val.(ast.LockingWaitPolicy)
}
func (u *sqlSymUnion) updateExpr() *ast.UpdateExpr {
    return u.val.(*ast.UpdateExpr)
}
func (u *sqlSymUnion) updateExprs() ast.UpdateExprs {
    return u.val.(ast.UpdateExprs)
}
func (u *sqlSymUnion) limit() *ast.Limit {
    return u.val.(*ast.Limit)
}
func (u *sqlSymUnion) targetList() ast.TargetList {
    return u.val.(ast.TargetList)
}
func (u *sqlSymUnion) targetListPtr() *ast.TargetList {
    return u.val.(*ast.TargetList)
}
func (u *sqlSymUnion) privilegeType() privilege.Kind {
    return u.val.(privilege.Kind)
}
func (u *sqlSymUnion) privilegeList() privilege.List {
    return u.val.(privilege.List)
}
func (u *sqlSymUnion) onConflict() *ast.OnConflict {
    return u.val.(*ast.OnConflict)
}
func (u *sqlSymUnion) orderBy() ast.OrderBy {
    return u.val.(ast.OrderBy)
}
func (u *sqlSymUnion) order() *ast.Order {
    return u.val.(*ast.Order)
}
func (u *sqlSymUnion) orders() []*ast.Order {
    return u.val.([]*ast.Order)
}
func (u *sqlSymUnion) groupBy() ast.GroupBy {
    return u.val.(ast.GroupBy)
}
func (u *sqlSymUnion) windowFrame() *ast.WindowFrame {
    return u.val.(*ast.WindowFrame)
}
func (u *sqlSymUnion) windowFrameBounds() ast.WindowFrameBounds {
    return u.val.(ast.WindowFrameBounds)
}
func (u *sqlSymUnion) windowFrameBound() *ast.WindowFrameBound {
    return u.val.(*ast.WindowFrameBound)
}
func (u *sqlSymUnion) windowFrameExclusion() ast.WindowFrameExclusion {
    return u.val.(ast.WindowFrameExclusion)
}
func (u *sqlSymUnion) distinctOn() ast.DistinctOn {
    return u.val.(ast.DistinctOn)
}
func (u *sqlSymUnion) dir() ast.Direction {
    return u.val.(ast.Direction)
}
func (u *sqlSymUnion) nullsOrder() ast.NullsOrder {
    return u.val.(ast.NullsOrder)
}
func (u *sqlSymUnion) alterTableCmd() ast.AlterTableCmd {
    return u.val.(ast.AlterTableCmd)
}
func (u *sqlSymUnion) alterTableCmds() ast.AlterTableCmds {
    return u.val.(ast.AlterTableCmds)
}
func (u *sqlSymUnion) alterIndexCmd() ast.AlterIndexCmd {
    return u.val.(ast.AlterIndexCmd)
}
func (u *sqlSymUnion) alterIndexCmds() ast.AlterIndexCmds {
    return u.val.(ast.AlterIndexCmds)
}
func (u *sqlSymUnion) isoLevel() ast.IsolationLevel {
    return u.val.(ast.IsolationLevel)
}
func (u *sqlSymUnion) userPriority() ast.UserPriority {
    return u.val.(ast.UserPriority)
}
func (u *sqlSymUnion) readWriteMode() ast.ReadWriteMode {
    return u.val.(ast.ReadWriteMode)
}
func (u *sqlSymUnion) idxElem() ast.IndexElem {
    return u.val.(ast.IndexElem)
}
func (u *sqlSymUnion) idxElems() ast.IndexElemList {
    return u.val.(ast.IndexElemList)
}
func (u *sqlSymUnion) dropBehavior() ast.DropBehavior {
    return u.val.(ast.DropBehavior)
}
func (u *sqlSymUnion) validationBehavior() ast.ValidationBehavior {
    return u.val.(ast.ValidationBehavior)
}
func (u *sqlSymUnion) interleave() *ast.InterleaveDef {
    return u.val.(*ast.InterleaveDef)
}
func (u *sqlSymUnion) partitionBy() *ast.PartitionBy {
    return u.val.(*ast.PartitionBy)
}
func (u *sqlSymUnion) createTableOnCommitSetting() ast.CreateTableOnCommitSetting {
    return u.val.(ast.CreateTableOnCommitSetting)
}
func (u *sqlSymUnion) listPartition() ast.ListPartition {
    return u.val.(ast.ListPartition)
}
func (u *sqlSymUnion) listPartitions() []ast.ListPartition {
    return u.val.([]ast.ListPartition)
}
func (u *sqlSymUnion) rangePartition() ast.RangePartition {
    return u.val.(ast.RangePartition)
}
func (u *sqlSymUnion) rangePartitions() []ast.RangePartition {
    return u.val.([]ast.RangePartition)
}
func (u *sqlSymUnion) setZoneConfig() *ast.SetZoneConfig {
    return u.val.(*ast.SetZoneConfig)
}
func (u *sqlSymUnion) tuples() []*ast.Tuple {
    return u.val.([]*ast.Tuple)
}
func (u *sqlSymUnion) tuple() *ast.Tuple {
    return u.val.(*ast.Tuple)
}
func (u *sqlSymUnion) windowDef() *ast.WindowDef {
    return u.val.(*ast.WindowDef)
}
func (u *sqlSymUnion) window() ast.Window {
    return u.val.(ast.Window)
}
func (u *sqlSymUnion) op() ast.Operator {
    return u.val.(ast.Operator)
}
func (u *sqlSymUnion) cmpOp() ast.ComparisonOperator {
    return u.val.(ast.ComparisonOperator)
}
func (u *sqlSymUnion) intervalTypeMetadata() types.IntervalTypeMetadata {
    return u.val.(types.IntervalTypeMetadata)
}
func (u *sqlSymUnion) kvOption() ast.KVOption {
    return u.val.(ast.KVOption)
}
func (u *sqlSymUnion) kvOptions() []ast.KVOption {
    if colType, ok := u.val.([]ast.KVOption); ok {
        return colType
    }
    return nil
}
func (u *sqlSymUnion) backupOptions() *ast.BackupOptions {
  return u.val.(*ast.BackupOptions)
}
func (u *sqlSymUnion) transactionModes() ast.TransactionModes {
    return u.val.(ast.TransactionModes)
}
func (u *sqlSymUnion) compositeKeyMatchMethod() ast.CompositeKeyMatchMethod {
  return u.val.(ast.CompositeKeyMatchMethod)
}
func (u *sqlSymUnion) referenceAction() ast.ReferenceAction {
    return u.val.(ast.ReferenceAction)
}
func (u *sqlSymUnion) referenceActions() ast.ReferenceActions {
    return u.val.(ast.ReferenceActions)
}
func (u *sqlSymUnion) createStatsOptions() *ast.CreateStatsOptions {
    return u.val.(*ast.CreateStatsOptions)
}
func (u *sqlSymUnion) scrubOptions() ast.ScrubOptions {
    return u.val.(ast.ScrubOptions)
}
func (u *sqlSymUnion) scrubOption() ast.ScrubOption {
    return u.val.(ast.ScrubOption)
}
func (u *sqlSymUnion) resolvableFuncRefFromName() ast.ResolvableFunctionReference {
    return ast.ResolvableFunctionReference{FunctionReference: u.unresolvedName()}
}
func (u *sqlSymUnion) rowsFromExpr() *ast.RowsFromExpr {
    return u.val.(*ast.RowsFromExpr)
}
func (u *sqlSymUnion) partitionedBackup() ast.PartitionedBackup {
    return u.val.(ast.PartitionedBackup)
}
func (u *sqlSymUnion) partitionedBackups() []ast.PartitionedBackup {
    return u.val.([]ast.PartitionedBackup)
}
func (u *sqlSymUnion) fullBackupClause() *ast.FullBackupClause {
    return u.val.(*ast.FullBackupClause)
}
func (u *sqlSymUnion) geoShapeType() geopb.ShapeType {
  return u.val.(geopb.ShapeType)
}
func newNameFromStr(s string) *ast.Name {
    return (*ast.Name)(&s)
}
func (u *sqlSymUnion) typeReference() ast.ResolvableTypeReference {
    return u.val.(ast.ResolvableTypeReference)
}
func (u *sqlSymUnion) typeReferences() []ast.ResolvableTypeReference {
    return u.val.([]ast.ResolvableTypeReference)
}
func (u *sqlSymUnion) alterTypeAddValuePlacement() *ast.AlterTypeAddValuePlacement {
    return u.val.(*ast.AlterTypeAddValuePlacement)
}
%}

// NB: the %token definitions must come before the %type definitions in this
// file to work around a bug in goyacc. See #16369 for more details.

// Non-keyword token types.
%token <str> IDENT SCONST BCONST BITCONST
%token <*ast.NumVal> ICONST FCONST
%token <*ast.Placeholder> PLACEHOLDER
%token <str> TYPECAST TYPEANNOTATE DOT_DOT
%token <str> LESS_EQUALS GREATER_EQUALS NOT_EQUALS
%token <str> NOT_REGMATCH REGIMATCH NOT_REGIMATCH
%token <str> ERROR

// If you want to make any keyword changes, add the new keyword here as well as
// to the appropriate one of the reserved-or-not-so-reserved keyword lists,
// below; search this file for "Keyword category lists".

// Ordinary key words in alphabetical order.
%token <str> ABORT ACTION ADD ADMIN AFTER AGGREGATE
%token <str> ALL ALTER ALWAYS ANALYSE ANALYZE AND AND_AND ANY ANNOTATE_TYPE ARRAY AS ASC
%token <str> ASYMMETRIC AT ATTRIBUTE AUTHORIZATION AUTOMATIC

%token <str> BACKUP BEFORE BEGIN BETWEEN BIGINT BIGSERIAL BIT
%token <str> BUCKET_COUNT
%token <str> BOOLEAN BOTH BUNDLE BY

%token <str> CACHE CANCEL CASCADE CASE CAST CBRT CHANGEFEED CHAR
%token <str> CHARACTER CHARACTERISTICS CHECK CLOSE
%token <str> CLUSTER COALESCE COLLATE COLLATION COLUMN COLUMNS COMMENT COMMENTS COMMIT
%token <str> COMMITTED COMPACT COMPLETE CONCAT CONCURRENTLY CONFIGURATION CONFIGURATIONS CONFIGURE
%token <str> CONFLICT CONSTRAINT CONSTRAINTS CONTAINS CONVERSION COPY COVERING CREATE CREATEROLE
%token <str> CROSS CUBE CURRENT CURRENT_CATALOG CURRENT_DATE CURRENT_SCHEMA
%token <str> CURRENT_ROLE CURRENT_TIME CURRENT_TIMESTAMP
%token <str> CURRENT_USER CYCLE

%token <str> DATA DATABASE DATABASES DATE DAY DEC DECIMAL DEFAULT DEFAULTS
%token <str> DEALLOCATE DECLARE DEFERRABLE DEFERRED DELETE DESC DETACHED
%token <str> DISCARD DISTINCT DO DOMAIN DOUBLE DROP

%token <str> ELSE ENCODING ENCRYPTION_PASSPHRASE END ENUM ESCAPE EXCEPT EXCLUDE EXCLUDING
%token <str> EXISTS EXECUTE EXECUTION EXPERIMENTAL
%token <str> EXPERIMENTAL_FINGERPRINTS EXPERIMENTAL_REPLICA
%token <str> EXPERIMENTAL_AUDIT
%token <str> EXPIRATION EXPLAIN EXPORT EXTENSION EXTRACT EXTRACT_DURATION

%token <str> FALSE FAMILY FETCH FETCHVAL FETCHTEXT FETCHVAL_PATH FETCHTEXT_PATH
%token <str> FILES FILTER
%token <str> FIRST FLOAT FLOAT4 FLOAT8 FLOORDIV FOLLOWING FOR FORCE_INDEX FOREIGN FROM FULL FUNCTION

%token <str> GENERATED GEOGRAPHY GEOMETRY GEOMETRYCOLLECTION
%token <str> GLOBAL GRANT GRANTS GREATEST GROUP GROUPING GROUPS

%token <str> HAVING HASH HIGH HISTOGRAM HOUR

%token <str> IDENTITY
%token <str> IF IFERROR IFNULL IGNORE_FOREIGN_KEYS ILIKE IMMEDIATE IMPORT IN INCLUDE INCLUDING INCREMENT INCREMENTAL
%token <str> INET INET_CONTAINED_BY_OR_EQUALS
%token <str> INET_CONTAINS_OR_EQUALS INDEX INDEXES INJECT INTERLEAVE INITIALLY
%token <str> INNER INSERT INT INTEGER
%token <str> INTERSECT INTERVAL INTO INVERTED IS ISERROR ISNULL ISOLATION

%token <str> JOB JOBS JOIN JSON JSONB JSON_SOME_EXISTS JSON_ALL_EXISTS

%token <str> KEY KEYS KV

%token <str> LANGUAGE LAST LATERAL LC_CTYPE LC_COLLATE
%token <str> LEADING LEASE LEAST LEFT LESS LEVEL LIKE LIMIT LINESTRING LIST LOCAL
%token <str> LOCALTIME LOCALTIMESTAMP LOCKED LOGIN LOOKUP LOW LSHIFT

%token <str> MATCH MATERIALIZED MERGE MINVALUE MAXVALUE MINUTE MONTH
%token <str> MULTILINESTRING MULTIPOINT MULTIPOLYGON

%token <str> NAN NAME NAMES NATURAL NEVER NEXT NO NOCREATEROLE NOLOGIN NO_INDEX_JOIN
%token <str> NONE NORMAL NOT NOTHING NOTNULL NOWAIT NULL NULLIF NULLS NUMERIC

%token <str> OF OFF OFFSET OID OIDS OIDVECTOR ON ONLY OPT OPTION OPTIONS OR
%token <str> ORDER ORDINALITY OTHERS OUT OUTER OVER OVERLAPS OVERLAY OWNED OWNER OPERATOR

%token <str> PARENT PARTIAL PARTITION PARTITIONS PASSWORD PAUSE PHYSICAL PLACING
%token <str> PLAN PLANS POINT POLYGON POSITION PRECEDING PRECISION PREPARE PRESERVE PRIMARY PRIORITY
%token <str> PROCEDURAL PUBLIC PUBLICATION

%token <str> QUERIES QUERY

%token <str> RANGE RANGES READ REAL RECURSIVE RECURRING REF REFERENCES
%token <str> REGCLASS REGPROC REGPROCEDURE REGNAMESPACE REGTYPE REINDEX
%token <str> REMOVE_PATH RENAME REPEATABLE REPLACE
%token <str> RELEASE RESET RESTORE RESTRICT RESUME RETURNING RETRY REVISION_HISTORY REVOKE RIGHT
%token <str> ROLE ROLES ROLLBACK ROLLUP ROW ROWS RSHIFT RULE

%token <str> SAVEPOINT SCATTER SCHEDULE SCHEMA SCHEMAS SCRUB SEARCH SECOND SELECT SEQUENCE SEQUENCES
%token <str> SERIALIZABLE SERVER SESSION SESSIONS SESSION_USER SET SETTING SETTINGS
%token <str> SHARE SHOW SIMILAR SIMPLE SKIP SMALLINT SMALLSERIAL SNAPSHOT SOME SPLIT SQL

%token <str> START STATISTICS STATUS STDIN STRICT STRING STORAGE STORE STORED STORING SUBSTRING
%token <str> SYMMETRIC SYNTAX SYSTEM SQRT SUBSCRIPTION

%token <str> TABLE TABLES TEMP TEMPLATE TEMPORARY TENANT TESTING_RELOCATE EXPERIMENTAL_RELOCATE TEXT THEN
%token <str> TIES TIME TIMETZ TIMESTAMP TIMESTAMPTZ TO THROTTLING TRAILING TRACE TRANSACTION TREAT TRIGGER TRIM TRUE
%token <str> TRUNCATE TRUSTED TYPE
%token <str> TRACING

%token <str> UNBOUNDED UNCOMMITTED UNION UNIQUE UNKNOWN UNLOGGED UNSPLIT
%token <str> UPDATE UPSERT UNTIL USE USER USERS USING UUID

%token <str> VALID VALIDATE VALUE VALUES VARBIT VARCHAR VARIADIC VIEW VARYING VIRTUAL

%token <str> WHEN WHERE WINDOW WITH WITHIN WITHOUT WORK WRITE

%token <str> YEAR

%token <str> ZONE

// The grammar thinks these are keywords, but they are not in any category
// and so can never be entered directly. The filter in scan.go creates these
// tokens when required (based on looking one token ahead).
//
// NOT_LA exists so that productions such as NOT LIKE can be given the same
// precedence as LIKE; otherwise they'd effectively have the same precedence as
// NOT, at least with respect to their left-hand subexpression. WITH_LA is
// needed to make the grammar LALR(1). GENERATED_ALWAYS is needed to support
// the Postgres syntax for computed columns along with our family related
// extensions (CREATE FAMILY/CREATE FAMILY family_name).
%token NOT_LA WITH_LA AS_LA GENERATED_ALWAYS

%union {
  id    int32
  pos   int32
  str   string
  union sqlSymUnion
}

%type <ast.Statement> stmt_block
%type <ast.Statement> stmt

%type <ast.Statement> alter_stmt
%type <ast.Statement> alter_ddl_stmt
%type <ast.Statement> alter_table_stmt
%type <ast.Statement> alter_index_stmt
%type <ast.Statement> alter_view_stmt
%type <ast.Statement> alter_sequence_stmt
%type <ast.Statement> alter_database_stmt
%type <ast.Statement> alter_range_stmt
%type <ast.Statement> alter_partition_stmt
%type <ast.Statement> alter_role_stmt
%type <ast.Statement> alter_type_stmt

// ALTER RANGE
%type <ast.Statement> alter_zone_range_stmt

// ALTER TABLE
%type <ast.Statement> alter_onetable_stmt
%type <ast.Statement> alter_split_stmt
%type <ast.Statement> alter_unsplit_stmt
%type <ast.Statement> alter_rename_table_stmt
%type <ast.Statement> alter_scatter_stmt
%type <ast.Statement> alter_relocate_stmt
%type <ast.Statement> alter_relocate_lease_stmt
%type <ast.Statement> alter_zone_table_stmt

// ALTER PARTITION
%type <ast.Statement> alter_zone_partition_stmt

// ALTER DATABASE
%type <ast.Statement> alter_rename_database_stmt
%type <ast.Statement> alter_zone_database_stmt

// ALTER INDEX
%type <ast.Statement> alter_oneindex_stmt
%type <ast.Statement> alter_scatter_index_stmt
%type <ast.Statement> alter_split_index_stmt
%type <ast.Statement> alter_unsplit_index_stmt
%type <ast.Statement> alter_rename_index_stmt
%type <ast.Statement> alter_relocate_index_stmt
%type <ast.Statement> alter_relocate_index_lease_stmt
%type <ast.Statement> alter_zone_index_stmt

// ALTER VIEW
%type <ast.Statement> alter_rename_view_stmt

// ALTER SEQUENCE
%type <ast.Statement> alter_rename_sequence_stmt
%type <ast.Statement> alter_sequence_options_stmt

%type <ast.Statement> backup_stmt
%type <ast.Statement> begin_stmt

%type <ast.Statement> cancel_stmt
%type <ast.Statement> cancel_jobs_stmt
%type <ast.Statement> cancel_queries_stmt
%type <ast.Statement> cancel_sessions_stmt

// SCRUB
%type <ast.Statement> scrub_stmt
%type <ast.Statement> scrub_database_stmt
%type <ast.Statement> scrub_table_stmt
%type <ast.ScrubOptions> opt_scrub_options_clause
%type <ast.ScrubOptions> scrub_option_list
%type <ast.ScrubOption> scrub_option

%type <ast.Statement> comment_stmt
%type <ast.Statement> commit_stmt
%type <ast.Statement> copy_from_stmt

%type <ast.Statement> create_stmt
%type <ast.Statement> create_changefeed_stmt
%type <ast.Statement> create_ddl_stmt
%type <ast.Statement> create_database_stmt
%type <ast.Statement> create_index_stmt
%type <ast.Statement> create_role_stmt
%type <ast.Statement> create_schedule_for_backup_stmt
%type <ast.Statement> create_schema_stmt
%type <ast.Statement> create_table_stmt
%type <ast.Statement> create_table_as_stmt
%type <ast.Statement> create_view_stmt
%type <ast.Statement> create_sequence_stmt

%type <ast.Statement> create_stats_stmt
%type <*ast.CreateStatsOptions> opt_create_stats_options
%type <*ast.CreateStatsOptions> create_stats_option_list
%type <*ast.CreateStatsOptions> create_stats_option

%type <ast.Statement> create_type_stmt
%type <ast.Statement> delete_stmt
%type <ast.Statement> discard_stmt

%type <ast.Statement> drop_stmt
%type <ast.Statement> drop_ddl_stmt
%type <ast.Statement> drop_database_stmt
%type <ast.Statement> drop_index_stmt
%type <ast.Statement> drop_role_stmt
%type <ast.Statement> drop_table_stmt
%type <ast.Statement> drop_type_stmt
%type <ast.Statement> drop_view_stmt
%type <ast.Statement> drop_sequence_stmt

%type <ast.Statement> analyze_stmt
%type <ast.Statement> explain_stmt
%type <ast.Statement> prepare_stmt
%type <ast.Statement> preparable_stmt
%type <ast.Statement> row_source_extension_stmt
%type <ast.Statement> export_stmt
%type <ast.Statement> execute_stmt
%type <ast.Statement> deallocate_stmt
%type <ast.Statement> grant_stmt
%type <ast.Statement> insert_stmt
%type <ast.Statement> import_stmt
%type <ast.Statement> pause_stmt
%type <ast.Statement> release_stmt
%type <ast.Statement> reset_stmt reset_session_stmt reset_csetting_stmt
%type <ast.Statement> resume_stmt
%type <ast.Statement> restore_stmt
%type <ast.PartitionedBackup> partitioned_backup
%type <[]ast.PartitionedBackup> partitioned_backup_list
%type <ast.Statement> revoke_stmt
%type <*ast.Select> select_stmt
%type <ast.Statement> abort_stmt
%type <ast.Statement> rollback_stmt
%type <ast.Statement> savepoint_stmt

%type <ast.Statement> preparable_set_stmt nonpreparable_set_stmt
%type <ast.Statement> set_session_stmt
%type <ast.Statement> set_csetting_stmt
%type <ast.Statement> set_transaction_stmt
%type <ast.Statement> set_exprs_internal
%type <ast.Statement> generic_set
%type <ast.Statement> set_rest_more
%type <ast.Statement> set_names

%type <ast.Statement> show_stmt
%type <ast.Statement> show_backup_stmt
%type <ast.Statement> show_columns_stmt
%type <ast.Statement> show_constraints_stmt
%type <ast.Statement> show_create_stmt
%type <ast.Statement> show_csettings_stmt
%type <ast.Statement> show_databases_stmt
%type <ast.Statement> show_fingerprints_stmt
%type <ast.Statement> show_grants_stmt
%type <ast.Statement> show_histogram_stmt
%type <ast.Statement> show_indexes_stmt
%type <ast.Statement> show_partitions_stmt
%type <ast.Statement> show_jobs_stmt
%type <ast.Statement> show_queries_stmt
%type <ast.Statement> show_ranges_stmt
%type <ast.Statement> show_range_for_row_stmt
%type <ast.Statement> show_roles_stmt
%type <ast.Statement> show_schemas_stmt
%type <ast.Statement> show_sequences_stmt
%type <ast.Statement> show_session_stmt
%type <ast.Statement> show_sessions_stmt
%type <ast.Statement> show_savepoint_stmt
%type <ast.Statement> show_stats_stmt
%type <ast.Statement> show_syntax_stmt
%type <ast.Statement> show_last_query_stats_stmt
%type <ast.Statement> show_tables_stmt
%type <ast.Statement> show_trace_stmt
%type <ast.Statement> show_transaction_stmt
%type <ast.Statement> show_users_stmt
%type <ast.Statement> show_zone_stmt

%type <str> session_var
%type <*string> comment_text

%type <ast.Statement> transaction_stmt
%type <ast.Statement> truncate_stmt
%type <ast.Statement> update_stmt
%type <ast.Statement> upsert_stmt
%type <ast.Statement> use_stmt

%type <ast.Statement> close_cursor_stmt
%type <ast.Statement> declare_cursor_stmt
%type <ast.Statement> reindex_stmt

%type <[]string> opt_incremental
%type <ast.KVOption> kv_option
%type <[]ast.KVOption> kv_option_list opt_with_options var_set_list opt_with_schedule_options
%type <*ast.BackupOptions> opt_with_backup_options backup_options backup_options_list
%type <str> import_format
%type <ast.StorageParam> storage_parameter
%type <[]ast.StorageParam> storage_parameter_list opt_table_with

%type <*ast.Select> select_no_parens
%type <ast.SelectStatement> select_clause select_with_parens simple_select values_clause table_clause simple_select_clause
%type <ast.LockingClause> for_locking_clause opt_for_locking_clause for_locking_items
%type <*ast.LockingItem> for_locking_item
%type <ast.LockingStrength> for_locking_strength
%type <ast.LockingWaitPolicy> opt_nowait_or_skip
%type <ast.SelectStatement> set_operation

%type <ast.Expr> alter_column_default
%type <ast.Direction> opt_asc_desc
%type <ast.NullsOrder> opt_nulls_order

%type <ast.AlterTableCmd> alter_table_cmd
%type <ast.AlterTableCmds> alter_table_cmds
%type <ast.AlterIndexCmd> alter_index_cmd
%type <ast.AlterIndexCmds> alter_index_cmds

%type <ast.DropBehavior> opt_drop_behavior
%type <ast.DropBehavior> opt_interleave_drop_behavior

%type <ast.ValidationBehavior> opt_validate_behavior

%type <str> opt_template_clause opt_encoding_clause opt_lc_collate_clause opt_lc_ctype_clause

%type <ast.IsolationLevel> transaction_iso_level
%type <ast.UserPriority> transaction_user_priority
%type <ast.ReadWriteMode> transaction_read_mode

%type <str> name opt_name opt_name_parens
%type <str> privilege savepoint_name
%type <ast.KVOption> role_option password_clause valid_until_clause
%type <ast.Operator> subquery_op
%type <*ast.UnresolvedName> func_name func_name_no_crdb_extra
%type <str> opt_collate

%type <str> cursor_name database_name index_name opt_index_name column_name insert_column_item statistics_name window_name
%type <str> family_name opt_family_name table_alias_name constraint_name target_name zone_name partition_name collation_name
%type <str> db_object_name_component
%type <*ast.UnresolvedObjectName> table_name standalone_index_name sequence_name type_name view_name db_object_name simple_db_object_name complex_db_object_name
%type <[]*ast.UnresolvedObjectName> type_name_list
%type <str> schema_name
%type <*ast.UnresolvedName> table_pattern complex_table_pattern
%type <*ast.UnresolvedName> column_path prefixed_column_path column_path_with_star
%type <ast.TableExpr> insert_target create_stats_target analyze_target

%type <*ast.TableIndexName> table_index_name
%type <ast.TableIndexNames> table_index_name_list

%type <ast.Operator> math_op

%type <ast.IsolationLevel> iso_level
%type <ast.UserPriority> user_priority

%type <ast.TableDefs> opt_table_elem_list table_elem_list create_as_opt_col_list create_as_table_defs
%type <[]ast.LikeTableOption> like_table_option_list
%type <ast.LikeTableOption> like_table_option
%type <ast.CreateTableOnCommitSetting> opt_create_table_on_commit
%type <*ast.InterleaveDef> opt_interleave
%type <*ast.PartitionBy> opt_partition_by partition_by
%type <str> partition opt_partition
%type <ast.ListPartition> list_partition
%type <[]ast.ListPartition> list_partitions
%type <ast.RangePartition> range_partition
%type <[]ast.RangePartition> range_partitions
%type <empty> opt_all_clause
%type <bool> distinct_clause
%type <ast.DistinctOn> distinct_on_clause
%type <ast.NameList> opt_column_list insert_column_list opt_stats_columns
%type <ast.OrderBy> sort_clause single_sort_clause opt_sort_clause
%type <[]*ast.Order> sortby_list
%type <ast.IndexElemList> index_params create_as_params
%type <ast.NameList> name_list privilege_list
%type <[]int32> opt_array_bounds
%type <ast.From> from_clause
%type <ast.TableExprs> from_list rowsfrom_list opt_from_list
%type <ast.TablePatterns> table_pattern_list single_table_pattern_list
%type <ast.TableNames> table_name_list opt_locked_rels
%type <ast.Exprs> expr_list opt_expr_list tuple1_ambiguous_values tuple1_unambiguous_values
%type <*ast.Tuple> expr_tuple1_ambiguous expr_tuple_unambiguous
%type <ast.NameList> attrs
%type <ast.SelectExprs> target_list
%type <ast.UpdateExprs> set_clause_list
%type <*ast.UpdateExpr> set_clause multiple_set_clause
%type <ast.ArraySubscripts> array_subscripts
%type <ast.GroupBy> group_clause
%type <*ast.Limit> select_limit opt_select_limit
%type <ast.TableNames> relation_expr_list
%type <ast.ReturningClause> returning_clause
%type <empty> opt_using_clause

%type <[]ast.SequenceOption> sequence_option_list opt_sequence_option_list
%type <ast.SequenceOption> sequence_option_elem

%type <bool> all_or_distinct
%type <bool> with_comment
%type <empty> join_outer
%type <ast.JoinCond> join_qual
%type <str> join_type
%type <str> opt_join_hint

%type <ast.Exprs> extract_list
%type <ast.Exprs> overlay_list
%type <ast.Exprs> position_list
%type <ast.Exprs> substr_list
%type <ast.Exprs> trim_list
%type <ast.Exprs> execute_param_clause
%type <types.IntervalTypeMetadata> opt_interval_qualifier interval_qualifier interval_second
%type <ast.Expr> overlay_placing

%type <bool> opt_unique opt_concurrently opt_cluster
%type <bool> opt_using_gin_btree

%type <*ast.Limit> limit_clause offset_clause opt_limit_clause
%type <ast.Expr> select_fetch_first_value
%type <empty> row_or_rows
%type <empty> first_or_next

%type <ast.Statement> insert_rest
%type <ast.NameList> opt_conf_expr opt_col_def_list
%type <*ast.OnConflict> on_conflict

%type <ast.Statement> begin_transaction
%type <ast.TransactionModes> transaction_mode_list transaction_mode

%type <*ast.ShardedIndexDef> opt_hash_sharded
%type <ast.NameList> opt_storing
%type <*ast.ColumnTableDef> column_def
%type <ast.TableDef> table_elem
%type <ast.Expr> where_clause opt_where_clause
%type <*ast.ArraySubscript> array_subscript
%type <ast.Expr> opt_slice_bound
%type <*ast.IndexFlags> opt_index_flags
%type <*ast.IndexFlags> index_flags_param
%type <*ast.IndexFlags> index_flags_param_list
%type <ast.Expr> a_expr b_expr c_expr d_expr typed_literal
%type <ast.Expr> substr_from substr_for
%type <ast.Expr> in_expr
%type <ast.Expr> having_clause
%type <ast.Expr> array_expr
%type <ast.Expr> interval_value
%type <[]ast.ResolvableTypeReference> type_list prep_type_clause
%type <ast.Exprs> array_expr_list
%type <*ast.Tuple> row labeled_row
%type <ast.Expr> case_expr case_arg case_default
%type <*ast.When> when_clause
%type <[]*ast.When> when_clause_list
%type <ast.ComparisonOperator> sub_type
%type <ast.Expr> numeric_only
%type <ast.AliasClause> alias_clause opt_alias_clause
%type <bool> opt_ordinality opt_compact
%type <*ast.Order> sortby
%type <ast.IndexElem> index_elem create_as_param
%type <ast.TableExpr> table_ref numeric_table_ref func_table
%type <ast.Exprs> rowsfrom_list
%type <ast.Expr> rowsfrom_item
%type <ast.TableExpr> joined_table
%type <*ast.UnresolvedObjectName> relation_expr
%type <ast.TableExpr> table_expr_opt_alias_idx table_name_opt_idx
%type <ast.SelectExpr> target_elem
%type <*ast.UpdateExpr> single_set_clause
%type <ast.AsOfClause> as_of_clause opt_as_of_clause
%type <ast.Expr> opt_changefeed_sink

%type <str> explain_option_name
%type <[]string> explain_option_list opt_enum_val_list enum_val_list

%type <ast.ResolvableTypeReference> typename simple_typename cast_target
%type <*types.T> const_typename
%type <*ast.AlterTypeAddValuePlacement> opt_add_val_placement
%type <bool> opt_timezone
%type <*types.T> numeric opt_numeric_modifiers
%type <*types.T> opt_float
%type <*types.T> character_with_length character_without_length
%type <*types.T> const_datetime interval_type
%type <*types.T> bit_with_length bit_without_length
%type <*types.T> character_base
%type <*types.T> geo_shape_type
%type <*types.T> const_geo
%type <str> extract_arg
%type <bool> opt_varying

%type <*ast.NumVal> signed_iconst only_signed_iconst
%type <*ast.NumVal> signed_fconst only_signed_fconst
%type <int32> iconst32
%type <int64> signed_iconst64
%type <int64> iconst64
%type <ast.Expr> var_value
%type <ast.Exprs> var_list
%type <ast.NameList> var_name
%type <str> unrestricted_name type_function_name type_function_name_no_crdb_extra
%type <str> non_reserved_word
%type <str> non_reserved_word_or_sconst
%type <ast.Expr> zone_value
%type <ast.Expr> string_or_placeholder
%type <ast.Expr> string_or_placeholder_list

%type <str> unreserved_keyword type_func_name_keyword type_func_name_no_crdb_extra_keyword type_func_name_crdb_extra_keyword
%type <str> col_name_keyword reserved_keyword cockroachdb_extra_reserved_keyword extra_var_value

%type <ast.ResolvableTypeReference> complex_type_name
%type <str> general_type_name

%type <ast.ConstraintTableDef> table_constraint constraint_elem create_as_constraint_def create_as_constraint_elem
%type <ast.TableDef> index_def
%type <ast.TableDef> family_def
%type <[]ast.NamedColumnQualification> col_qual_list create_as_col_qual_list
%type <ast.NamedColumnQualification> col_qualification create_as_col_qualification
%type <ast.ColumnQualification> col_qualification_elem create_as_col_qualification_elem
%type <ast.CompositeKeyMatchMethod> key_match
%type <ast.ReferenceActions> reference_actions
%type <ast.ReferenceAction> reference_action reference_on_delete reference_on_update

%type <ast.Expr> func_application func_expr_common_subexpr special_function
%type <ast.Expr> func_expr func_expr_windowless
%type <empty> opt_with
%type <*ast.With> with_clause opt_with_clause
%type <[]*ast.CTE> cte_list
%type <*ast.CTE> common_table_expr
%type <bool> materialize_clause

%type <ast.Expr> within_group_clause
%type <ast.Expr> filter_clause
%type <ast.Exprs> opt_partition_clause
%type <ast.Window> window_clause window_definition_list
%type <*ast.WindowDef> window_definition over_clause window_specification
%type <str> opt_existing_window_name
%type <*ast.WindowFrame> opt_frame_clause
%type <ast.WindowFrameBounds> frame_extent
%type <*ast.WindowFrameBound> frame_bound
%type <ast.WindowFrameExclusion> opt_frame_exclusion

%type <[]ast.ColumnID> opt_tableref_col_list tableref_col_list

%type <ast.TargetList> targets targets_roles changefeed_targets
%type <*ast.TargetList> opt_on_targets_roles opt_backup_targets
%type <ast.NameList> for_grantee_clause
%type <privilege.List> privileges
%type <[]ast.KVOption> opt_role_options role_options
%type <ast.AuditMode> audit_mode

%type <str> relocate_kw

%type <*ast.SetZoneConfig> set_zone_config

%type <ast.Expr> opt_alter_column_using

%type <bool> opt_temp
%type <bool> opt_temp_create_table
%type <bool> role_or_group_or_user

%type <ast.Expr>  cron_expr opt_description sconst_or_placeholder
%type <*ast.FullBackupClause> opt_full_backup_clause

// Precedence: lowest to highest
%nonassoc  VALUES              // see value_clause
%nonassoc  SET                 // see table_expr_opt_alias_idx
%left      UNION EXCEPT
%left      INTERSECT
%left      OR
%left      AND
%right     NOT
%nonassoc  IS ISNULL NOTNULL   // IS sets precedence for IS NULL, etc
%nonassoc  '<' '>' '=' LESS_EQUALS GREATER_EQUALS NOT_EQUALS
%nonassoc  '~' BETWEEN IN LIKE ILIKE SIMILAR NOT_REGMATCH REGIMATCH NOT_REGIMATCH NOT_LA
%nonassoc  ESCAPE              // ESCAPE must be just above LIKE/ILIKE/SIMILAR
%nonassoc  CONTAINS CONTAINED_BY '?' JSON_SOME_EXISTS JSON_ALL_EXISTS
%nonassoc  OVERLAPS
%left      POSTFIXOP           // dummy for postfix OP rules
// To support target_elem without AS, we must give IDENT an explicit priority
// between POSTFIXOP and OP. We can safely assign the same priority to various
// unreserved keywords as needed to resolve ambiguities (this can't have any
// bad effects since obviously the keywords will still behave the same as if
// they weren't keywords). We need to do this for PARTITION, RANGE, ROWS,
// GROUPS to support opt_existing_window_name; and for RANGE, ROWS, GROUPS so
// that they can follow a_expr without creating postfix-operator problems; and
// for NULL so that it can follow b_expr in col_qual_list without creating
// postfix-operator problems.
//
// To support CUBE and ROLLUP in GROUP BY without reserving them, we give them
// an explicit priority lower than '(', so that a rule with CUBE '(' will shift
// rather than reducing a conflicting rule that takes CUBE as a function name.
// Using the same precedence as IDENT seems right for the reasons given above.
//
// The frame_bound productions UNBOUNDED PRECEDING and UNBOUNDED FOLLOWING are
// even messier: since UNBOUNDED is an unreserved keyword (per spec!), there is
// no principled way to distinguish these from the productions a_expr
// PRECEDING/FOLLOWING. We hack this up by giving UNBOUNDED slightly lower
// precedence than PRECEDING and FOLLOWING. At present this doesn't appear to
// cause UNBOUNDED to be treated differently from other unreserved keywords
// anywhere else in the grammar, but it's definitely risky. We can blame any
// funny behavior of UNBOUNDED on the SQL standard, though.
%nonassoc  UNBOUNDED         // ideally should have same precedence as IDENT
%nonassoc  IDENT NULL PARTITION RANGE ROWS GROUPS PRECEDING FOLLOWING CUBE ROLLUP
%left      CONCAT FETCHVAL FETCHTEXT FETCHVAL_PATH FETCHTEXT_PATH REMOVE_PATH  // multi-character ops
%left      '|'
%left      '#'
%left      '&'
%left      LSHIFT RSHIFT INET_CONTAINS_OR_EQUALS INET_CONTAINED_BY_OR_EQUALS AND_AND SQRT CBRT
%left      '+' '-'
%left      '*' '/' FLOORDIV '%'
%left      '^'
// Unary Operators
%left      AT                // sets precedence for AT TIME ZONE
%left      COLLATE
%right     UMINUS
%left      '[' ']'
%left      '(' ')'
%left      TYPEANNOTATE
%left      TYPECAST
%left      '.'
// These might seem to be low-precedence, but actually they are not part
// of the arithmetic hierarchy at all in their use as JOIN operators.
// We make them high-precedence to support their use as function names.
// They wouldn't be given a precedence at all, were it not that we need
// left-associativity among the JOIN rules themselves.
%left      JOIN CROSS LEFT FULL RIGHT INNER NATURAL
%right     HELPTOKEN

%%

stmt_block:
  stmt
  {
    sqllex.(*lexer).SetStmt($1.stmt())
  }

stmt:
  HELPTOKEN { return helpWith(sqllex, "") }
| preparable_stmt   // help texts in sub-rule
| analyze_stmt      // EXTEND WITH HELP: ANALYZE
| copy_from_stmt
| comment_stmt
| execute_stmt      // EXTEND WITH HELP: EXECUTE
| deallocate_stmt   // EXTEND WITH HELP: DEALLOCATE
| discard_stmt      // EXTEND WITH HELP: DISCARD
| grant_stmt        // EXTEND WITH HELP: GRANT
| prepare_stmt      // EXTEND WITH HELP: PREPARE
| revoke_stmt       // EXTEND WITH HELP: REVOKE
| savepoint_stmt    // EXTEND WITH HELP: SAVEPOINT
| release_stmt      // EXTEND WITH HELP: RELEASE
| nonpreparable_set_stmt // help texts in sub-rule
| transaction_stmt  // help texts in sub-rule
| close_cursor_stmt
| declare_cursor_stmt
| reindex_stmt
| /* EMPTY */
  {
    $$.val = ast.Statement(nil)
  }

// %Help: ALTER
// %Category: Group
// %Text: ALTER TABLE, ALTER INDEX, ALTER VIEW, ALTER SEQUENCE, ALTER DATABASE, ALTER USER, ALTER ROLE
alter_stmt:
  alter_ddl_stmt      // help texts in sub-rule
| alter_role_stmt     // EXTEND WITH HELP: ALTER ROLE
| ALTER error         // SHOW HELP: ALTER

alter_ddl_stmt:
  alter_table_stmt     // EXTEND WITH HELP: ALTER TABLE
| alter_index_stmt     // EXTEND WITH HELP: ALTER INDEX
| alter_view_stmt      // EXTEND WITH HELP: ALTER VIEW
| alter_sequence_stmt  // EXTEND WITH HELP: ALTER SEQUENCE
| alter_database_stmt  // EXTEND WITH HELP: ALTER DATABASE
| alter_range_stmt     // EXTEND WITH HELP: ALTER RANGE
| alter_partition_stmt // EXTEND WITH HELP: ALTER PARTITION
| alter_type_stmt      // EXTEND WITH HELP: ALTER TYPE

// %Help: ALTER TABLE - change the definition of a table
// %Category: DDL
// %Text:
// ALTER TABLE [IF EXISTS] <tablename> <command> [, ...]
//
// Commands:
//   ALTER TABLE ... ADD [COLUMN] [IF NOT EXISTS] <colname> <type> [<qualifiers...>]
//   ALTER TABLE ... ADD <constraint>
//   ALTER TABLE ... DROP [COLUMN] [IF EXISTS] <colname> [RESTRICT | CASCADE]
//   ALTER TABLE ... DROP CONSTRAINT [IF EXISTS] <constraintname> [RESTRICT | CASCADE]
//   ALTER TABLE ... ALTER [COLUMN] <colname> {SET DEFAULT <expr> | DROP DEFAULT}
//   ALTER TABLE ... ALTER [COLUMN] <colname> DROP NOT NULL
//   ALTER TABLE ... ALTER [COLUMN] <colname> DROP STORED
//   ALTER TABLE ... ALTER [COLUMN] <colname> [SET DATA] TYPE <type> [COLLATE <collation>]
//   ALTER TABLE ... ALTER PRIMARY KEY USING INDEX <name>
//   ALTER TABLE ... RENAME TO <newname>
//   ALTER TABLE ... RENAME [COLUMN] <colname> TO <newname>
//   ALTER TABLE ... VALIDATE CONSTRAINT <constraintname>
//   ALTER TABLE ... SPLIT AT <selectclause> [WITH EXPIRATION <expr>]
//   ALTER TABLE ... UNSPLIT AT <selectclause>
//   ALTER TABLE ... UNSPLIT ALL
//   ALTER TABLE ... SCATTER [ FROM ( <exprs...> ) TO ( <exprs...> ) ]
//   ALTER TABLE ... INJECT STATISTICS ...  (experimental)
//   ALTER TABLE ... PARTITION BY RANGE ( <name...> ) ( <rangespec> )
//   ALTER TABLE ... PARTITION BY LIST ( <name...> ) ( <listspec> )
//   ALTER TABLE ... PARTITION BY NOTHING
//   ALTER TABLE ... CONFIGURE ZONE <zoneconfig>
//
// Column qualifiers:
//   [CONSTRAINT <constraintname>] {NULL | NOT NULL | UNIQUE | PRIMARY KEY | CHECK (<expr>) | DEFAULT <expr>}
//   FAMILY <familyname>, CREATE [IF NOT EXISTS] FAMILY [<familyname>]
//   REFERENCES <tablename> [( <colnames...> )]
//   COLLATE <collationname>
//
// Zone configurations:
//   DISCARD
//   USING <var> = <expr> [, ...]
//   USING <var> = COPY FROM PARENT [, ...]
//   { TO | = } <expr>
//
// %SeeAlso: WEBDOCS/alter-table.html
alter_table_stmt:
  alter_onetable_stmt
| alter_relocate_stmt
| alter_relocate_lease_stmt
| alter_split_stmt
| alter_unsplit_stmt
| alter_scatter_stmt
| alter_zone_table_stmt
| alter_rename_table_stmt
// ALTER TABLE has its error help token here because the ALTER TABLE
// prefix is spread over multiple non-terminals.
| ALTER TABLE error     // SHOW HELP: ALTER TABLE

// %Help: ALTER PARTITION - apply zone configurations to a partition
// %Category: DDL
// %Text:
// ALTER PARTITION <name> <command>
//
// Commands:
//   -- Alter a single partition which exists on any of a table's indexes.
//   ALTER PARTITION <partition> OF TABLE <tablename> CONFIGURE ZONE <zoneconfig>
//
//   -- Alter a partition of a specific index.
//   ALTER PARTITION <partition> OF INDEX <tablename>@<indexname> CONFIGURE ZONE <zoneconfig>
//
//   -- Alter all partitions with the same name across a table's indexes.
//   ALTER PARTITION <partition> OF INDEX <tablename>@* CONFIGURE ZONE <zoneconfig>
//
// Zone configurations:
//   DISCARD
//   USING <var> = <expr> [, ...]
//   USING <var> = COPY FROM PARENT [, ...]
//   { TO | = } <expr>
//
// %SeeAlso: WEBDOCS/configure-zone.html
alter_partition_stmt:
  alter_zone_partition_stmt
| ALTER PARTITION error // SHOW HELP: ALTER PARTITION

// %Help: ALTER VIEW - change the definition of a view
// %Category: DDL
// %Text:
// ALTER VIEW [IF EXISTS] <name> RENAME TO <newname>
// %SeeAlso: WEBDOCS/alter-view.html
alter_view_stmt:
  alter_rename_view_stmt
// ALTER VIEW has its error help token here because the ALTER VIEW
// prefix is spread over multiple non-terminals.
| ALTER VIEW error // SHOW HELP: ALTER VIEW

// %Help: ALTER SEQUENCE - change the definition of a sequence
// %Category: DDL
// %Text:
// ALTER SEQUENCE [IF EXISTS] <name>
//   [INCREMENT <increment>]
//   [MINVALUE <minvalue> | NO MINVALUE]
//   [MAXVALUE <maxvalue> | NO MAXVALUE]
//   [START <start>]
//   [[NO] CYCLE]
// ALTER SEQUENCE [IF EXISTS] <name> RENAME TO <newname>
alter_sequence_stmt:
  alter_rename_sequence_stmt
| alter_sequence_options_stmt
| ALTER SEQUENCE error // SHOW HELP: ALTER SEQUENCE

alter_sequence_options_stmt:
  ALTER SEQUENCE sequence_name sequence_option_list
  {
    $$.val = &ast.AlterSequence{Name: $3.unresolvedObjectName(), Options: $4.seqOpts(), IfExists: false}
  }
| ALTER SEQUENCE IF EXISTS sequence_name sequence_option_list
  {
    $$.val = &ast.AlterSequence{Name: $5.unresolvedObjectName(), Options: $6.seqOpts(), IfExists: true}
  }

// %Help: ALTER DATABASE - change the definition of a database
// %Category: DDL
// %Text:
// ALTER DATABASE <name> RENAME TO <newname>
// %SeeAlso: WEBDOCS/alter-database.html
alter_database_stmt:
  alter_rename_database_stmt
|  alter_zone_database_stmt
// ALTER DATABASE has its error help token here because the ALTER DATABASE
// prefix is spread over multiple non-terminals.
| ALTER DATABASE error // SHOW HELP: ALTER DATABASE

// %Help: ALTER RANGE - change the parameters of a range
// %Category: DDL
// %Text:
// ALTER RANGE <zonename> <command>
//
// Commands:
//   ALTER RANGE ... CONFIGURE ZONE <zoneconfig>
//
// Zone configurations:
//   DISCARD
//   USING <var> = <expr> [, ...]
//   USING <var> = COPY FROM PARENT [, ...]
//   { TO | = } <expr>
//
// %SeeAlso: ALTER TABLE
alter_range_stmt:
  alter_zone_range_stmt
| ALTER RANGE error // SHOW HELP: ALTER RANGE

// %Help: ALTER INDEX - change the definition of an index
// %Category: DDL
// %Text:
// ALTER INDEX [IF EXISTS] <idxname> <command>
//
// Commands:
//   ALTER INDEX ... RENAME TO <newname>
//   ALTER INDEX ... SPLIT AT <selectclause> [WITH EXPIRATION <expr>]
//   ALTER INDEX ... UNSPLIT AT <selectclause>
//   ALTER INDEX ... UNSPLIT ALL
//   ALTER INDEX ... SCATTER [ FROM ( <exprs...> ) TO ( <exprs...> ) ]
//
// Zone configurations:
//   DISCARD
//   USING <var> = <expr> [, ...]
//   USING <var> = COPY FROM PARENT [, ...]
//   { TO | = } <expr>
//
// %SeeAlso: WEBDOCS/alter-index.html
alter_index_stmt:
  alter_oneindex_stmt
| alter_relocate_index_stmt
| alter_relocate_index_lease_stmt
| alter_split_index_stmt
| alter_unsplit_index_stmt
| alter_scatter_index_stmt
| alter_rename_index_stmt
| alter_zone_index_stmt
// ALTER INDEX has its error help token here because the ALTER INDEX
// prefix is spread over multiple non-terminals.
| ALTER INDEX error // SHOW HELP: ALTER INDEX

alter_onetable_stmt:
  ALTER TABLE relation_expr alter_table_cmds
  {
    $$.val = &ast.AlterTable{Table: $3.unresolvedObjectName(), IfExists: false, Cmds: $4.alterTableCmds()}
  }
| ALTER TABLE IF EXISTS relation_expr alter_table_cmds
  {
    $$.val = &ast.AlterTable{Table: $5.unresolvedObjectName(), IfExists: true, Cmds: $6.alterTableCmds()}
  }

alter_oneindex_stmt:
  ALTER INDEX table_index_name alter_index_cmds
  {
    $$.val = &ast.AlterIndex{Index: $3.tableIndexName(), IfExists: false, Cmds: $4.alterIndexCmds()}
  }
| ALTER INDEX IF EXISTS table_index_name alter_index_cmds
  {
    $$.val = &ast.AlterIndex{Index: $5.tableIndexName(), IfExists: true, Cmds: $6.alterIndexCmds()}
  }

alter_split_stmt:
  ALTER TABLE table_name SPLIT AT select_stmt
  {
    name := $3.unresolvedObjectName().ToTableName()
    $$.val = &ast.Split{
      TableOrIndex: ast.TableIndexName{Table: name},
      Rows: $6.slct(),
      ExpireExpr: ast.Expr(nil),
    }
  }
| ALTER TABLE table_name SPLIT AT select_stmt WITH EXPIRATION a_expr
  {
    name := $3.unresolvedObjectName().ToTableName()
    $$.val = &ast.Split{
      TableOrIndex: ast.TableIndexName{Table: name},
      Rows: $6.slct(),
      ExpireExpr: $9.expr(),
    }
  }

alter_split_index_stmt:
  ALTER INDEX table_index_name SPLIT AT select_stmt
  {
    $$.val = &ast.Split{TableOrIndex: $3.tableIndexName(), Rows: $6.slct(), ExpireExpr: ast.Expr(nil)}
  }
| ALTER INDEX table_index_name SPLIT AT select_stmt WITH EXPIRATION a_expr
  {
    $$.val = &ast.Split{TableOrIndex: $3.tableIndexName(), Rows: $6.slct(), ExpireExpr: $9.expr()}
  }

alter_unsplit_stmt:
  ALTER TABLE table_name UNSPLIT AT select_stmt
  {
    name := $3.unresolvedObjectName().ToTableName()
    $$.val = &ast.Unsplit{
      TableOrIndex: ast.TableIndexName{Table: name},
      Rows: $6.slct(),
    }
  }
| ALTER TABLE table_name UNSPLIT ALL
  {
    name := $3.unresolvedObjectName().ToTableName()
    $$.val = &ast.Unsplit {
      TableOrIndex: ast.TableIndexName{Table: name},
      All: true,
    }
  }

alter_unsplit_index_stmt:
  ALTER INDEX table_index_name UNSPLIT AT select_stmt
  {
    $$.val = &ast.Unsplit{TableOrIndex: $3.tableIndexName(), Rows: $6.slct()}
  }
| ALTER INDEX table_index_name UNSPLIT ALL
  {
    $$.val = &ast.Unsplit{TableOrIndex: $3.tableIndexName(), All: true}
  }

relocate_kw:
  TESTING_RELOCATE
| EXPERIMENTAL_RELOCATE

alter_relocate_stmt:
  ALTER TABLE table_name relocate_kw select_stmt
  {
    /* SKIP DOC */
    name := $3.unresolvedObjectName().ToTableName()
    $$.val = &ast.Relocate{
      TableOrIndex: ast.TableIndexName{Table: name},
      Rows: $5.slct(),
    }
  }

alter_relocate_index_stmt:
  ALTER INDEX table_index_name relocate_kw select_stmt
  {
    /* SKIP DOC */
    $$.val = &ast.Relocate{TableOrIndex: $3.tableIndexName(), Rows: $5.slct()}
  }

alter_relocate_lease_stmt:
  ALTER TABLE table_name relocate_kw LEASE select_stmt
  {
    /* SKIP DOC */
    name := $3.unresolvedObjectName().ToTableName()
    $$.val = &ast.Relocate{
      TableOrIndex: ast.TableIndexName{Table: name},
      Rows: $6.slct(),
      RelocateLease: true,
    }
  }

alter_relocate_index_lease_stmt:
  ALTER INDEX table_index_name relocate_kw LEASE select_stmt
  {
    /* SKIP DOC */
    $$.val = &ast.Relocate{TableOrIndex: $3.tableIndexName(), Rows: $6.slct(), RelocateLease: true}
  }

alter_zone_range_stmt:
  ALTER RANGE zone_name set_zone_config
  {
     s := $4.setZoneConfig()
     s.ZoneSpecifier = ast.ZoneSpecifier{NamedZone: ast.UnrestrictedName($3)}
     $$.val = s
  }

set_zone_config:
  CONFIGURE ZONE to_or_eq a_expr
  {
    /* SKIP DOC */
    $$.val = &ast.SetZoneConfig{YAMLConfig: $4.expr()}
  }
| CONFIGURE ZONE USING var_set_list
  {
    $$.val = &ast.SetZoneConfig{Options: $4.kvOptions()}
  }
| CONFIGURE ZONE USING DEFAULT
  {
    /* SKIP DOC */
    $$.val = &ast.SetZoneConfig{SetDefault: true}
  }
| CONFIGURE ZONE DISCARD
  {
    $$.val = &ast.SetZoneConfig{YAMLConfig: ast.DNull}
  }

alter_zone_database_stmt:
  ALTER DATABASE database_name set_zone_config
  {
     s := $4.setZoneConfig()
     s.ZoneSpecifier = ast.ZoneSpecifier{Database: ast.Name($3)}
     $$.val = s
  }

alter_zone_table_stmt:
  ALTER TABLE table_name set_zone_config
  {
    name := $3.unresolvedObjectName().ToTableName()
    s := $4.setZoneConfig()
    s.ZoneSpecifier = ast.ZoneSpecifier{
       TableOrIndex: ast.TableIndexName{Table: name},
    }
    $$.val = s
  }

alter_zone_index_stmt:
  ALTER INDEX table_index_name set_zone_config
  {
    s := $4.setZoneConfig()
    s.ZoneSpecifier = ast.ZoneSpecifier{
       TableOrIndex: $3.tableIndexName(),
    }
    $$.val = s
  }

alter_zone_partition_stmt:
  ALTER PARTITION partition_name OF TABLE table_name set_zone_config
  {
    name := $6.unresolvedObjectName().ToTableName()
    s := $7.setZoneConfig()
    s.ZoneSpecifier = ast.ZoneSpecifier{
       TableOrIndex: ast.TableIndexName{Table: name},
       Partition: ast.Name($3),
    }
    $$.val = s
  }
| ALTER PARTITION partition_name OF INDEX table_index_name set_zone_config
  {
    s := $7.setZoneConfig()
    s.ZoneSpecifier = ast.ZoneSpecifier{
       TableOrIndex: $6.tableIndexName(),
       Partition: ast.Name($3),
    }
    $$.val = s
  }
| ALTER PARTITION partition_name OF INDEX table_name '@' '*' set_zone_config
  {
    name := $6.unresolvedObjectName().ToTableName()
    s := $9.setZoneConfig()
    s.ZoneSpecifier = ast.ZoneSpecifier{
       TableOrIndex: ast.TableIndexName{Table: name},
       Partition: ast.Name($3),
    }
    s.AllIndexes = true
    $$.val = s
  }
| ALTER PARTITION partition_name OF TABLE table_name '@' error
  {
    err := errors.New("index name should not be specified in ALTER PARTITION ... OF TABLE")
    err = errors.WithHint(err, "try ALTER PARTITION ... OF INDEX")
    return setErr(sqllex, err)
  }
| ALTER PARTITION partition_name OF TABLE table_name '@' '*' error
  {
    err := errors.New("index wildcard unsupported in ALTER PARTITION ... OF TABLE")
    err = errors.WithHint(err, "try ALTER PARTITION <partition> OF INDEX <tablename>@*")
    return setErr(sqllex, err)
  }

var_set_list:
  var_name '=' COPY FROM PARENT
  {
    $$.val = []ast.KVOption{ast.KVOption{Key: ast.Name(strings.Join($1.strs(), "."))}}
  }
| var_name '=' var_value
  {
    $$.val = []ast.KVOption{ast.KVOption{Key: ast.Name(strings.Join($1.strs(), ".")), Value: $3.expr()}}
  }
| var_set_list ',' var_name '=' var_value
  {
    $$.val = append($1.kvOptions(), ast.KVOption{Key: ast.Name(strings.Join($3.strs(), ".")), Value: $5.expr()})
  }
| var_set_list ',' var_name '=' COPY FROM PARENT
  {
    $$.val = append($1.kvOptions(), ast.KVOption{Key: ast.Name(strings.Join($3.strs(), "."))})
  }

alter_scatter_stmt:
  ALTER TABLE table_name SCATTER
  {
    name := $3.unresolvedObjectName().ToTableName()
    $$.val = &ast.Scatter{TableOrIndex: ast.TableIndexName{Table: name}}
  }
| ALTER TABLE table_name SCATTER FROM '(' expr_list ')' TO '(' expr_list ')'
  {
    name := $3.unresolvedObjectName().ToTableName()
    $$.val = &ast.Scatter{
      TableOrIndex: ast.TableIndexName{Table: name},
      From: $7.exprs(),
      To: $11.exprs(),
    }
  }

alter_scatter_index_stmt:
  ALTER INDEX table_index_name SCATTER
  {
    $$.val = &ast.Scatter{TableOrIndex: $3.tableIndexName()}
  }
| ALTER INDEX table_index_name SCATTER FROM '(' expr_list ')' TO '(' expr_list ')'
  {
    $$.val = &ast.Scatter{TableOrIndex: $3.tableIndexName(), From: $7.exprs(), To: $11.exprs()}
  }

alter_table_cmds:
  alter_table_cmd
  {
    $$.val = ast.AlterTableCmds{$1.alterTableCmd()}
  }
| alter_table_cmds ',' alter_table_cmd
  {
    $$.val = append($1.alterTableCmds(), $3.alterTableCmd())
  }

alter_table_cmd:
  // ALTER TABLE <name> RENAME [COLUMN] <name> TO <newname>
  RENAME opt_column column_name TO column_name
  {
    $$.val = &ast.AlterTableRenameColumn{Column: ast.Name($3), NewName: ast.Name($5) }
  }
  // ALTER TABLE <name> RENAME CONSTRAINT <name> TO <newname>
| RENAME CONSTRAINT column_name TO column_name
  {
    $$.val = &ast.AlterTableRenameConstraint{Constraint: ast.Name($3), NewName: ast.Name($5) }
  }
  // ALTER TABLE <name> ADD <coldef>
| ADD column_def
  {
    $$.val = &ast.AlterTableAddColumn{IfNotExists: false, ColumnDef: $2.colDef()}
  }
  // ALTER TABLE <name> ADD IF NOT EXISTS <coldef>
| ADD IF NOT EXISTS column_def
  {
    $$.val = &ast.AlterTableAddColumn{IfNotExists: true, ColumnDef: $5.colDef()}
  }
  // ALTER TABLE <name> ADD COLUMN <coldef>
| ADD COLUMN column_def
  {
    $$.val = &ast.AlterTableAddColumn{IfNotExists: false, ColumnDef: $3.colDef()}
  }
  // ALTER TABLE <name> ADD COLUMN IF NOT EXISTS <coldef>
| ADD COLUMN IF NOT EXISTS column_def
  {
    $$.val = &ast.AlterTableAddColumn{IfNotExists: true, ColumnDef: $6.colDef()}
  }
  // ALTER TABLE <name> ALTER [COLUMN] <colname> {SET DEFAULT <expr>|DROP DEFAULT}
| ALTER opt_column column_name alter_column_default
  {
    $$.val = &ast.AlterTableSetDefault{Column: ast.Name($3), Default: $4.expr()}
  }
  // ALTER TABLE <name> ALTER [COLUMN] <colname> DROP NOT NULL
| ALTER opt_column column_name DROP NOT NULL
  {
    $$.val = &ast.AlterTableDropNotNull{Column: ast.Name($3)}
  }
  // ALTER TABLE <name> ALTER [COLUMN] <colname> DROP STORED
| ALTER opt_column column_name DROP STORED
  {
    $$.val = &ast.AlterTableDropStored{Column: ast.Name($3)}
  }
  // ALTER TABLE <name> ALTER [COLUMN] <colname> SET NOT NULL
| ALTER opt_column column_name SET NOT NULL
  {
    $$.val = &ast.AlterTableSetNotNull{Column: ast.Name($3)}
  }
  // ALTER TABLE <name> DROP [COLUMN] IF EXISTS <colname> [RESTRICT|CASCADE]
| DROP opt_column IF EXISTS column_name opt_drop_behavior
  {
    $$.val = &ast.AlterTableDropColumn{
      IfExists: true,
      Column: ast.Name($5),
      DropBehavior: $6.dropBehavior(),
    }
  }
  // ALTER TABLE <name> DROP [COLUMN] <colname> [RESTRICT|CASCADE]
| DROP opt_column column_name opt_drop_behavior
  {
    $$.val = &ast.AlterTableDropColumn{
      IfExists: false,
      Column: ast.Name($3),
      DropBehavior: $4.dropBehavior(),
    }
  }
  // ALTER TABLE <name> ALTER [COLUMN] <colname>
  //     [SET DATA] TYPE <typename>
  //     [ COLLATE collation ]
  //     [ USING <expression> ]
| ALTER opt_column column_name opt_set_data TYPE typename opt_collate opt_alter_column_using
  {
    $$.val = &ast.AlterTableAlterColumnType{
      Column: ast.Name($3),
      ToType: $6.typeReference(),
      Collation: $7,
      Using: $8.expr(),
    }
  }
  // ALTER TABLE <name> ADD CONSTRAINT ...
| ADD table_constraint opt_validate_behavior
  {
    $$.val = &ast.AlterTableAddConstraint{
      ConstraintDef: $2.constraintDef(),
      ValidationBehavior: $3.validationBehavior(),
    }
  }
  // ALTER TABLE <name> ALTER CONSTRAINT ...
| ALTER CONSTRAINT constraint_name error { return unimplementedWithIssueDetail(sqllex, 31632, "alter constraint") }
  // ALTER TABLE <name> VALIDATE CONSTRAINT ...
  // ALTER TABLE <name> ALTER PRIMARY KEY USING INDEX <name>
| ALTER PRIMARY KEY USING COLUMNS '(' index_params ')' opt_hash_sharded opt_interleave
  {
    $$.val = &ast.AlterTableAlterPrimaryKey{
      Columns: $7.idxElems(),
      Sharded: $9.shardedIndexDef(),
      Interleave: $10.interleave(),
    }
  }
| VALIDATE CONSTRAINT constraint_name
  {
    $$.val = &ast.AlterTableValidateConstraint{
      Constraint: ast.Name($3),
    }
  }
  // ALTER TABLE <name> DROP CONSTRAINT IF EXISTS <name> [RESTRICT|CASCADE]
| DROP CONSTRAINT IF EXISTS constraint_name opt_drop_behavior
  {
    $$.val = &ast.AlterTableDropConstraint{
      IfExists: true,
      Constraint: ast.Name($5),
      DropBehavior: $6.dropBehavior(),
    }
  }
  // ALTER TABLE <name> DROP CONSTRAINT <name> [RESTRICT|CASCADE]
| DROP CONSTRAINT constraint_name opt_drop_behavior
  {
    $$.val = &ast.AlterTableDropConstraint{
      IfExists: false,
      Constraint: ast.Name($3),
      DropBehavior: $4.dropBehavior(),
    }
  }
  // ALTER TABLE <name> EXPERIMENTAL_AUDIT SET <mode>
| EXPERIMENTAL_AUDIT SET audit_mode
  {
    $$.val = &ast.AlterTableSetAudit{Mode: $3.auditMode()}
  }
  // ALTER TABLE <name> PARTITION BY ...
| partition_by
  {
    $$.val = &ast.AlterTablePartitionBy{
      PartitionBy: $1.partitionBy(),
    }
  }
  // ALTER TABLE <name> INJECT STATISTICS <json>
| INJECT STATISTICS a_expr
  {
    /* SKIP DOC */
    $$.val = &ast.AlterTableInjectStats{
      Stats: $3.expr(),
    }
  }

audit_mode:
  READ WRITE { $$.val = ast.AuditModeReadWrite }
| OFF        { $$.val = ast.AuditModeDisable }

alter_index_cmds:
  alter_index_cmd
  {
    $$.val = ast.AlterIndexCmds{$1.alterIndexCmd()}
  }
| alter_index_cmds ',' alter_index_cmd
  {
    $$.val = append($1.alterIndexCmds(), $3.alterIndexCmd())
  }

alter_index_cmd:
  partition_by
  {
    $$.val = &ast.AlterIndexPartitionBy{
      PartitionBy: $1.partitionBy(),
    }
  }

alter_column_default:
  SET DEFAULT a_expr
  {
    $$.val = $3.expr()
  }
| DROP DEFAULT
  {
    $$.val = nil
  }

opt_alter_column_using:
  USING a_expr
  {
     $$.val = $2.expr()
  }
| /* EMPTY */
  {
     $$.val = nil
  }


opt_drop_behavior:
  CASCADE
  {
    $$.val = ast.DropCascade
  }
| RESTRICT
  {
    $$.val = ast.DropRestrict
  }
| /* EMPTY */
  {
    $$.val = ast.DropDefault
  }

opt_validate_behavior:
  NOT VALID
  {
    $$.val = ast.ValidationSkip
  }
| /* EMPTY */
  {
    $$.val = ast.ValidationDefault
  }

// %Help: ALTER TYPE - change the definition of a type.
// %Category: DDL
// %Text: ALTER TYPE <typename> <command>
//
// Commands:
//   ALTER TYPE ... ADD VALUE [IF NOT EXISTS] <value> [ { BEFORE | AFTER } <value> ]
//   ALTER TYPE ... RENAME VALUE <oldname> TO <newname>
//   ALTER TYPE ... RENAME TO <newname>
//   ALTER TYPE ... SET SCHEMA <newschemaname>
//   ALTER TYPE ... OWNER TO {<newowner> | CURRENT_USER | SESSION_USER }
//   ALTER TYPE ... RENAME ATTRIBUTE <oldname> TO <newname> [ CASCADE | RESTRICT ]
//   ALTER TYPE ... <attributeaction> [, ... ]
//
// Attribute action:
//   ADD ATTRIBUTE <name> <type> [ COLLATE <collation> ] [ CASCADE | RESTRICT ]
//   DROP ATTRIBUTE [IF EXISTS] <name> [ CASCADE | RESTRICT ]
//   ALTER ATTRIBUTE <name> [ SET DATA ] TYPE <type> [ COLLATE <collation> ] [ CASCADE | RESTRICT ]
//
// %SeeAlso: WEBDOCS/alter-type.html
alter_type_stmt:
  ALTER TYPE type_name ADD VALUE SCONST opt_add_val_placement
  {
    $$.val = &ast.AlterType{
      Type: $3.unresolvedObjectName(),
      Cmd: &ast.AlterTypeAddValue{
        NewVal: $6,
        IfNotExists: false,
        Placement: $7.alterTypeAddValuePlacement(),
      },
    }
  }
| ALTER TYPE type_name ADD VALUE IF NOT EXISTS SCONST opt_add_val_placement
  {
    $$.val = &ast.AlterType{
      Type: $3.unresolvedObjectName(),
      Cmd: &ast.AlterTypeAddValue{
        NewVal: $9,
        IfNotExists: true,
        Placement: $10.alterTypeAddValuePlacement(),
      },
    }
  }
| ALTER TYPE type_name RENAME VALUE SCONST TO SCONST
  {
    $$.val = &ast.AlterType{
      Type: $3.unresolvedObjectName(),
      Cmd: &ast.AlterTypeRenameValue{
        OldVal: $6,
        NewVal: $8,
      },
    }
  }
| ALTER TYPE type_name RENAME TO name
  {
    $$.val = &ast.AlterType{
      Type: $3.unresolvedObjectName(),
      Cmd: &ast.AlterTypeRename{
        NewName: $6,
      },
    }
  }
| ALTER TYPE type_name SET SCHEMA schema_name
  {
    $$.val = &ast.AlterType{
      Type: $3.unresolvedObjectName(),
      Cmd: &ast.AlterTypeSetSchema{
        Schema: $6,
      },
    }
  }
| ALTER TYPE type_name OWNER TO role_spec
  {
    return unimplementedWithIssueDetail(sqllex, 48700, "ALTER TYPE OWNER TO")
  }
| ALTER TYPE type_name RENAME ATTRIBUTE column_name TO column_name opt_drop_behavior
  {
    return unimplementedWithIssueDetail(sqllex, 48701, "ALTER TYPE ATTRIBUTE")
  }
| ALTER TYPE type_name alter_attribute_action_list
  {
    return unimplementedWithIssueDetail(sqllex, 48701, "ALTER TYPE ATTRIBUTE")
  }
| ALTER TYPE error // SHOW HELP: ALTER TYPE

opt_add_val_placement:
  BEFORE SCONST
  {
    $$.val = &ast.AlterTypeAddValuePlacement{
       Before: true,
       ExistingVal: $2,
    }
  }
| AFTER SCONST
  {
    $$.val = &ast.AlterTypeAddValuePlacement{
       Before: false,
       ExistingVal: $2,
    }
  }
| /* EMPTY */
  {
    $$.val = (*ast.AlterTypeAddValuePlacement)(nil)
  }

role_spec:
  non_reserved_word_or_sconst
| CURRENT_USER
| SESSION_USER

alter_attribute_action_list:
  alter_attribute_action
| alter_attribute_action_list ',' alter_attribute_action

alter_attribute_action:
  ADD ATTRIBUTE column_name type_name opt_collate opt_drop_behavior
| DROP ATTRIBUTE column_name opt_drop_behavior
| DROP ATTRIBUTE IF EXISTS column_name opt_drop_behavior
| ALTER ATTRIBUTE column_name TYPE type_name opt_collate opt_drop_behavior
| ALTER ATTRIBUTE column_name SET DATA TYPE type_name opt_collate opt_drop_behavior

// %Help: BACKUP - back up data to external storage
// %Category: CCL
// %Text:
// BACKUP <targets...> TO <location...>
//        [ AS OF SYSTEM TIME <expr> ]
//        [ INCREMENTAL FROM <location...> ]
//        [ WITH <option> [= <value>] [, ...] ]
//
// Targets:
//    Empty targets list: backup full cluster.
//    TABLE <pattern> [, ...]
//    DATABASE <databasename> [, ...]
//
// Location:
//    "[scheme]://[host]/[path to backup]?[parameters]"
//
// Options:
//    revision_history: enable revision history
//    encryption_passphrase="secret": encrypt backups
//    detached: execute backup job asynchronously, without waiting for its completion.
//
// %SeeAlso: RESTORE, WEBDOCS/backup.html
backup_stmt:
  BACKUP opt_backup_targets TO partitioned_backup opt_as_of_clause opt_incremental opt_with_backup_options
  {
    backup := &ast.Backup{
      To:              $4.partitionedBackup(),
      IncrementalFrom: $6.exprs(),
      AsOf:            $5.asOfClause(),
      Options:         *$7.backupOptions(),
    }

    tl := $2.targetListPtr()
    if tl == nil {
      backup.DescriptorCoverage = ast.AllDescriptors
    } else {
      backup.DescriptorCoverage = ast.RequestedDescriptors
      backup.Targets = *tl
    }

    $$.val = backup
  }
| BACKUP error // SHOW HELP: BACKUP

opt_backup_targets:
  /* EMPTY -- full cluster */
  {
    $$.val = (*ast.TargetList)(nil)
  }
| targets
  {
    t := $1.targetList()
    $$.val = &t
  }

// Optional backup options.
opt_with_backup_options:
  WITH backup_options_list
  {
    $$.val = $2.backupOptions()
  }
| WITH OPTIONS '(' backup_options_list ')'
  {
    $$.val = $4.backupOptions()
  }
| /* EMPTY */
  {
    $$.val = &ast.BackupOptions{}
  }

backup_options_list:
  // Require at least one option
  backup_options
  {
    $$.val = $1.backupOptions()
  }
| backup_options_list ',' backup_options
  {
    if err := $1.backupOptions().CombineWith($3.backupOptions()); err != nil {
      return setErr(sqllex, err)
    }
  }

// List of valid backup options.
backup_options:
  ENCRYPTION_PASSPHRASE '=' string_or_placeholder
  {
    $$.val = &ast.BackupOptions{EncryptionPassphrase: $3.expr()}
  }
| REVISION_HISTORY
  {
    $$.val = &ast.BackupOptions{CaptureRevisionHistory: true}
  }
| DETACHED
  {
    $$.val = &ast.BackupOptions{Detached: true}
  }

// %Help: CREATE SCHEDULE FOR BACKUP - backup data periodically
// %Category: CCL
// %Text:
// CREATE SCHEDULE [<description>]
// FOR BACKUP [<targets>] TO <location...>
// [WITH <backup_option>[=<value>] [, ...]]
// RECURRING [crontab|NEVER] [FULL BACKUP <crontab|ALWAYS>]
// [WITH EXPERIMENTAL SCHEDULE OPTIONS <schedule_option>[= <value>] [, ...] ]
//
// All backups run in UTC timezone.
//
// Description:
//   Optional description (or name) for this schedule
//
// Targets:
//   empty targets: Backup entire cluster
//   DATABASE <pattern> [, ...]: comma separated list of databases to backup.
//   TABLE <pattern> [, ...]: comma separated list of tables to backup.
//
// Location:
//   "[scheme]://[host]/[path prefix to backup]?[parameters]"
//   Backup schedule will create subdirectories under this location to store
//   full and periodic backups.
//
// WITH <options>:
//   Options specific to BACKUP: See BACKUP options
//
// RECURRING <crontab>:
//   The RECURRING expression specifies when we backup.  By default these are incremental
//   backups that capture changes since the last backup, writing to the "current" backup.
//
//   Schedule specified as a string in crontab format.
//   All times in UTC.
//     "5 0 * * *": run schedule 5 minutes past midnight.
//     "@daily": run daily, at midnight
//   See https://en.wikipedia.org/wiki/Cron
//
//   RECURRING NEVER indicates that the schedule is non recurring.
//   If, in addition to 'NEVER', the 'first_run' schedule option is specified,
//   then the schedule will execute once at that time (that is: it's a one-off execution).
//   If the 'first_run' is not specified, then the created scheduled will be in 'PAUSED' state,
//   and will need to be unpaused before it can execute.
//
// FULL BACKUP <crontab|ALWAYS>:
//   The optional FULL BACKUP '<cron expr>' clause specifies when we'll start a new full backup,
//   which becomes the "current" backup when complete.
//   If FULL BACKUP ALWAYS is specified, then the backups triggered by the RECURRING clause will
//   always be full backups. For free users, this is the only accepted value of FULL BACKUP.
//
//   If the FULL BACKUP clause is omitted, we will select a reasonable default:
//      * RECURRING <= 1 hour: we default to FULL BACKUP '@daily';
//      * RECURRING <= 1 day:  we default to FULL BACKUP '@weekly';
//      * Otherwise: we default to FULL BACKUP ALWAYS.
//
// EXPERIMENTAL SCHEDULE OPTIONS:
//   The schedule can be modified by specifying the following options (which are considered
//   to be experimental at this time):
//   * first_run=TIMESTAMPTZ:
//     execute the schedule at the specified time. If not specified, the default is to execute
//     the scheduled based on it's next RECURRING time.
//   * on_execution_failure='[retry|reschedule|pause]':
//     If an error occurs during the execution, handle the error based as:
//     * retry: retry execution right away
//     * reschedule: retry execution by rescheduling it based on its RECURRING expression.
//       This is the default.
//     * pause: pause this schedule.  Requires manual intervention to unpause.
//   * on_previous_running='[start|skip|wait]':
//     If the previous backup started by this schedule still running, handle this as:
//     * start: start this execution anyway, even if the previous one still running.
//     * skip: skip this execution, reschedule it based on RECURRING (or change_capture_period)
//       expression.
//     * wait: wait for the previous execution to complete.  This is the default.
//
// %SeeAlso: BACKUP
create_schedule_for_backup_stmt:
  CREATE SCHEDULE /*$3=*/opt_description FOR BACKUP /*$6=*/opt_backup_targets TO
  /*$8=*/partitioned_backup /*$9=*/opt_with_backup_options
  /*$10=*/cron_expr /*$11=*/opt_full_backup_clause /*$12=*/opt_with_schedule_options
  {
    $$.val = &ast.ScheduledBackup{
      ScheduleName:     $3.expr(),
      Recurrence:       $10.expr(),
      FullBackup:       $11.fullBackupClause(),
      To:               $8.partitionedBackup(),
      Targets:          $6.targetListPtr(),
      BackupOptions:    *($9.backupOptions()),
      ScheduleOptions:  $12.kvOptions(),
    }
  }
| CREATE SCHEDULE error  // SHOW HELP: CREATE SCHEDULE FOR BACKUP

opt_description:
  string_or_placeholder
| /* EMPTY */
  {
     $$.val = nil
  }


// sconst_or_placeholder matches a simple string, or a placeholder.
sconst_or_placeholder:
  SCONST
  {
    $$.val =  ast.NewStrVal($1)
  }
| PLACEHOLDER
  {
    p := $1.placeholder()
    sqllex.(*lexer).UpdateNumPlaceholders(p)
    $$.val = p
  }

cron_expr:
  RECURRING NEVER
  {
    $$.val = nil
  }
| RECURRING sconst_or_placeholder
  // Can't use string_or_placeholder here due to conflict on NEVER branch above
  // (is NEVER a keyword or a variable?).
  {
    $$.val = $2.expr()
  }

opt_full_backup_clause:
  FULL BACKUP sconst_or_placeholder
  // Can't use string_or_placeholder here due to conflict on ALWAYS branch below
  // (is ALWAYS a keyword or a variable?).
  {
    $$.val = &ast.FullBackupClause{Recurrence: $3.expr()}
  }
| FULL BACKUP ALWAYS
  {
    $$.val = &ast.FullBackupClause{AlwaysFull: true}
  }
| /* EMPTY */
  {
    $$.val = (*ast.FullBackupClause)(nil)
  }

opt_with_schedule_options:
  WITH EXPERIMENTAL SCHEDULE OPTIONS kv_option_list
  {
    $$.val = $5.kvOptions()
  }
| WITH EXPERIMENTAL SCHEDULE OPTIONS '(' kv_option_list ')'
  {
    $$.val = $6.kvOptions()
  }
| /* EMPTY */
  {
    $$.val = nil
  }


// %Help: RESTORE - restore data from external storage
// %Category: CCL
// %Text:
// RESTORE <targets...> FROM <location...>
//         [ AS OF SYSTEM TIME <expr> ]
//         [ WITH <option> [= <value>] [, ...] ]
//
// Targets:
//    TABLE <pattern> [, ...]
//    DATABASE <databasename> [, ...]
//
// Locations:
//    "[scheme]://[host]/[path to backup]?[parameters]"
//
// Options:
//    INTO_DB
//    SKIP_MISSING_FOREIGN_KEYS
//
// %SeeAlso: BACKUP, WEBDOCS/restore.html
restore_stmt:
  RESTORE FROM partitioned_backup_list opt_as_of_clause opt_with_options
  {
    $$.val = &ast.Restore{DescriptorCoverage: ast.AllDescriptors, From: $3.partitionedBackups(), AsOf: $4.asOfClause(), Options: $5.kvOptions()}
  }
| RESTORE targets FROM partitioned_backup_list opt_as_of_clause opt_with_options
  {
    $$.val = &ast.Restore{Targets: $2.targetList(), From: $4.partitionedBackups(), AsOf: $5.asOfClause(), Options: $6.kvOptions()}
  }
| RESTORE error // SHOW HELP: RESTORE

partitioned_backup:
  string_or_placeholder
  {
    $$.val = ast.PartitionedBackup{$1.expr()}
  }
| '(' string_or_placeholder_list ')'
  {
    $$.val = ast.PartitionedBackup($2.exprs())
  }

partitioned_backup_list:
  partitioned_backup
  {
    $$.val = []ast.PartitionedBackup{$1.partitionedBackup()}
  }
| partitioned_backup_list ',' partitioned_backup
  {
    $$.val = append($1.partitionedBackups(), $3.partitionedBackup())
  }

import_format:
  name
  {
    $$ = strings.ToUpper($1)
  }

// %Help: IMPORT - load data from file in a distributed manner
// %Category: CCL
// %Text:
// -- Import both schema and table data:
// IMPORT [ TABLE <tablename> FROM ]
//        <format> <datafile>
//        [ WITH <option> [= <value>] [, ...] ]
//
// -- Import using specific schema, use only table data from external file:
// IMPORT TABLE <tablename>
//        { ( <elements> ) | CREATE USING <schemafile> }
//        <format>
//        DATA ( <datafile> [, ...] )
//        [ WITH <option> [= <value>] [, ...] ]
//
// Formats:
//    CSV
//    DELIMITED
//    MYSQLDUMP
//    PGCOPY
//    PGDUMP
//
// Options:
//    distributed = '...'
//    sstsize = '...'
//    temp = '...'
//    delimiter = '...'      [CSV, PGCOPY-specific]
//    nullif = '...'         [CSV, PGCOPY-specific]
//    comment = '...'        [CSV-specific]
//
// %SeeAlso: CREATE TABLE
import_stmt:
 IMPORT import_format '(' string_or_placeholder ')' opt_with_options
  {
    /* SKIP DOC */
    $$.val = &ast.Import{Bundle: true, FileFormat: $2, Files: ast.Exprs{$4.expr()}, Options: $6.kvOptions()}
  }
| IMPORT import_format string_or_placeholder opt_with_options
  {
    $$.val = &ast.Import{Bundle: true, FileFormat: $2, Files: ast.Exprs{$3.expr()}, Options: $4.kvOptions()}
  }
| IMPORT TABLE table_name FROM import_format '(' string_or_placeholder ')' opt_with_options
  {
    /* SKIP DOC */
    name := $3.unresolvedObjectName().ToTableName()
    $$.val = &ast.Import{Bundle: true, Table: &name, FileFormat: $5, Files: ast.Exprs{$7.expr()}, Options: $9.kvOptions()}
  }
| IMPORT TABLE table_name FROM import_format string_or_placeholder opt_with_options
  {
    name := $3.unresolvedObjectName().ToTableName()
    $$.val = &ast.Import{Bundle: true, Table: &name, FileFormat: $5, Files: ast.Exprs{$6.expr()}, Options: $7.kvOptions()}
  }
| IMPORT TABLE table_name CREATE USING string_or_placeholder import_format DATA '(' string_or_placeholder_list ')' opt_with_options
  {
    name := $3.unresolvedObjectName().ToTableName()
    $$.val = &ast.Import{Table: &name, CreateFile: $6.expr(), FileFormat: $7, Files: $10.exprs(), Options: $12.kvOptions()}
  }
| IMPORT TABLE table_name '(' table_elem_list ')' import_format DATA '(' string_or_placeholder_list ')' opt_with_options
  {
    name := $3.unresolvedObjectName().ToTableName()
    $$.val = &ast.Import{Table: &name, CreateDefs: $5.tblDefs(), FileFormat: $7, Files: $10.exprs(), Options: $12.kvOptions()}
  }
| IMPORT INTO table_name '(' insert_column_list ')' import_format DATA '(' string_or_placeholder_list ')' opt_with_options
  {
    name := $3.unresolvedObjectName().ToTableName()
    $$.val = &ast.Import{Table: &name, Into: true, IntoCols: $5.nameList(), FileFormat: $7, Files: $10.exprs(), Options: $12.kvOptions()}
  }
| IMPORT INTO table_name import_format DATA '(' string_or_placeholder_list ')' opt_with_options
  {
    name := $3.unresolvedObjectName().ToTableName()
    $$.val = &ast.Import{Table: &name, Into: true, IntoCols: nil, FileFormat: $4, Files: $7.exprs(), Options: $9.kvOptions()}
  }
| IMPORT error // SHOW HELP: IMPORT

// %Help: EXPORT - export data to file in a distributed manner
// %Category: CCL
// %Text:
// EXPORT INTO <format> <datafile> [WITH <option> [= value] [,...]] FROM <query>
//
// Formats:
//    CSV
//
// Options:
//    delimiter = '...'   [CSV-specific]
//
// %SeeAlso: SELECT
export_stmt:
  EXPORT INTO import_format string_or_placeholder opt_with_options FROM select_stmt
  {
    $$.val = &ast.Export{Query: $7.slct(), FileFormat: $3, File: $4.expr(), Options: $5.kvOptions()}
  }
| EXPORT error // SHOW HELP: EXPORT

string_or_placeholder:
  non_reserved_word_or_sconst
  {
    $$.val = ast.NewStrVal($1)
  }
| PLACEHOLDER
  {
    p := $1.placeholder()
    sqllex.(*lexer).UpdateNumPlaceholders(p)
    $$.val = p
  }

string_or_placeholder_list:
  string_or_placeholder
  {
    $$.val = ast.Exprs{$1.expr()}
  }
| string_or_placeholder_list ',' string_or_placeholder
  {
    $$.val = append($1.exprs(), $3.expr())
  }

opt_incremental:
  INCREMENTAL FROM string_or_placeholder_list
  {
    $$.val = $3.exprs()
  }
| /* EMPTY */
  {
    $$.val = ast.Exprs(nil)
  }

kv_option:
  name '=' string_or_placeholder
  {
    $$.val = ast.KVOption{Key: ast.Name($1), Value: $3.expr()}
  }
|  name
  {
    $$.val = ast.KVOption{Key: ast.Name($1)}
  }
|  SCONST '=' string_or_placeholder
  {
    $$.val = ast.KVOption{Key: ast.Name($1), Value: $3.expr()}
  }
|  SCONST
  {
    $$.val = ast.KVOption{Key: ast.Name($1)}
  }

kv_option_list:
  kv_option
  {
    $$.val = []ast.KVOption{$1.kvOption()}
  }
|  kv_option_list ',' kv_option
  {
    $$.val = append($1.kvOptions(), $3.kvOption())
  }

opt_with_options:
  WITH kv_option_list
  {
    $$.val = $2.kvOptions()
  }
| WITH OPTIONS '(' kv_option_list ')'
  {
    $$.val = $4.kvOptions()
  }
| /* EMPTY */
  {
    $$.val = nil
  }

copy_from_stmt:
  COPY table_name opt_column_list FROM STDIN opt_with_options
  {
    name := $2.unresolvedObjectName().ToTableName()
    $$.val = &ast.CopyFrom{
       Table: name,
       Columns: $3.nameList(),
       Stdin: true,
       Options: $6.kvOptions(),
    }
  }

// %Help: CANCEL
// %Category: Group
// %Text: CANCEL JOBS, CANCEL QUERIES, CANCEL SESSIONS
cancel_stmt:
  cancel_jobs_stmt     // EXTEND WITH HELP: CANCEL JOBS
| cancel_queries_stmt  // EXTEND WITH HELP: CANCEL QUERIES
| cancel_sessions_stmt // EXTEND WITH HELP: CANCEL SESSIONS
| CANCEL error         // SHOW HELP: CANCEL

// %Help: CANCEL JOBS - cancel background jobs
// %Category: Misc
// %Text:
// CANCEL JOBS <selectclause>
// CANCEL JOB <jobid>
// %SeeAlso: SHOW JOBS, PAUSE JOBS, RESUME JOBS
cancel_jobs_stmt:
  CANCEL JOB a_expr
  {
    $$.val = &ast.ControlJobs{
      Jobs: &ast.Select{
        Select: &ast.ValuesClause{Rows: []ast.Exprs{ast.Exprs{$3.expr()}}},
      },
      Command: ast.CancelJob,
    }
  }
| CANCEL JOB error // SHOW HELP: CANCEL JOBS
| CANCEL JOBS select_stmt
  {
    $$.val = &ast.ControlJobs{Jobs: $3.slct(), Command: ast.CancelJob}
  }
| CANCEL JOBS error // SHOW HELP: CANCEL JOBS

// %Help: CANCEL QUERIES - cancel running queries
// %Category: Misc
// %Text:
// CANCEL QUERIES [IF EXISTS] <selectclause>
// CANCEL QUERY [IF EXISTS] <expr>
// %SeeAlso: SHOW QUERIES
cancel_queries_stmt:
  CANCEL QUERY a_expr
  {
    $$.val = &ast.CancelQueries{
      Queries: &ast.Select{
        Select: &ast.ValuesClause{Rows: []ast.Exprs{ast.Exprs{$3.expr()}}},
      },
      IfExists: false,
    }
  }
| CANCEL QUERY IF EXISTS a_expr
  {
    $$.val = &ast.CancelQueries{
      Queries: &ast.Select{
        Select: &ast.ValuesClause{Rows: []ast.Exprs{ast.Exprs{$5.expr()}}},
      },
      IfExists: true,
    }
  }
| CANCEL QUERY error // SHOW HELP: CANCEL QUERIES
| CANCEL QUERIES select_stmt
  {
    $$.val = &ast.CancelQueries{Queries: $3.slct(), IfExists: false}
  }
| CANCEL QUERIES IF EXISTS select_stmt
  {
    $$.val = &ast.CancelQueries{Queries: $5.slct(), IfExists: true}
  }
| CANCEL QUERIES error // SHOW HELP: CANCEL QUERIES

// %Help: CANCEL SESSIONS - cancel open sessions
// %Category: Misc
// %Text:
// CANCEL SESSIONS [IF EXISTS] <selectclause>
// CANCEL SESSION [IF EXISTS] <sessionid>
// %SeeAlso: SHOW SESSIONS
cancel_sessions_stmt:
  CANCEL SESSION a_expr
  {
   $$.val = &ast.CancelSessions{
      Sessions: &ast.Select{
        Select: &ast.ValuesClause{Rows: []ast.Exprs{ast.Exprs{$3.expr()}}},
      },
      IfExists: false,
    }
  }
| CANCEL SESSION IF EXISTS a_expr
  {
   $$.val = &ast.CancelSessions{
      Sessions: &ast.Select{
        Select: &ast.ValuesClause{Rows: []ast.Exprs{ast.Exprs{$5.expr()}}},
      },
      IfExists: true,
    }
  }
| CANCEL SESSION error // SHOW HELP: CANCEL SESSIONS
| CANCEL SESSIONS select_stmt
  {
    $$.val = &ast.CancelSessions{Sessions: $3.slct(), IfExists: false}
  }
| CANCEL SESSIONS IF EXISTS select_stmt
  {
    $$.val = &ast.CancelSessions{Sessions: $5.slct(), IfExists: true}
  }
| CANCEL SESSIONS error // SHOW HELP: CANCEL SESSIONS

comment_stmt:
  COMMENT ON DATABASE database_name IS comment_text
  {
    $$.val = &ast.CommentOnDatabase{Name: ast.Name($4), Comment: $6.strPtr()}
  }
| COMMENT ON TABLE table_name IS comment_text
  {
    $$.val = &ast.CommentOnTable{Table: $4.unresolvedObjectName(), Comment: $6.strPtr()}
  }
| COMMENT ON COLUMN column_path IS comment_text
  {
    varName, err := $4.unresolvedName().NormalizeVarName()
    if err != nil {
      return setErr(sqllex, err)
    }
    columnItem, ok := varName.(*ast.ColumnItem)
    if !ok {
      sqllex.Error(fmt.Sprintf("invalid column name: %q", ast.ErrString($4.unresolvedName())))
            return 1
    }
    $$.val = &ast.CommentOnColumn{ColumnItem: columnItem, Comment: $6.strPtr()}
  }
| COMMENT ON INDEX table_index_name IS comment_text
  {
    $$.val = &ast.CommentOnIndex{Index: $4.tableIndexName(), Comment: $6.strPtr()}
  }

comment_text:
  SCONST
  {
    t := $1
    $$.val = &t
  }
| NULL
  {
    var str *string
    $$.val = str
  }

// %Help: CREATE
// %Category: Group
// %Text:
// CREATE DATABASE, CREATE TABLE, CREATE INDEX, CREATE TABLE AS,
// CREATE USER, CREATE VIEW, CREATE SEQUENCE, CREATE STATISTICS,
// CREATE ROLE, CREATE TYPE
create_stmt:
  create_role_stmt     // EXTEND WITH HELP: CREATE ROLE
| create_ddl_stmt      // help texts in sub-rule
| create_stats_stmt    // EXTEND WITH HELP: CREATE STATISTICS
| create_schedule_for_backup_stmt   // EXTEND WITH HELP: CREATE SCHEDULE FOR BACKUP
| create_unsupported   {}
| CREATE error         // SHOW HELP: CREATE

create_unsupported:
  CREATE AGGREGATE error { return unimplemented(sqllex, "create aggregate") }
| CREATE CAST error { return unimplemented(sqllex, "create cast") }
| CREATE CONSTRAINT TRIGGER error { return unimplementedWithIssueDetail(sqllex, 28296, "create constraint") }
| CREATE CONVERSION error { return unimplemented(sqllex, "create conversion") }
| CREATE DEFAULT CONVERSION error { return unimplemented(sqllex, "create def conv") }
| CREATE EXTENSION IF NOT EXISTS name error { return unimplemented(sqllex, "create extension " + $6) }
| CREATE EXTENSION name error { return unimplemented(sqllex, "create extension " + $3) }
| CREATE FOREIGN TABLE error { return unimplemented(sqllex, "create foreign table") }
| CREATE FOREIGN DATA error { return unimplemented(sqllex, "create fdw") }
| CREATE FUNCTION error { return unimplementedWithIssueDetail(sqllex, 17511, "create function") }
| CREATE OR REPLACE FUNCTION error { return unimplementedWithIssueDetail(sqllex, 17511, "create function") }
| CREATE opt_or_replace opt_trusted opt_procedural LANGUAGE name error { return unimplementedWithIssueDetail(sqllex, 17511, "create language " + $6) }
| CREATE MATERIALIZED VIEW error { return unimplementedWithIssue(sqllex, 41649) }
| CREATE OPERATOR error { return unimplemented(sqllex, "create operator") }
| CREATE PUBLICATION error { return unimplemented(sqllex, "create publication") }
| CREATE opt_or_replace RULE error { return unimplemented(sqllex, "create rule") }
| CREATE SERVER error { return unimplemented(sqllex, "create server") }
| CREATE SUBSCRIPTION error { return unimplemented(sqllex, "create subscription") }
| CREATE TEXT error { return unimplementedWithIssueDetail(sqllex, 7821, "create text") }
| CREATE TRIGGER error { return unimplementedWithIssueDetail(sqllex, 28296, "create") }

opt_or_replace:
  OR REPLACE {}
| /* EMPTY */ {}

opt_trusted:
  TRUSTED {}
| /* EMPTY */ {}

opt_procedural:
  PROCEDURAL {}
| /* EMPTY */ {}

drop_unsupported:
  DROP AGGREGATE error { return unimplemented(sqllex, "drop aggregate") }
| DROP CAST error { return unimplemented(sqllex, "drop cast") }
| DROP COLLATION error { return unimplemented(sqllex, "drop collation") }
| DROP CONVERSION error { return unimplemented(sqllex, "drop conversion") }
| DROP DOMAIN error { return unimplementedWithIssueDetail(sqllex, 27796, "drop") }
| DROP EXTENSION IF EXISTS name error { return unimplemented(sqllex, "drop extension " + $5) }
| DROP EXTENSION name error { return unimplemented(sqllex, "drop extension " + $3) }
| DROP FOREIGN TABLE error { return unimplemented(sqllex, "drop foreign table") }
| DROP FOREIGN DATA error { return unimplemented(sqllex, "drop fdw") }
| DROP FUNCTION error { return unimplementedWithIssueDetail(sqllex, 17511, "drop function") }
| DROP opt_procedural LANGUAGE name error { return unimplementedWithIssueDetail(sqllex, 17511, "drop language " + $4) }
| DROP OPERATOR error { return unimplemented(sqllex, "drop operator") }
| DROP PUBLICATION error { return unimplemented(sqllex, "drop publication") }
| DROP RULE error { return unimplemented(sqllex, "drop rule") }
| DROP SCHEMA error { return unimplementedWithIssueDetail(sqllex, 26443, "drop") }
| DROP SERVER error { return unimplemented(sqllex, "drop server") }
| DROP SUBSCRIPTION error { return unimplemented(sqllex, "drop subscription") }
| DROP TEXT error { return unimplementedWithIssueDetail(sqllex, 7821, "drop text") }
| DROP TRIGGER error { return unimplementedWithIssueDetail(sqllex, 28296, "drop") }

create_ddl_stmt:
  create_changefeed_stmt
| create_database_stmt // EXTEND WITH HELP: CREATE DATABASE
| create_index_stmt    // EXTEND WITH HELP: CREATE INDEX
| create_schema_stmt   // EXTEND WITH HELP: CREATE SCHEMA
| create_table_stmt    // EXTEND WITH HELP: CREATE TABLE
| create_table_as_stmt // EXTEND WITH HELP: CREATE TABLE
// Error case for both CREATE TABLE and CREATE TABLE ... AS in one
| CREATE opt_temp_create_table TABLE error   // SHOW HELP: CREATE TABLE
| create_type_stmt     // EXTEND WITH HELP: CREATE TYPE
| create_view_stmt     // EXTEND WITH HELP: CREATE VIEW
| create_sequence_stmt // EXTEND WITH HELP: CREATE SEQUENCE

// %Help: CREATE STATISTICS - create a new table statistic
// %Category: Misc
// %Text:
// CREATE STATISTICS <statisticname>
//   [ON <colname> [, ...]]
//   FROM <tablename> [AS OF SYSTEM TIME <expr>]
create_stats_stmt:
  CREATE STATISTICS statistics_name opt_stats_columns FROM create_stats_target opt_create_stats_options
  {
    $$.val = &ast.CreateStats{
      Name: ast.Name($3),
      ColumnNames: $4.nameList(),
      Table: $6.tblExpr(),
      Options: *$7.createStatsOptions(),
    }
  }
| CREATE STATISTICS error // SHOW HELP: CREATE STATISTICS

opt_stats_columns:
  ON name_list
  {
    $$.val = $2.nameList()
  }
| /* EMPTY */
  {
    $$.val = ast.NameList(nil)
  }

create_stats_target:
  table_name
  {
    $$.val = $1.unresolvedObjectName()
  }
| '[' iconst64 ']'
  {
    /* SKIP DOC */
    $$.val = &ast.TableRef{
      TableID: $2.int64(),
    }
  }

opt_create_stats_options:
  WITH OPTIONS create_stats_option_list
  {
    /* SKIP DOC */
    $$.val = $3.createStatsOptions()
  }
// Allow AS OF SYSTEM TIME without WITH OPTIONS, for consistency with other
// statements.
| as_of_clause
  {
    $$.val = &ast.CreateStatsOptions{
      AsOf: $1.asOfClause(),
    }
  }
| /* EMPTY */
  {
    $$.val = &ast.CreateStatsOptions{}
  }

create_stats_option_list:
  create_stats_option
  {
    $$.val = $1.createStatsOptions()
  }
| create_stats_option_list create_stats_option
  {
    a := $1.createStatsOptions()
    b := $2.createStatsOptions()
    if err := a.CombineWith(b); err != nil {
      return setErr(sqllex, err)
    }
    $$.val = a
  }

create_stats_option:
  THROTTLING FCONST
  {
    /* SKIP DOC */
    value, _ := constant.Float64Val($2.numVal().AsConstantValue())
    if value < 0.0 || value >= 1.0 {
      sqllex.Error("THROTTLING fraction must be between 0 and 1")
      return 1
    }
    $$.val = &ast.CreateStatsOptions{
      Throttling: value,
    }
  }
| as_of_clause
  {
    $$.val = &ast.CreateStatsOptions{
      AsOf: $1.asOfClause(),
    }
  }

create_changefeed_stmt:
  CREATE CHANGEFEED FOR changefeed_targets opt_changefeed_sink opt_with_options
  {
    $$.val = &ast.CreateChangefeed{
      Targets: $4.targetList(),
      SinkURI: $5.expr(),
      Options: $6.kvOptions(),
    }
  }
| EXPERIMENTAL CHANGEFEED FOR changefeed_targets opt_with_options
  {
    /* SKIP DOC */
    $$.val = &ast.CreateChangefeed{
      Targets: $4.targetList(),
      Options: $5.kvOptions(),
    }
  }

changefeed_targets:
  single_table_pattern_list
  {
    $$.val = ast.TargetList{Tables: $1.tablePatterns()}
  }
| TABLE single_table_pattern_list
  {
    $$.val = ast.TargetList{Tables: $2.tablePatterns()}
  }

single_table_pattern_list:
  table_name
  {
    $$.val = ast.TablePatterns{$1.unresolvedObjectName().ToUnresolvedName()}
  }
| single_table_pattern_list ',' table_name
  {
    $$.val = append($1.tablePatterns(), $3.unresolvedObjectName().ToUnresolvedName())
  }


opt_changefeed_sink:
  INTO string_or_placeholder
  {
    $$.val = $2.expr()
  }
| /* EMPTY */
  {
    /* SKIP DOC */
    $$.val = nil
  }

// %Help: DELETE - delete rows from a table
// %Category: DML
// %Text: DELETE FROM <tablename> [WHERE <expr>]
//               [ORDER BY <exprs...>]
//               [LIMIT <expr>]
//               [RETURNING <exprs...>]
// %SeeAlso: WEBDOCS/delete.html
delete_stmt:
  opt_with_clause DELETE FROM table_expr_opt_alias_idx opt_using_clause opt_where_clause opt_sort_clause opt_limit_clause returning_clause
  {
    $$.val = &ast.Delete{
      With: $1.with(),
      Table: $4.tblExpr(),
      Where: ast.NewWhere(ast.AstWhere, $6.expr()),
      OrderBy: $7.orderBy(),
      Limit: $8.limit(),
      Returning: $9.retClause(),
    }
  }
| opt_with_clause DELETE error // SHOW HELP: DELETE

opt_using_clause:
  USING from_list { return unimplementedWithIssueDetail(sqllex, 40963, "delete using") }
| /* EMPTY */ { }


// %Help: DISCARD - reset the session to its initial state
// %Category: Cfg
// %Text: DISCARD ALL
discard_stmt:
  DISCARD ALL
  {
    $$.val = &ast.Discard{Mode: ast.DiscardModeAll}
  }
| DISCARD PLANS { return unimplemented(sqllex, "discard plans") }
| DISCARD SEQUENCES { return unimplemented(sqllex, "discard sequences") }
| DISCARD TEMP { return unimplemented(sqllex, "discard temp") }
| DISCARD TEMPORARY { return unimplemented(sqllex, "discard temp") }
| DISCARD error // SHOW HELP: DISCARD

// %Help: DROP
// %Category: Group
// %Text:
// DROP DATABASE, DROP INDEX, DROP TABLE, DROP VIEW, DROP SEQUENCE,
// DROP USER, DROP ROLE, DROP TYPE
drop_stmt:
  drop_ddl_stmt      // help texts in sub-rule
| drop_role_stmt     // EXTEND WITH HELP: DROP ROLE
| drop_unsupported   {}
| DROP error         // SHOW HELP: DROP

drop_ddl_stmt:
  drop_database_stmt // EXTEND WITH HELP: DROP DATABASE
| drop_index_stmt    // EXTEND WITH HELP: DROP INDEX
| drop_table_stmt    // EXTEND WITH HELP: DROP TABLE
| drop_view_stmt     // EXTEND WITH HELP: DROP VIEW
| drop_sequence_stmt // EXTEND WITH HELP: DROP SEQUENCE
| drop_type_stmt     // EXTEND WITH HELP: DROP TYPE

// %Help: DROP VIEW - remove a view
// %Category: DDL
// %Text: DROP VIEW [IF EXISTS] <tablename> [, ...] [CASCADE | RESTRICT]
// %SeeAlso: WEBDOCS/drop-index.html
drop_view_stmt:
  DROP VIEW table_name_list opt_drop_behavior
  {
    $$.val = &ast.DropView{Names: $3.tableNames(), IfExists: false, DropBehavior: $4.dropBehavior()}
  }
| DROP VIEW IF EXISTS table_name_list opt_drop_behavior
  {
    $$.val = &ast.DropView{Names: $5.tableNames(), IfExists: true, DropBehavior: $6.dropBehavior()}
  }
| DROP VIEW error // SHOW HELP: DROP VIEW

// %Help: DROP SEQUENCE - remove a sequence
// %Category: DDL
// %Text: DROP SEQUENCE [IF EXISTS] <sequenceName> [, ...] [CASCADE | RESTRICT]
// %SeeAlso: DROP
drop_sequence_stmt:
  DROP SEQUENCE table_name_list opt_drop_behavior
  {
    $$.val = &ast.DropSequence{Names: $3.tableNames(), IfExists: false, DropBehavior: $4.dropBehavior()}
  }
| DROP SEQUENCE IF EXISTS table_name_list opt_drop_behavior
  {
    $$.val = &ast.DropSequence{Names: $5.tableNames(), IfExists: true, DropBehavior: $6.dropBehavior()}
  }
| DROP SEQUENCE error // SHOW HELP: DROP VIEW

// %Help: DROP TABLE - remove a table
// %Category: DDL
// %Text: DROP TABLE [IF EXISTS] <tablename> [, ...] [CASCADE | RESTRICT]
// %SeeAlso: WEBDOCS/drop-table.html
drop_table_stmt:
  DROP TABLE table_name_list opt_drop_behavior
  {
    $$.val = &ast.DropTable{Names: $3.tableNames(), IfExists: false, DropBehavior: $4.dropBehavior()}
  }
| DROP TABLE IF EXISTS table_name_list opt_drop_behavior
  {
    $$.val = &ast.DropTable{Names: $5.tableNames(), IfExists: true, DropBehavior: $6.dropBehavior()}
  }
| DROP TABLE error // SHOW HELP: DROP TABLE

// %Help: DROP INDEX - remove an index
// %Category: DDL
// %Text: DROP INDEX [CONCURRENTLY] [IF EXISTS] <idxname> [, ...] [CASCADE | RESTRICT]
// %SeeAlso: WEBDOCS/drop-index.html
drop_index_stmt:
  DROP INDEX opt_concurrently table_index_name_list opt_drop_behavior
  {
    $$.val = &ast.DropIndex{
      IndexList: $4.newTableIndexNames(),
      IfExists: false,
      DropBehavior: $5.dropBehavior(),
      Concurrently: $3.bool(),
    }
  }
| DROP INDEX opt_concurrently IF EXISTS table_index_name_list opt_drop_behavior
  {
    $$.val = &ast.DropIndex{
      IndexList: $6.newTableIndexNames(),
      IfExists: true,
      DropBehavior: $7.dropBehavior(),
      Concurrently: $3.bool(),
    }
  }
| DROP INDEX error // SHOW HELP: DROP INDEX

// %Help: DROP DATABASE - remove a database
// %Category: DDL
// %Text: DROP DATABASE [IF EXISTS] <databasename> [CASCADE | RESTRICT]
// %SeeAlso: WEBDOCS/drop-database.html
drop_database_stmt:
  DROP DATABASE database_name opt_drop_behavior
  {
    $$.val = &ast.DropDatabase{
      Name: ast.Name($3),
      IfExists: false,
      DropBehavior: $4.dropBehavior(),
    }
  }
| DROP DATABASE IF EXISTS database_name opt_drop_behavior
  {
    $$.val = &ast.DropDatabase{
      Name: ast.Name($5),
      IfExists: true,
      DropBehavior: $6.dropBehavior(),
    }
  }
| DROP DATABASE error // SHOW HELP: DROP DATABASE

// %Help: DROP TYPE - remove a type
// %Category: DDL
// %Text: DROP TYPE [IF EXISTS] <type_name> [, ...] [CASCASE | RESTRICT]
drop_type_stmt:
  DROP TYPE type_name_list opt_drop_behavior
  {
    $$.val = &ast.DropType{
      Names: $3.unresolvedObjectNames(),
      IfExists: false,
      DropBehavior: $4.dropBehavior(),
    }
  }
| DROP TYPE IF EXISTS type_name_list opt_drop_behavior
  {
    $$.val = &ast.DropType{
      Names: $5.unresolvedObjectNames(),
      IfExists: true,
      DropBehavior: $6.dropBehavior(),
    }
  }
| DROP TYPE error // SHOW HELP: DROP TYPE


type_name_list:
  type_name
  {
    $$.val = []*ast.UnresolvedObjectName{$1.unresolvedObjectName()}
  }
| type_name_list ',' type_name
  {
    $$.val = append($1.unresolvedObjectNames(), $3.unresolvedObjectName())
  }


// %Help: DROP ROLE - remove a user
// %Category: Priv
// %Text: DROP ROLE [IF EXISTS] <user> [, ...]
// %SeeAlso: CREATE ROLE, SHOW ROLE
drop_role_stmt:
  DROP role_or_group_or_user string_or_placeholder_list
  {
    $$.val = &ast.DropRole{Names: $3.exprs(), IfExists: false, IsRole: $2.bool()}
  }
| DROP role_or_group_or_user IF EXISTS string_or_placeholder_list
  {
    $$.val = &ast.DropRole{Names: $5.exprs(), IfExists: true, IsRole: $2.bool()}
  }
| DROP role_or_group_or_user error // SHOW HELP: DROP ROLE

table_name_list:
  table_name
  {
    name := $1.unresolvedObjectName().ToTableName()
    $$.val = ast.TableNames{name}
  }
| table_name_list ',' table_name
  {
    name := $3.unresolvedObjectName().ToTableName()
    $$.val = append($1.tableNames(), name)
  }

// %Help: ANALYZE - collect table statistics
// %Category: Misc
// %Text:
// ANALYZE <tablename>
//
// %SeeAlso: CREATE STATISTICS
analyze_stmt:
  ANALYZE analyze_target
  {
    $$.val = &ast.Analyze{
      Table: $2.tblExpr(),
    }
  }
| ANALYZE error // SHOW HELP: ANALYZE
| ANALYSE analyze_target
  {
    $$.val = &ast.Analyze{
      Table: $2.tblExpr(),
    }
  }
| ANALYSE error // SHOW HELP: ANALYZE

analyze_target:
  table_name
  {
    $$.val = $1.unresolvedObjectName()
  }

// %Help: EXPLAIN - show the logical plan of a query
// %Category: Misc
// %Text:
// EXPLAIN <statement>
// EXPLAIN ([PLAN ,] <planoptions...> ) <statement>
// EXPLAIN [ANALYZE] (DISTSQL) <statement>
// EXPLAIN ANALYZE [(DISTSQL)] <statement>
//
// Explainable statements:
//     SELECT, CREATE, DROP, ALTER, INSERT, UPSERT, UPDATE, DELETE,
//     SHOW, EXPLAIN
//
// Plan options:
//     TYPES, VERBOSE, OPT
//
// %SeeAlso: WEBDOCS/explain.html
explain_stmt:
  EXPLAIN preparable_stmt
  {
    var err error
    $$.val, err = ast.MakeExplain(nil /* options */, $2.stmt())
    if err != nil {
      return setErr(sqllex, err)
    }
  }
| EXPLAIN error // SHOW HELP: EXPLAIN
| EXPLAIN '(' explain_option_list ')' preparable_stmt
  {
    var err error
    $$.val, err = ast.MakeExplain($3.strs(), $5.stmt())
    if err != nil {
      return setErr(sqllex, err)
    }
  }
| EXPLAIN ANALYZE preparable_stmt
  {
    var err error
    $$.val, err = ast.MakeExplain([]string{"DISTSQL", "ANALYZE"}, $3.stmt())
    if err != nil {
      return setErr(sqllex, err)
    }
  }
| EXPLAIN ANALYSE preparable_stmt
  {
    var err error
    $$.val, err = ast.MakeExplain([]string{"DISTSQL", "ANALYZE"}, $3.stmt())
    if err != nil {
      return setErr(sqllex, err)
    }
  }
| EXPLAIN ANALYZE '(' explain_option_list ')' preparable_stmt
  {
    var err error
    $$.val, err = ast.MakeExplain(append($4.strs(), "ANALYZE"), $6.stmt())
    if err != nil {
      return setErr(sqllex, err)
    }
  }
| EXPLAIN ANALYSE '(' explain_option_list ')' preparable_stmt
  {
    var err error
    $$.val, err = ast.MakeExplain(append($4.strs(), "ANALYZE"), $6.stmt())
    if err != nil {
      return setErr(sqllex, err)
    }
  }
// This second error rule is necessary, because otherwise
// preparable_stmt also provides "selectclause := '(' error ..." and
// cause a help text for the select clause, which will be confusing in
// the context of EXPLAIN.
| EXPLAIN '(' error // SHOW HELP: EXPLAIN

preparable_stmt:
  alter_stmt        // help texts in sub-rule
| backup_stmt       // EXTEND WITH HELP: BACKUP
| cancel_stmt       // help texts in sub-rule
| create_stmt       // help texts in sub-rule
| delete_stmt       // EXTEND WITH HELP: DELETE
| drop_stmt         // help texts in sub-rule
| explain_stmt      // EXTEND WITH HELP: EXPLAIN
| import_stmt       // EXTEND WITH HELP: IMPORT
| insert_stmt       // EXTEND WITH HELP: INSERT
| pause_stmt        // EXTEND WITH HELP: PAUSE JOBS
| reset_stmt        // help texts in sub-rule
| restore_stmt      // EXTEND WITH HELP: RESTORE
| resume_stmt       // EXTEND WITH HELP: RESUME JOBS
| export_stmt       // EXTEND WITH HELP: EXPORT
| scrub_stmt        // help texts in sub-rule
| select_stmt       // help texts in sub-rule
  {
    $$.val = $1.slct()
  }
| preparable_set_stmt // help texts in sub-rule
| show_stmt         // help texts in sub-rule
| truncate_stmt     // EXTEND WITH HELP: TRUNCATE
| update_stmt       // EXTEND WITH HELP: UPDATE
| upsert_stmt       // EXTEND WITH HELP: UPSERT

// These are statements that can be used as a data source using the special
// syntax with brackets. These are a subset of preparable_stmt.
row_source_extension_stmt:
  delete_stmt       // EXTEND WITH HELP: DELETE
| explain_stmt      // EXTEND WITH HELP: EXPLAIN
| insert_stmt       // EXTEND WITH HELP: INSERT
| select_stmt       // help texts in sub-rule
  {
    $$.val = $1.slct()
  }
| show_stmt         // help texts in sub-rule
| update_stmt       // EXTEND WITH HELP: UPDATE
| upsert_stmt       // EXTEND WITH HELP: UPSERT

explain_option_list:
  explain_option_name
  {
    $$.val = []string{$1}
  }
| explain_option_list ',' explain_option_name
  {
    $$.val = append($1.strs(), $3)
  }

// %Help: PREPARE - prepare a statement for later execution
// %Category: Misc
// %Text: PREPARE <name> [ ( <types...> ) ] AS <query>
// %SeeAlso: EXECUTE, DEALLOCATE, DISCARD
prepare_stmt:
  PREPARE table_alias_name prep_type_clause AS preparable_stmt
  {
    $$.val = &ast.Prepare{
      Name: ast.Name($2),
      Types: $3.typeReferences(),
      Statement: $5.stmt(),
    }
  }
| PREPARE table_alias_name prep_type_clause AS OPT PLAN SCONST
  {
    /* SKIP DOC */
    $$.val = &ast.Prepare{
      Name: ast.Name($2),
      Types: $3.typeReferences(),
      Statement: &ast.CannedOptPlan{Plan: $7},
    }
  }
| PREPARE error // SHOW HELP: PREPARE

prep_type_clause:
  '(' type_list ')'
  {
    $$.val = $2.typeReferences();
  }
| /* EMPTY */
  {
    $$.val = []ast.ResolvableTypeReference(nil)
  }

// %Help: EXECUTE - execute a statement prepared previously
// %Category: Misc
// %Text: EXECUTE <name> [ ( <exprs...> ) ]
// %SeeAlso: PREPARE, DEALLOCATE, DISCARD
execute_stmt:
  EXECUTE table_alias_name execute_param_clause
  {
    $$.val = &ast.Execute{
      Name: ast.Name($2),
      Params: $3.exprs(),
    }
  }
| EXECUTE table_alias_name execute_param_clause DISCARD ROWS
  {
    /* SKIP DOC */
    $$.val = &ast.Execute{
      Name: ast.Name($2),
      Params: $3.exprs(),
      DiscardRows: true,
    }
  }
| EXECUTE error // SHOW HELP: EXECUTE

execute_param_clause:
  '(' expr_list ')'
  {
    $$.val = $2.exprs()
  }
| /* EMPTY */
  {
    $$.val = ast.Exprs(nil)
  }

// %Help: DEALLOCATE - remove a prepared statement
// %Category: Misc
// %Text: DEALLOCATE [PREPARE] { <name> | ALL }
// %SeeAlso: PREPARE, EXECUTE, DISCARD
deallocate_stmt:
  DEALLOCATE name
  {
    $$.val = &ast.Deallocate{Name: ast.Name($2)}
  }
| DEALLOCATE PREPARE name
  {
    $$.val = &ast.Deallocate{Name: ast.Name($3)}
  }
| DEALLOCATE ALL
  {
    $$.val = &ast.Deallocate{}
  }
| DEALLOCATE PREPARE ALL
  {
    $$.val = &ast.Deallocate{}
  }
| DEALLOCATE error // SHOW HELP: DEALLOCATE

// %Help: GRANT - define access privileges and role memberships
// %Category: Priv
// %Text:
// Grant privileges:
//   GRANT {ALL | <privileges...> } ON <targets...> TO <grantees...>
// Grant role membership (CCL only):
//   GRANT <roles...> TO <grantees...> [WITH ADMIN OPTION]
//
// Privileges:
//   CREATE, DROP, GRANT, SELECT, INSERT, DELETE, UPDATE
//
// Targets:
//   DATABASE <databasename> [, ...]
//   [TABLE] [<databasename> .] { <tablename> | * } [, ...]
//
// %SeeAlso: REVOKE, WEBDOCS/grant.html
grant_stmt:
  GRANT privileges ON targets TO name_list
  {
    $$.val = &ast.Grant{Privileges: $2.privilegeList(), Grantees: $6.nameList(), Targets: $4.targetList()}
  }
| GRANT privilege_list TO name_list
  {
    $$.val = &ast.GrantRole{Roles: $2.nameList(), Members: $4.nameList(), AdminOption: false}
  }
| GRANT privilege_list TO name_list WITH ADMIN OPTION
  {
    $$.val = &ast.GrantRole{Roles: $2.nameList(), Members: $4.nameList(), AdminOption: true}
  }
| GRANT error // SHOW HELP: GRANT

// %Help: REVOKE - remove access privileges and role memberships
// %Category: Priv
// %Text:
// Revoke privileges:
//   REVOKE {ALL | <privileges...> } ON <targets...> FROM <grantees...>
// Revoke role membership (CCL only):
//   REVOKE [ADMIN OPTION FOR] <roles...> FROM <grantees...>
//
// Privileges:
//   CREATE, DROP, GRANT, SELECT, INSERT, DELETE, UPDATE
//
// Targets:
//   DATABASE <databasename> [, <databasename>]...
//   [TABLE] [<databasename> .] { <tablename> | * } [, ...]
//
// %SeeAlso: GRANT, WEBDOCS/revoke.html
revoke_stmt:
  REVOKE privileges ON targets FROM name_list
  {
    $$.val = &ast.Revoke{Privileges: $2.privilegeList(), Grantees: $6.nameList(), Targets: $4.targetList()}
  }
| REVOKE privilege_list FROM name_list
  {
    $$.val = &ast.RevokeRole{Roles: $2.nameList(), Members: $4.nameList(), AdminOption: false }
  }
| REVOKE ADMIN OPTION FOR privilege_list FROM name_list
  {
    $$.val = &ast.RevokeRole{Roles: $5.nameList(), Members: $7.nameList(), AdminOption: true }
  }
| REVOKE error // SHOW HELP: REVOKE

// ALL is always by itself.
privileges:
  ALL
  {
    $$.val = privilege.List{privilege.ALL}
  }
  | privilege_list
  {
     privList, err := privilege.ListFromStrings($1.nameList().ToStrings())
     if err != nil {
       return setErr(sqllex, err)
     }
     $$.val = privList
  }

privilege_list:
  privilege
  {
    $$.val = ast.NameList{ast.Name($1)}
  }
| privilege_list ',' privilege
  {
    $$.val = append($1.nameList(), ast.Name($3))
  }

// Privileges are parsed at execution time to avoid having to make them reserved.
// Any privileges above `col_name_keyword` should be listed here.
// The full list is in sql/privilege/privilege.go.
privilege:
  name
| CREATE
| GRANT
| SELECT

reset_stmt:
  reset_session_stmt  // EXTEND WITH HELP: RESET
| reset_csetting_stmt // EXTEND WITH HELP: RESET CLUSTER SETTING

// %Help: RESET - reset a session variable to its default value
// %Category: Cfg
// %Text: RESET [SESSION] <var>
// %SeeAlso: RESET CLUSTER SETTING, WEBDOCS/set-vars.html
reset_session_stmt:
  RESET session_var
  {
    $$.val = &ast.SetVar{Name: $2, Values:ast.Exprs{ast.DefaultVal{}}}
  }
| RESET SESSION session_var
  {
    $$.val = &ast.SetVar{Name: $3, Values:ast.Exprs{ast.DefaultVal{}}}
  }
| RESET error // SHOW HELP: RESET

// %Help: RESET CLUSTER SETTING - reset a cluster setting to its default value
// %Category: Cfg
// %Text: RESET CLUSTER SETTING <var>
// %SeeAlso: SET CLUSTER SETTING, RESET
reset_csetting_stmt:
  RESET CLUSTER SETTING var_name
  {
    $$.val = &ast.SetClusterSetting{Name: strings.Join($4.strs(), "."), Value:ast.DefaultVal{}}
  }
| RESET CLUSTER error // SHOW HELP: RESET CLUSTER SETTING

// USE is the MSSQL/MySQL equivalent of SET DATABASE. Alias it for convenience.
// %Help: USE - set the current database
// %Category: Cfg
// %Text: USE <dbname>
//
// "USE <dbname>" is an alias for "SET [SESSION] database = <dbname>".
// %SeeAlso: SET SESSION, WEBDOCS/set-vars.html
use_stmt:
  USE var_value
  {
    $$.val = &ast.SetVar{Name: "database", Values: ast.Exprs{$2.expr()}}
  }
| USE error // SHOW HELP: USE

// SET remainder, e.g. SET TRANSACTION
nonpreparable_set_stmt:
  set_transaction_stmt // EXTEND WITH HELP: SET TRANSACTION
| set_exprs_internal   { /* SKIP DOC */ }
| SET CONSTRAINTS error { return unimplemented(sqllex, "set constraints") }
| SET LOCAL error { return unimplementedWithIssue(sqllex, 32562) }

// SET SESSION / SET CLUSTER SETTING
preparable_set_stmt:
  set_session_stmt     // EXTEND WITH HELP: SET SESSION
| set_csetting_stmt    // EXTEND WITH HELP: SET CLUSTER SETTING
| use_stmt             // EXTEND WITH HELP: USE

// %Help: SCRUB - run checks against databases or tables
// %Category: Experimental
// %Text:
// EXPERIMENTAL SCRUB TABLE <table> ...
// EXPERIMENTAL SCRUB DATABASE <database>
//
// The various checks that ca be run with SCRUB includes:
//   - Physical table data (encoding)
//   - Secondary index integrity
//   - Constraint integrity (NOT NULL, CHECK, FOREIGN KEY, UNIQUE)
// %SeeAlso: SCRUB TABLE, SCRUB DATABASE
scrub_stmt:
  scrub_table_stmt
| scrub_database_stmt
| EXPERIMENTAL SCRUB error // SHOW HELP: SCRUB

// %Help: SCRUB DATABASE - run scrub checks on a database
// %Category: Experimental
// %Text:
// EXPERIMENTAL SCRUB DATABASE <database>
//                             [AS OF SYSTEM TIME <expr>]
//
// All scrub checks will be run on the database. This includes:
//   - Physical table data (encoding)
//   - Secondary index integrity
//   - Constraint integrity (NOT NULL, CHECK, FOREIGN KEY, UNIQUE)
// %SeeAlso: SCRUB TABLE, SCRUB
scrub_database_stmt:
  EXPERIMENTAL SCRUB DATABASE database_name opt_as_of_clause
  {
    $$.val = &ast.Scrub{Typ: ast.ScrubDatabase, Database: ast.Name($4), AsOf: $5.asOfClause()}
  }
| EXPERIMENTAL SCRUB DATABASE error // SHOW HELP: SCRUB DATABASE

// %Help: SCRUB TABLE - run scrub checks on a table
// %Category: Experimental
// %Text:
// SCRUB TABLE <tablename>
//             [AS OF SYSTEM TIME <expr>]
//             [WITH OPTIONS <option> [, ...]]
//
// Options:
//   EXPERIMENTAL SCRUB TABLE ... WITH OPTIONS INDEX ALL
//   EXPERIMENTAL SCRUB TABLE ... WITH OPTIONS INDEX (<index>...)
//   EXPERIMENTAL SCRUB TABLE ... WITH OPTIONS CONSTRAINT ALL
//   EXPERIMENTAL SCRUB TABLE ... WITH OPTIONS CONSTRAINT (<constraint>...)
//   EXPERIMENTAL SCRUB TABLE ... WITH OPTIONS PHYSICAL
// %SeeAlso: SCRUB DATABASE, SRUB
scrub_table_stmt:
  EXPERIMENTAL SCRUB TABLE table_name opt_as_of_clause opt_scrub_options_clause
  {
    $$.val = &ast.Scrub{
      Typ: ast.ScrubTable,
      Table: $4.unresolvedObjectName(),
      AsOf: $5.asOfClause(),
      Options: $6.scrubOptions(),
    }
  }
| EXPERIMENTAL SCRUB TABLE error // SHOW HELP: SCRUB TABLE

opt_scrub_options_clause:
  WITH OPTIONS scrub_option_list
  {
    $$.val = $3.scrubOptions()
  }
| /* EMPTY */
  {
    $$.val = ast.ScrubOptions{}
  }

scrub_option_list:
  scrub_option
  {
    $$.val = ast.ScrubOptions{$1.scrubOption()}
  }
| scrub_option_list ',' scrub_option
  {
    $$.val = append($1.scrubOptions(), $3.scrubOption())
  }

scrub_option:
  INDEX ALL
  {
    $$.val = &ast.ScrubOptionIndex{}
  }
| INDEX '(' name_list ')'
  {
    $$.val = &ast.ScrubOptionIndex{IndexNames: $3.nameList()}
  }
| CONSTRAINT ALL
  {
    $$.val = &ast.ScrubOptionConstraint{}
  }
| CONSTRAINT '(' name_list ')'
  {
    $$.val = &ast.ScrubOptionConstraint{ConstraintNames: $3.nameList()}
  }
| PHYSICAL
  {
    $$.val = &ast.ScrubOptionPhysical{}
  }

// %Help: SET CLUSTER SETTING - change a cluster setting
// %Category: Cfg
// %Text: SET CLUSTER SETTING <var> { TO | = } <value>
// %SeeAlso: SHOW CLUSTER SETTING, RESET CLUSTER SETTING, SET SESSION,
// WEBDOCS/cluster-settings.html
set_csetting_stmt:
  SET CLUSTER SETTING var_name to_or_eq var_value
  {
    $$.val = &ast.SetClusterSetting{Name: strings.Join($4.strs(), "."), Value: $6.expr()}
  }
| SET CLUSTER error // SHOW HELP: SET CLUSTER SETTING

to_or_eq:
  '='
| TO

set_exprs_internal:
  /* SET ROW serves to accelerate parser.parseExprs().
     It cannot be used by clients. */
  SET ROW '(' expr_list ')'
  {
    $$.val = &ast.SetVar{Values: $4.exprs()}
  }

// %Help: SET SESSION - change a session variable
// %Category: Cfg
// %Text:
// SET [SESSION] <var> { TO | = } <values...>
// SET [SESSION] TIME ZONE <tz>
// SET [SESSION] CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL { SNAPSHOT | SERIALIZABLE }
// SET [SESSION] TRACING { TO | = } { on | off | cluster | local | kv | results } [,...]
//
// %SeeAlso: SHOW SESSION, RESET, DISCARD, SHOW, SET CLUSTER SETTING, SET TRANSACTION,
// WEBDOCS/set-vars.html
set_session_stmt:
  SET SESSION set_rest_more
  {
    $$.val = $3.stmt()
  }
| SET set_rest_more
  {
    $$.val = $2.stmt()
  }
// Special form for pg compatibility:
| SET SESSION CHARACTERISTICS AS TRANSACTION transaction_mode_list
  {
    $$.val = &ast.SetSessionCharacteristics{Modes: $6.transactionModes()}
  }

// %Help: SET TRANSACTION - configure the transaction settings
// %Category: Txn
// %Text:
// SET [SESSION] TRANSACTION <txnparameters...>
//
// Transaction parameters:
//    ISOLATION LEVEL { SNAPSHOT | SERIALIZABLE }
//    PRIORITY { LOW | NORMAL | HIGH }
//
// %SeeAlso: SHOW TRANSACTION, SET SESSION,
// WEBDOCS/set-transaction.html
set_transaction_stmt:
  SET TRANSACTION transaction_mode_list
  {
    $$.val = &ast.SetTransaction{Modes: $3.transactionModes()}
  }
| SET TRANSACTION error // SHOW HELP: SET TRANSACTION
| SET SESSION TRANSACTION transaction_mode_list
  {
    $$.val = &ast.SetTransaction{Modes: $4.transactionModes()}
  }
| SET SESSION TRANSACTION error // SHOW HELP: SET TRANSACTION

generic_set:
  var_name to_or_eq var_list
  {
    // We need to recognize the "set tracing" specially here; couldn't make "set
    // tracing" a different grammar rule because of ambiguity.
    varName := $1.strs()
    if len(varName) == 1 && varName[0] == "tracing" {
      $$.val = &ast.SetTracing{Values: $3.exprs()}
    } else {
      $$.val = &ast.SetVar{Name: strings.Join($1.strs(), "."), Values: $3.exprs()}
    }
  }

set_rest_more:
// Generic SET syntaxes:
   generic_set
// Special SET syntax forms in addition to the generic form.
// See: https://www.postgresql.org/docs/10/static/sql-set.html
//
// "SET TIME ZONE value is an alias for SET timezone TO value."
| TIME ZONE zone_value
  {
    /* SKIP DOC */
    $$.val = &ast.SetVar{Name: "timezone", Values: ast.Exprs{$3.expr()}}
  }
// "SET SCHEMA 'value' is an alias for SET search_path TO value. Only
// one schema can be specified using this syntax."
| SCHEMA var_value
  {
    /* SKIP DOC */
    $$.val = &ast.SetVar{Name: "search_path", Values: ast.Exprs{$2.expr()}}
  }
| SESSION AUTHORIZATION DEFAULT
  {
    /* SKIP DOC */
    $$.val = &ast.SetSessionAuthorizationDefault{}
  }
| SESSION AUTHORIZATION non_reserved_word_or_sconst
  {
    return unimplementedWithIssue(sqllex, 40283)
  }
// See comment for the non-terminal for SET NAMES below.
| set_names
| var_name FROM CURRENT { return unimplemented(sqllex, "set from current") }
| error // SHOW HELP: SET SESSION

// SET NAMES is the SQL standard syntax for SET client_encoding.
// "SET NAMES value is an alias for SET client_encoding TO value."
// See https://www.postgresql.org/docs/10/static/sql-set.html
// Also see https://www.postgresql.org/docs/9.6/static/multibyte.html#AEN39236
set_names:
  NAMES var_value
  {
    /* SKIP DOC */
    $$.val = &ast.SetVar{Name: "client_encoding", Values: ast.Exprs{$2.expr()}}
  }
| NAMES
  {
    /* SKIP DOC */
    $$.val = &ast.SetVar{Name: "client_encoding", Values: ast.Exprs{ast.DefaultVal{}}}
  }

var_name:
  name
  {
    $$.val = []string{$1}
  }
| name attrs
  {
    $$.val = append([]string{$1}, $2.strs()...)
  }

attrs:
  '.' unrestricted_name
  {
    $$.val = []string{$2}
  }
| attrs '.' unrestricted_name
  {
    $$.val = append($1.strs(), $3)
  }

var_value:
  a_expr
| extra_var_value
  {
    $$.val = ast.Expr(&ast.UnresolvedName{NumParts: 1, Parts: ast.NameParts{$1}})
  }

// The RHS of a SET statement can contain any valid expression, which
// themselves can contain identifiers like TRUE, FALSE. These are parsed
// as column names (via a_expr) and later during semantic analysis
// assigned their special value.
//
// In addition, for compatibility with CockroachDB we need to support
// the reserved keyword ON (to go along OFF, which is a valid column name).
//
// Finally, in PostgreSQL the CockroachDB-reserved words "index",
// "nothing", etc. are not special and are valid in SET. These need to
// be allowed here too.
extra_var_value:
  ON
| cockroachdb_extra_reserved_keyword

var_list:
  var_value
  {
    $$.val = ast.Exprs{$1.expr()}
  }
| var_list ',' var_value
  {
    $$.val = append($1.exprs(), $3.expr())
  }

iso_level:
  READ UNCOMMITTED
  {
    $$.val = ast.SerializableIsolation
  }
| READ COMMITTED
  {
    $$.val = ast.SerializableIsolation
  }
| SNAPSHOT
  {
    $$.val = ast.SerializableIsolation
  }
| REPEATABLE READ
  {
    $$.val = ast.SerializableIsolation
  }
| SERIALIZABLE
  {
    $$.val = ast.SerializableIsolation
  }

user_priority:
  LOW
  {
    $$.val = ast.Low
  }
| NORMAL
  {
    $$.val = ast.Normal
  }
| HIGH
  {
    $$.val = ast.High
  }

// Timezone values can be:
// - a string such as 'pst8pdt'
// - an identifier such as "pst8pdt"
// - an integer or floating point number
// - a time interval per SQL99
zone_value:
  SCONST
  {
    $$.val = ast.NewStrVal($1)
  }
| IDENT
  {
    $$.val = ast.NewStrVal($1)
  }
| interval_value
  {
    $$.val = $1.expr()
  }
| numeric_only
| DEFAULT
  {
    $$.val = ast.DefaultVal{}
  }
| LOCAL
  {
    $$.val = ast.NewStrVal($1)
  }

// %Help: SHOW
// %Category: Group
// %Text:
// SHOW BACKUP, SHOW CLUSTER SETTING, SHOW COLUMNS, SHOW CONSTRAINTS,
// SHOW CREATE, SHOW DATABASES, SHOW HISTOGRAM, SHOW INDEXES, SHOW
// PARTITIONS, SHOW JOBS, SHOW QUERIES, SHOW RANGE, SHOW RANGES,
// SHOW ROLES, SHOW SCHEMAS, SHOW SEQUENCES, SHOW SESSION, SHOW SESSIONS,
// SHOW STATISTICS, SHOW SYNTAX, SHOW TABLES, SHOW TRACE SHOW TRANSACTION, SHOW USERS,
// SHOW LAST QUERY STATISTICS
show_stmt:
  show_backup_stmt          // EXTEND WITH HELP: SHOW BACKUP
| show_columns_stmt         // EXTEND WITH HELP: SHOW COLUMNS
| show_constraints_stmt     // EXTEND WITH HELP: SHOW CONSTRAINTS
| show_create_stmt          // EXTEND WITH HELP: SHOW CREATE
| show_csettings_stmt       // EXTEND WITH HELP: SHOW CLUSTER SETTING
| show_databases_stmt       // EXTEND WITH HELP: SHOW DATABASES
| show_fingerprints_stmt
| show_grants_stmt          // EXTEND WITH HELP: SHOW GRANTS
| show_histogram_stmt       // EXTEND WITH HELP: SHOW HISTOGRAM
| show_indexes_stmt         // EXTEND WITH HELP: SHOW INDEXES
| show_partitions_stmt      // EXTEND WITH HELP: SHOW PARTITIONS
| show_jobs_stmt            // EXTEND WITH HELP: SHOW JOBS
| show_queries_stmt         // EXTEND WITH HELP: SHOW QUERIES
| show_ranges_stmt          // EXTEND WITH HELP: SHOW RANGES
| show_range_for_row_stmt
| show_roles_stmt           // EXTEND WITH HELP: SHOW ROLES
| show_savepoint_stmt       // EXTEND WITH HELP: SHOW SAVEPOINT
| show_schemas_stmt         // EXTEND WITH HELP: SHOW SCHEMAS
| show_sequences_stmt       // EXTEND WITH HELP: SHOW SEQUENCES
| show_session_stmt         // EXTEND WITH HELP: SHOW SESSION
| show_sessions_stmt        // EXTEND WITH HELP: SHOW SESSIONS
| show_stats_stmt           // EXTEND WITH HELP: SHOW STATISTICS
| show_syntax_stmt          // EXTEND WITH HELP: SHOW SYNTAX
| show_tables_stmt          // EXTEND WITH HELP: SHOW TABLES
| show_trace_stmt           // EXTEND WITH HELP: SHOW TRACE
| show_transaction_stmt     // EXTEND WITH HELP: SHOW TRANSACTION
| show_users_stmt           // EXTEND WITH HELP: SHOW USERS
| show_zone_stmt
| SHOW error                // SHOW HELP: SHOW
| show_last_query_stats_stmt // EXTEND WITH HELP: SHOW LAST QUERY STATISTICS

// Cursors are not yet supported by CockroachDB. CLOSE ALL is safe to no-op
// since there will be no open cursors.
close_cursor_stmt:
	CLOSE ALL { }
| CLOSE cursor_name { return unimplementedWithIssue(sqllex, 41412) }

declare_cursor_stmt:
	DECLARE { return unimplementedWithIssue(sqllex, 41412) }

reindex_stmt:
  REINDEX TABLE error
  {
    /* SKIP DOC */
    return purposelyUnimplemented(sqllex, "reindex table", "CockroachDB does not require reindexing.")
  }
| REINDEX INDEX error
  {
    /* SKIP DOC */
    return purposelyUnimplemented(sqllex, "reindex index", "CockroachDB does not require reindexing.")
  }
| REINDEX DATABASE error
  {
    /* SKIP DOC */
    return purposelyUnimplemented(sqllex, "reindex database", "CockroachDB does not require reindexing.")
  }
| REINDEX SYSTEM error
  {
    /* SKIP DOC */
    return purposelyUnimplemented(sqllex, "reindex system", "CockroachDB does not require reindexing.")
  }

// %Help: SHOW SESSION - display session variables
// %Category: Cfg
// %Text: SHOW [SESSION] { <var> | ALL }
// %SeeAlso: WEBDOCS/show-vars.html
show_session_stmt:
  SHOW session_var         { $$.val = &ast.ShowVar{Name: $2} }
| SHOW SESSION session_var { $$.val = &ast.ShowVar{Name: $3} }
| SHOW SESSION error // SHOW HELP: SHOW SESSION

session_var:
  IDENT
// Although ALL, SESSION_USER and DATABASE are identifiers for the
// purpose of SHOW, they lex as separate token types, so they need
// separate rules.
| ALL
| DATABASE
// SET NAMES is standard SQL for SET client_encoding.
// See https://www.postgresql.org/docs/9.6/static/multibyte.html#AEN39236
| NAMES { $$ = "client_encoding" }
| SESSION_USER
// TIME ZONE is special: it is two tokens, but is really the identifier "TIME ZONE".
| TIME ZONE { $$ = "timezone" }
| TIME error // SHOW HELP: SHOW SESSION

// %Help: SHOW STATISTICS - display table statistics (experimental)
// %Category: Experimental
// %Text: SHOW STATISTICS [USING JSON] FOR TABLE <table_name>
//
// Returns the available statistics for a table.
// The statistics can include a histogram ID, which can
// be used with SHOW HISTOGRAM.
// If USING JSON is specified, the statistics and histograms
// are encoded in JSON format.
// %SeeAlso: SHOW HISTOGRAM
show_stats_stmt:
  SHOW STATISTICS FOR TABLE table_name
  {
    $$.val = &ast.ShowTableStats{Table: $5.unresolvedObjectName()}
  }
| SHOW STATISTICS USING JSON FOR TABLE table_name
  {
    /* SKIP DOC */
    $$.val = &ast.ShowTableStats{Table: $7.unresolvedObjectName(), UsingJSON: true}
  }
| SHOW STATISTICS error // SHOW HELP: SHOW STATISTICS

// %Help: SHOW HISTOGRAM - display histogram (experimental)
// %Category: Experimental
// %Text: SHOW HISTOGRAM <histogram_id>
//
// Returns the data in the histogram with the
// given ID (as returned by SHOW STATISTICS).
// %SeeAlso: SHOW STATISTICS
show_histogram_stmt:
  SHOW HISTOGRAM ICONST
  {
    /* SKIP DOC */
    id, err := $3.numVal().AsInt64()
    if err != nil {
      return setErr(sqllex, err)
    }
    $$.val = &ast.ShowHistogram{HistogramID: id}
  }
| SHOW HISTOGRAM error // SHOW HELP: SHOW HISTOGRAM

// %Help: SHOW BACKUP - list backup contents
// %Category: CCL
// %Text: SHOW BACKUP [SCHEMAS|FILES|RANGES] <location>
// %SeeAlso: WEBDOCS/show-backup.html
show_backup_stmt:
  SHOW BACKUP string_or_placeholder opt_with_options
  {
    $$.val = &ast.ShowBackup{
      Details: ast.BackupDefaultDetails,
      Path:    $3.expr(),
      Options: $4.kvOptions(),
    }
  }
| SHOW BACKUP SCHEMAS string_or_placeholder opt_with_options
  {
    $$.val = &ast.ShowBackup{
      Details: ast.BackupDefaultDetails,
      ShouldIncludeSchemas: true,
      Path:    $4.expr(),
      Options: $5.kvOptions(),
    }
  }
| SHOW BACKUP RANGES string_or_placeholder opt_with_options
  {
    /* SKIP DOC */
    $$.val = &ast.ShowBackup{
      Details: ast.BackupRangeDetails,
      Path:    $4.expr(),
      Options: $5.kvOptions(),
    }
  }
| SHOW BACKUP FILES string_or_placeholder opt_with_options
  {
    /* SKIP DOC */
    $$.val = &ast.ShowBackup{
      Details: ast.BackupFileDetails,
      Path:    $4.expr(),
      Options: $5.kvOptions(),
    }
  }
| SHOW BACKUP error // SHOW HELP: SHOW BACKUP

// %Help: SHOW CLUSTER SETTING - display cluster settings
// %Category: Cfg
// %Text:
// SHOW CLUSTER SETTING <var>
// SHOW [ PUBLIC | ALL ] CLUSTER SETTINGS
// %SeeAlso: WEBDOCS/cluster-settings.html
show_csettings_stmt:
  SHOW CLUSTER SETTING var_name
  {
    $$.val = &ast.ShowClusterSetting{Name: strings.Join($4.strs(), ".")}
  }
| SHOW CLUSTER SETTING ALL
  {
    $$.val = &ast.ShowClusterSettingList{All: true}
  }
| SHOW CLUSTER error // SHOW HELP: SHOW CLUSTER SETTING
| SHOW ALL CLUSTER SETTINGS
  {
    $$.val = &ast.ShowClusterSettingList{All: true}
  }
| SHOW ALL CLUSTER error // SHOW HELP: SHOW CLUSTER SETTING
| SHOW CLUSTER SETTINGS
  {
    $$.val = &ast.ShowClusterSettingList{}
  }
| SHOW PUBLIC CLUSTER SETTINGS
  {
    $$.val = &ast.ShowClusterSettingList{}
  }
| SHOW PUBLIC CLUSTER error // SHOW HELP: SHOW CLUSTER SETTING

// %Help: SHOW COLUMNS - list columns in relation
// %Category: DDL
// %Text: SHOW COLUMNS FROM <tablename>
// %SeeAlso: WEBDOCS/show-columns.html
show_columns_stmt:
  SHOW COLUMNS FROM table_name with_comment
  {
    $$.val = &ast.ShowColumns{Table: $4.unresolvedObjectName(), WithComment: $5.bool()}
  }
| SHOW COLUMNS error // SHOW HELP: SHOW COLUMNS

// %Help: SHOW PARTITIONS - list partition information
// %Category: DDL
// %Text: SHOW PARTITIONS FROM { TABLE <table> | INDEX <index> | DATABASE <database> }
// %SeeAlso: WEBDOCS/show-partitions.html
show_partitions_stmt:
  SHOW PARTITIONS FROM TABLE table_name
  {
    $$.val = &ast.ShowPartitions{IsTable: true, Table: $5.unresolvedObjectName()}
  }
| SHOW PARTITIONS FROM DATABASE database_name
  {
    $$.val = &ast.ShowPartitions{IsDB: true, Database: ast.Name($5)}
  }
| SHOW PARTITIONS FROM INDEX table_index_name
  {
    $$.val = &ast.ShowPartitions{IsIndex: true, Index: $5.tableIndexName()}
  }
| SHOW PARTITIONS FROM INDEX table_name '@' '*'
  {
    $$.val = &ast.ShowPartitions{IsTable: true, Table: $5.unresolvedObjectName()}
  }
| SHOW PARTITIONS error // SHOW HELP: SHOW PARTITIONS

// %Help: SHOW DATABASES - list databases
// %Category: DDL
// %Text: SHOW DATABASES
// %SeeAlso: WEBDOCS/show-databases.html
show_databases_stmt:
  SHOW DATABASES with_comment
  {
    $$.val = &ast.ShowDatabases{WithComment: $3.bool()}
  }
| SHOW DATABASES error // SHOW HELP: SHOW DATABASES

// %Help: SHOW GRANTS - list grants
// %Category: Priv
// %Text:
// Show privilege grants:
//   SHOW GRANTS [ON <targets...>] [FOR <users...>]
// Show role grants:
//   SHOW GRANTS ON ROLE [<roles...>] [FOR <grantees...>]
//
// %SeeAlso: WEBDOCS/show-grants.html
show_grants_stmt:
  SHOW GRANTS opt_on_targets_roles for_grantee_clause
  {
    lst := $3.targetListPtr()
    if lst != nil && lst.ForRoles {
      $$.val = &ast.ShowRoleGrants{Roles: lst.Roles, Grantees: $4.nameList()}
    } else {
      $$.val = &ast.ShowGrants{Targets: lst, Grantees: $4.nameList()}
    }
  }
| SHOW GRANTS error // SHOW HELP: SHOW GRANTS

// %Help: SHOW INDEXES - list indexes
// %Category: DDL
// %Text: SHOW INDEXES FROM { <tablename> | DATABASE <database_name> } [WITH COMMENT]
// %SeeAlso: WEBDOCS/show-index.html
show_indexes_stmt:
  SHOW INDEX FROM table_name with_comment
  {
    $$.val = &ast.ShowIndexes{Table: $4.unresolvedObjectName(), WithComment: $5.bool()}
  }
| SHOW INDEX error // SHOW HELP: SHOW INDEXES
| SHOW INDEX FROM DATABASE database_name with_comment
  {
    $$.val = &ast.ShowDatabaseIndexes{Database: ast.Name($5), WithComment: $6.bool()}
  }
| SHOW INDEXES FROM table_name with_comment
  {
    $$.val = &ast.ShowIndexes{Table: $4.unresolvedObjectName(), WithComment: $5.bool()}
  }
| SHOW INDEXES FROM DATABASE database_name with_comment
  {
    $$.val = &ast.ShowDatabaseIndexes{Database: ast.Name($5), WithComment: $6.bool()}
  }
| SHOW INDEXES error // SHOW HELP: SHOW INDEXES
| SHOW KEYS FROM table_name with_comment
  {
    $$.val = &ast.ShowIndexes{Table: $4.unresolvedObjectName(), WithComment: $5.bool()}
  }
| SHOW KEYS FROM DATABASE database_name with_comment
  {
    $$.val = &ast.ShowDatabaseIndexes{Database: ast.Name($5), WithComment: $6.bool()}
  }
| SHOW KEYS error // SHOW HELP: SHOW INDEXES

// %Help: SHOW CONSTRAINTS - list constraints
// %Category: DDL
// %Text: SHOW CONSTRAINTS FROM <tablename>
// %SeeAlso: WEBDOCS/show-constraints.html
show_constraints_stmt:
  SHOW CONSTRAINT FROM table_name
  {
    $$.val = &ast.ShowConstraints{Table: $4.unresolvedObjectName()}
  }
| SHOW CONSTRAINT error // SHOW HELP: SHOW CONSTRAINTS
| SHOW CONSTRAINTS FROM table_name
  {
    $$.val = &ast.ShowConstraints{Table: $4.unresolvedObjectName()}
  }
| SHOW CONSTRAINTS error // SHOW HELP: SHOW CONSTRAINTS

// %Help: SHOW QUERIES - list running queries
// %Category: Misc
// %Text: SHOW [ALL] [CLUSTER | LOCAL] QUERIES
// %SeeAlso: CANCEL QUERIES
show_queries_stmt:
  SHOW opt_cluster QUERIES
  {
    $$.val = &ast.ShowQueries{All: false, Cluster: $2.bool()}
  }
| SHOW opt_cluster QUERIES error // SHOW HELP: SHOW QUERIES
| SHOW ALL opt_cluster QUERIES
  {
    $$.val = &ast.ShowQueries{All: true, Cluster: $3.bool()}
  }
| SHOW ALL opt_cluster QUERIES error // SHOW HELP: SHOW QUERIES

opt_cluster:
  /* EMPTY */
  { $$.val = true }
| CLUSTER
  { $$.val = true }
| LOCAL
  { $$.val = false }

// %Help: SHOW JOBS - list background jobs
// %Category: Misc
// %Text:
// SHOW [AUTOMATIC] JOBS
// SHOW JOB <jobid>
// %SeeAlso: CANCEL JOBS, PAUSE JOBS, RESUME JOBS
show_jobs_stmt:
  SHOW AUTOMATIC JOBS
  {
    $$.val = &ast.ShowJobs{Automatic: true}
  }
| SHOW JOBS
  {
    $$.val = &ast.ShowJobs{Automatic: false}
  }
| SHOW AUTOMATIC JOBS error // SHOW HELP: SHOW JOBS
| SHOW JOBS error // SHOW HELP: SHOW JOBS
| SHOW JOBS select_stmt
  {
    $$.val = &ast.ShowJobs{Jobs: $3.slct()}
  }
| SHOW JOBS WHEN COMPLETE select_stmt
  {
    $$.val = &ast.ShowJobs{Jobs: $5.slct(), Block: true}
  }
| SHOW JOBS select_stmt error // SHOW HELP: SHOW JOBS
| SHOW JOB a_expr
  {
    $$.val = &ast.ShowJobs{
      Jobs: &ast.Select{
        Select: &ast.ValuesClause{Rows: []ast.Exprs{ast.Exprs{$3.expr()}}},
      },
    }
  }
| SHOW JOB WHEN COMPLETE a_expr
  {
    $$.val = &ast.ShowJobs{
      Jobs: &ast.Select{
        Select: &ast.ValuesClause{Rows: []ast.Exprs{ast.Exprs{$5.expr()}}},
      },
      Block: true,
    }
  }
| SHOW JOB error // SHOW HELP: SHOW JOBS

// %Help: SHOW TRACE - display an execution trace
// %Category: Misc
// %Text:
// SHOW [COMPACT] [KV] TRACE FOR SESSION
// %SeeAlso: EXPLAIN
show_trace_stmt:
  SHOW opt_compact TRACE FOR SESSION
  {
    $$.val = &ast.ShowTraceForSession{TraceType: ast.ShowTraceRaw, Compact: $2.bool()}
  }
| SHOW opt_compact TRACE error // SHOW HELP: SHOW TRACE
| SHOW opt_compact KV TRACE FOR SESSION
  {
    $$.val = &ast.ShowTraceForSession{TraceType: ast.ShowTraceKV, Compact: $2.bool()}
  }
| SHOW opt_compact KV error // SHOW HELP: SHOW TRACE
| SHOW opt_compact EXPERIMENTAL_REPLICA TRACE FOR SESSION
  {
    /* SKIP DOC */
    $$.val = &ast.ShowTraceForSession{TraceType: ast.ShowTraceReplica, Compact: $2.bool()}
  }
| SHOW opt_compact EXPERIMENTAL_REPLICA error // SHOW HELP: SHOW TRACE

opt_compact:
  COMPACT { $$.val = true }
| /* EMPTY */ { $$.val = false }

// %Help: SHOW SESSIONS - list open client sessions
// %Category: Misc
// %Text: SHOW [ALL] [CLUSTER | LOCAL] SESSIONS
// %SeeAlso: CANCEL SESSIONS
show_sessions_stmt:
  SHOW opt_cluster SESSIONS
  {
    $$.val = &ast.ShowSessions{Cluster: $2.bool()}
  }
| SHOW opt_cluster SESSIONS error // SHOW HELP: SHOW SESSIONS
| SHOW ALL opt_cluster SESSIONS
  {
    $$.val = &ast.ShowSessions{All: true, Cluster: $3.bool()}
  }
| SHOW ALL opt_cluster SESSIONS error // SHOW HELP: SHOW SESSIONS

// %Help: SHOW TABLES - list tables
// %Category: DDL
// %Text: SHOW TABLES [FROM <databasename> [ . <schemaname> ] ] [WITH COMMENT]
// %SeeAlso: WEBDOCS/show-tables.html
show_tables_stmt:
  SHOW TABLES FROM name '.' name with_comment
  {
    $$.val = &ast.ShowTables{ObjectNamePrefix:ast.ObjectNamePrefix{
        CatalogName: ast.Name($4),
        ExplicitCatalog: true,
        SchemaName: ast.Name($6),
        ExplicitSchema: true,
    },
    WithComment: $7.bool()}
  }
| SHOW TABLES FROM name with_comment
  {
    $$.val = &ast.ShowTables{ObjectNamePrefix:ast.ObjectNamePrefix{
        // Note: the schema name may be interpreted as database name,
        // see name_resolution.go.
        SchemaName: ast.Name($4),
        ExplicitSchema: true,
    },
    WithComment: $5.bool()}
  }
| SHOW TABLES with_comment
  {
    $$.val = &ast.ShowTables{WithComment: $3.bool()}
  }
| SHOW TABLES error // SHOW HELP: SHOW TABLES

with_comment:
  WITH COMMENT { $$.val = true }
| /* EMPTY */  { $$.val = false }

// %Help: SHOW SCHEMAS - list schemas
// %Category: DDL
// %Text: SHOW SCHEMAS [FROM <databasename> ]
show_schemas_stmt:
  SHOW SCHEMAS FROM name
  {
    $$.val = &ast.ShowSchemas{Database: ast.Name($4)}
  }
| SHOW SCHEMAS
  {
    $$.val = &ast.ShowSchemas{}
  }
| SHOW SCHEMAS error // SHOW HELP: SHOW SCHEMAS

// %Help: SHOW SEQUENCES - list sequences
// %Category: DDL
// %Text: SHOW SEQUENCES [FROM <databasename> ]
show_sequences_stmt:
  SHOW SEQUENCES FROM name
  {
    $$.val = &ast.ShowSequences{Database: ast.Name($4)}
  }
| SHOW SEQUENCES
  {
    $$.val = &ast.ShowSequences{}
  }
| SHOW SEQUENCES error // SHOW HELP: SHOW SEQUENCES

// %Help: SHOW SYNTAX - analyze SQL syntax
// %Category: Misc
// %Text: SHOW SYNTAX <string>
show_syntax_stmt:
  SHOW SYNTAX SCONST
  {
    /* SKIP DOC */
    $$.val = &ast.ShowSyntax{Statement: $3}
  }
| SHOW SYNTAX error // SHOW HELP: SHOW SYNTAX

// %Help: SHOW LAST QUERY STATISTICS - display statistics for the last query issued
// %Category: Misc
// %Text: SHOW LAST QUERY STATISTICS
show_last_query_stats_stmt:
  SHOW LAST QUERY STATISTICS
  {
   /* SKIP DOC */
   $$.val = &ast.ShowLastQueryStatistics{}
  }

// %Help: SHOW SAVEPOINT - display current savepoint properties
// %Category: Cfg
// %Text: SHOW SAVEPOINT STATUS
show_savepoint_stmt:
  SHOW SAVEPOINT STATUS
  {
    $$.val = &ast.ShowSavepointStatus{}
  }
| SHOW SAVEPOINT error // SHOW HELP: SHOW SAVEPOINT

// %Help: SHOW TRANSACTION - display current transaction properties
// %Category: Cfg
// %Text: SHOW TRANSACTION {ISOLATION LEVEL | PRIORITY | STATUS}
// %SeeAlso: WEBDOCS/show-transaction.html
show_transaction_stmt:
  SHOW TRANSACTION ISOLATION LEVEL
  {
    /* SKIP DOC */
    $$.val = &ast.ShowVar{Name: "transaction_isolation"}
  }
| SHOW TRANSACTION PRIORITY
  {
    /* SKIP DOC */
    $$.val = &ast.ShowVar{Name: "transaction_priority"}
  }
| SHOW TRANSACTION STATUS
  {
    /* SKIP DOC */
    $$.val = &ast.ShowTransactionStatus{}
  }
| SHOW TRANSACTION error // SHOW HELP: SHOW TRANSACTION

// %Help: SHOW CREATE - display the CREATE statement for a table, sequence or view
// %Category: DDL
// %Text: SHOW CREATE [ TABLE | SEQUENCE | VIEW ] <tablename>
// %SeeAlso: WEBDOCS/show-create-table.html
show_create_stmt:
  SHOW CREATE table_name
  {
    $$.val = &ast.ShowCreate{Name: $3.unresolvedObjectName()}
  }
| SHOW CREATE create_kw table_name
  {
    /* SKIP DOC */
    $$.val = &ast.ShowCreate{Name: $4.unresolvedObjectName()}
  }
| SHOW CREATE error // SHOW HELP: SHOW CREATE

create_kw:
  TABLE
| VIEW
| SEQUENCE

// %Help: SHOW USERS - list defined users
// %Category: Priv
// %Text: SHOW USERS
// %SeeAlso: CREATE USER, DROP USER, WEBDOCS/show-users.html
show_users_stmt:
  SHOW USERS
  {
    $$.val = &ast.ShowUsers{}
  }
| SHOW USERS error // SHOW HELP: SHOW USERS

// %Help: SHOW ROLES - list defined roles
// %Category: Priv
// %Text: SHOW ROLES
// %SeeAlso: CREATE ROLE, ALTER ROLE, DROP ROLE
show_roles_stmt:
  SHOW ROLES
  {
    $$.val = &ast.ShowRoles{}
  }
| SHOW ROLES error // SHOW HELP: SHOW ROLES

show_zone_stmt:
  SHOW ZONE CONFIGURATION FOR RANGE zone_name
  {
    $$.val = &ast.ShowZoneConfig{ZoneSpecifier: ast.ZoneSpecifier{NamedZone: ast.UnrestrictedName($6)}}
  }
| SHOW ZONE CONFIGURATION FOR DATABASE database_name
  {
    $$.val = &ast.ShowZoneConfig{ZoneSpecifier: ast.ZoneSpecifier{Database: ast.Name($6)}}
  }
| SHOW ZONE CONFIGURATION FOR TABLE table_name opt_partition
  {
    name := $6.unresolvedObjectName().ToTableName()
    $$.val = &ast.ShowZoneConfig{ZoneSpecifier: ast.ZoneSpecifier{
        TableOrIndex: ast.TableIndexName{Table: name},
        Partition: ast.Name($7),
    }}
  }
| SHOW ZONE CONFIGURATION FOR PARTITION partition_name OF TABLE table_name
  {
    name := $9.unresolvedObjectName().ToTableName()
    $$.val = &ast.ShowZoneConfig{ZoneSpecifier: ast.ZoneSpecifier{
      TableOrIndex: ast.TableIndexName{Table: name},
      Partition: ast.Name($6),
    }}
  }
| SHOW ZONE CONFIGURATION FOR INDEX table_index_name opt_partition
  {
    $$.val = &ast.ShowZoneConfig{ZoneSpecifier: ast.ZoneSpecifier{
      TableOrIndex: $6.tableIndexName(),
      Partition: ast.Name($7),
    }}
  }
| SHOW ZONE CONFIGURATION FOR PARTITION partition_name OF INDEX table_index_name
  {
    $$.val = &ast.ShowZoneConfig{ZoneSpecifier: ast.ZoneSpecifier{
      TableOrIndex: $9.tableIndexName(),
      Partition: ast.Name($6),
    }}
  }
| SHOW ZONE CONFIGURATIONS
  {
    $$.val = &ast.ShowZoneConfig{}
  }
| SHOW ALL ZONE CONFIGURATIONS
  {
    $$.val = &ast.ShowZoneConfig{}
  }

// %Help: SHOW RANGE - show range information for a row
// %Category: Misc
// %Text:
// SHOW RANGE FROM TABLE <tablename> FOR ROW (row, value, ...)
// SHOW RANGE FROM INDEX [ <tablename> @ ] <indexname> FOR ROW (row, value, ...)
show_range_for_row_stmt:
  SHOW RANGE FROM TABLE table_name FOR ROW '(' expr_list ')'
  {
    name := $5.unresolvedObjectName().ToTableName()
    $$.val = &ast.ShowRangeForRow{
      Row: $9.exprs(),
      TableOrIndex: ast.TableIndexName{Table: name},
    }
  }
| SHOW RANGE FROM INDEX table_index_name FOR ROW '(' expr_list ')'
  {
    $$.val = &ast.ShowRangeForRow{
      Row: $9.exprs(),
      TableOrIndex: $5.tableIndexName(),
    }
  }
| SHOW RANGE error // SHOW HELP: SHOW RANGE

// %Help: SHOW RANGES - list ranges
// %Category: Misc
// %Text:
// SHOW RANGES FROM TABLE <tablename>
// SHOW RANGES FROM INDEX [ <tablename> @ ] <indexname>
show_ranges_stmt:
  SHOW RANGES FROM TABLE table_name
  {
    name := $5.unresolvedObjectName().ToTableName()
    $$.val = &ast.ShowRanges{TableOrIndex: ast.TableIndexName{Table: name}}
  }
| SHOW RANGES FROM INDEX table_index_name
  {
    $$.val = &ast.ShowRanges{TableOrIndex: $5.tableIndexName()}
  }
| SHOW RANGES FROM DATABASE database_name
  {
    $$.val = &ast.ShowRanges{DatabaseName: ast.Name($5)}
  }
| SHOW RANGES error // SHOW HELP: SHOW RANGES

show_fingerprints_stmt:
  SHOW EXPERIMENTAL_FINGERPRINTS FROM TABLE table_name
  {
    /* SKIP DOC */
    $$.val = &ast.ShowFingerprints{Table: $5.unresolvedObjectName()}
  }

opt_on_targets_roles:
  ON targets_roles
  {
    tmp := $2.targetList()
    $$.val = &tmp
  }
| /* EMPTY */
  {
    $$.val = (*ast.TargetList)(nil)
  }

// targets is a non-terminal for a list of privilege targets, either a
// list of databases or a list of tables.
//
// This rule is complex and cannot be decomposed as a tree of
// non-terminals because it must resolve syntax ambiguities in the
// SHOW GRANTS ON ROLE statement. It was constructed as follows.
//
// 1. Start with the desired definition of targets:
//
//    targets ::=
//        table_pattern_list
//        TABLE table_pattern_list
//        DATABASE name_list
//
// 2. Now we must disambiguate the first rule "table_pattern_list"
//    between one that recognizes ROLE and one that recognizes
//    "<some table pattern list>". So first, inline the definition of
//    table_pattern_list.
//
//    targets ::=
//        table_pattern                          # <- here
//        table_pattern_list ',' table_pattern   # <- here
//        TABLE table_pattern_list
//        DATABASE name_list
//
// 3. We now must disambiguate the "ROLE" inside the prefix "table_pattern".
//    However having "table_pattern_list" as prefix is cumbersome, so swap it.
//
//    targets ::=
//        table_pattern
//        table_pattern ',' table_pattern_list   # <- here
//        TABLE table_pattern_list
//        DATABASE name_list
//
// 4. The rule that has table_pattern followed by a comma is now
//    non-problematic, because it will never match "ROLE" followed
//    by an optional name list (neither "ROLE;" nor "ROLE <ident>"
//    would match). We just need to focus on the first one "table_pattern".
//    This needs to tweak "table_pattern".
//
//    Here we could inline table_pattern but now we do not have to any
//    more, we just need to create a variant of it which is
//    unambiguous with a single ROLE keyword. That is, we need a
//    table_pattern which cannot contain a single name. We do
//    this as follows.
//
//    targets ::=
//        complex_table_pattern                  # <- here
//        table_pattern ',' table_pattern_list
//        TABLE table_pattern_list
//        DATABASE name_list
//    complex_table_pattern ::=
//        name '.' unrestricted_name
//        name '.' unrestricted_name '.' unrestricted_name
//        name '.' unrestricted_name '.' '*'
//        name '.' '*'
//        '*'
//
// 5. At this point the rule cannot start with a simple identifier any
//    more, keyword or not. But more importantly, any token sequence
//    that starts with ROLE cannot be matched by any of these remaining
//    rules. This means that the prefix is now free to use, without
//    ambiguity. We do this as follows, to gain a syntax rule for "ROLE
//    <namelist>". (We will handle a ROLE with no name list below.)
//
//    targets ::=
//        ROLE name_list                        # <- here
//        complex_table_pattern
//        table_pattern ',' table_pattern_list
//        TABLE table_pattern_list
//        DATABASE name_list
//
// 6. Now on to the finishing touches. First we would like to regain the
//    ability to use "<tablename>" when the table name is a simple
//    identifier. This is done as follows:
//
//    targets ::=
//        ROLE name_list
//        name                                  # <- here
//        complex_table_pattern
//        table_pattern ',' table_pattern_list
//        TABLE table_pattern_list
//        DATABASE name_list
//
// 7. Then, we want to recognize "ROLE" without any subsequent name
//    list. This requires some care: we can not add "ROLE" to the set of
//    rules above, because "name" would then overlap. To disambiguate,
//    we must first inline "name" as follows:
//
//    targets ::=
//        ROLE name_list
//        IDENT                    # <- here, always <table>
//        col_name_keyword         # <- here, always <table>
//        unreserved_keyword       # <- here, either ROLE or <table>
//        complex_table_pattern
//        table_pattern ',' table_pattern_list
//        TABLE table_pattern_list
//        DATABASE name_list
//
// 8. And now the rule is sufficiently simple that we can disambiguate
//    in the action, like this:
//
//    targets ::=
//        ...
//        unreserved_keyword {
//             if $1 == "role" { /* handle ROLE */ }
//             else { /* handle ON <tablename> */ }
//        }
//        ...
//
//   (but see the comment on the action of this sub-rule below for
//   more nuance.)
//
// Tada!
targets:
  IDENT
  {
    $$.val = ast.TargetList{Tables: ast.TablePatterns{&ast.UnresolvedName{NumParts:1, Parts: ast.NameParts{$1}}}}
  }
| col_name_keyword
  {
    $$.val = ast.TargetList{Tables: ast.TablePatterns{&ast.UnresolvedName{NumParts:1, Parts: ast.NameParts{$1}}}}
  }
| unreserved_keyword
  {
    // This sub-rule is meant to support both ROLE and other keywords
    // used as table name without the TABLE prefix. The keyword ROLE
    // here can have two meanings:
    //
    // - for all statements except SHOW GRANTS, it must be interpreted
    //   as a plain table name.
    // - for SHOW GRANTS specifically, it must be handled as an ON ROLE
    //   specifier without a name list (the rule with a name list is separate,
    //   see above).
    //
    // Yet we want to use a single "targets" non-terminal for all
    // statements that use targets, to share the code. This action
    // achieves this as follows:
    //
    // - for all statements (including SHOW GRANTS), it populates the
    //   Tables list in TargetList{} with the given name. This will
    //   include the given keyword as table pattern in all cases,
    //   including when the keyword was ROLE.
    //
    // - if ROLE was specified, it remembers this fact in the ForRoles
    //   field. This distinguishes `ON ROLE` (where "role" is
    //   specified as keyword), which triggers the special case in
    //   SHOW GRANTS, from `ON "role"` (where "role" is specified as
    //   identifier), which is always handled as a table name.
    //
    //   Both `ON ROLE` and `ON "role"` populate the Tables list in the same way,
    //   so that other statements than SHOW GRANTS don't observe any difference.
    //
    // Arguably this code is a bit too clever. Future work should aim
    // to remove the special casing of SHOW GRANTS altogether instead
    // of increasing (or attempting to modify) the grey magic occurring
    // here.
    $$.val = ast.TargetList{
      Tables: ast.TablePatterns{&ast.UnresolvedName{NumParts:1, Parts: ast.NameParts{$1}}},
      ForRoles: $1 == "role", // backdoor for "SHOW GRANTS ON ROLE" (no name list)
    }
  }
| complex_table_pattern
  {
    $$.val = ast.TargetList{Tables: ast.TablePatterns{$1.unresolvedName()}}
  }
| table_pattern ',' table_pattern_list
  {
    remainderPats := $3.tablePatterns()
    $$.val = ast.TargetList{Tables: append(ast.TablePatterns{$1.unresolvedName()}, remainderPats...)}
  }
| TABLE table_pattern_list
  {
    $$.val = ast.TargetList{Tables: $2.tablePatterns()}
  }
| TENANT iconst64
  {
    tenID := uint64($2.int64())
    if tenID == 0 {
		  return setErr(sqllex, errors.New("invalid tenant ID"))
	  }
    $$.val = ast.TargetList{Tenant: roachpb.MakeTenantID(tenID)}
  }
| DATABASE name_list
  {
    $$.val = ast.TargetList{Databases: $2.nameList()}
  }

// target_roles is the variant of targets which recognizes ON ROLES
// with a name list. This cannot be included in targets directly
// because some statements must not recognize this syntax.
targets_roles:
  ROLE name_list
  {
     $$.val = ast.TargetList{ForRoles: true, Roles: $2.nameList()}
  }
| targets

for_grantee_clause:
  FOR name_list
  {
    $$.val = $2.nameList()
  }
| /* EMPTY */
  {
    $$.val = ast.NameList(nil)
  }

// %Help: PAUSE JOBS - pause background jobs
// %Category: Misc
// %Text:
// PAUSE JOBS <selectclause>
// PAUSE JOB <jobid>
// %SeeAlso: SHOW JOBS, CANCEL JOBS, RESUME JOBS
pause_stmt:
  PAUSE JOB a_expr
  {
    $$.val = &ast.ControlJobs{
      Jobs: &ast.Select{
        Select: &ast.ValuesClause{Rows: []ast.Exprs{ast.Exprs{$3.expr()}}},
      },
      Command: ast.PauseJob,
    }
  }
| PAUSE JOBS select_stmt
  {
    $$.val = &ast.ControlJobs{Jobs: $3.slct(), Command: ast.PauseJob}
  }
| PAUSE error // SHOW HELP: PAUSE JOBS

// %Help: CREATE SCHEMA - create a new schema
// %Category: DDL
// %Text:
// CREATE SCHEMA [IF NOT EXISTS] <schemaname>
create_schema_stmt:
  CREATE SCHEMA schema_name
  {
    $$.val = &ast.CreateSchema{
      Schema: $3,
    }
  }
| CREATE SCHEMA IF NOT EXISTS schema_name
  {
    $$.val = &ast.CreateSchema{
      Schema: $6,
      IfNotExists: true,
    }
  }
| CREATE SCHEMA error // SHOW HELP: CREATE SCHEMA

// %Help: CREATE TABLE - create a new table
// %Category: DDL
// %Text:
// CREATE [[GLOBAL | LOCAL] {TEMPORARY | TEMP}] TABLE [IF NOT EXISTS] <tablename> ( <elements...> ) [<interleave>] [<on_commit>]
// CREATE [[GLOBAL | LOCAL] {TEMPORARY | TEMP}] TABLE [IF NOT EXISTS] <tablename> [( <colnames...> )] AS <source> [<interleave>] [<on commit>]
//
// Table elements:
//    <name> <type> [<qualifiers...>]
//    [UNIQUE | INVERTED] INDEX [<name>] ( <colname> [ASC | DESC] [, ...] )
//                            [USING HASH WITH BUCKET_COUNT = <shard_buckets>] [{STORING | INCLUDE | COVERING} ( <colnames...> )] [<interleave>]
//    FAMILY [<name>] ( <colnames...> )
//    [CONSTRAINT <name>] <constraint>
//
// Table constraints:
//    PRIMARY KEY ( <colnames...> ) [USING HASH WITH BUCKET_COUNT = <shard_buckets>]
//    FOREIGN KEY ( <colnames...> ) REFERENCES <tablename> [( <colnames...> )] [ON DELETE {NO ACTION | RESTRICT}] [ON UPDATE {NO ACTION | RESTRICT}]
//    UNIQUE ( <colnames... ) [{STORING | INCLUDE | COVERING} ( <colnames...> )] [<interleave>]
//    CHECK ( <expr> )
//
// Column qualifiers:
//   [CONSTRAINT <constraintname>] {NULL | NOT NULL | UNIQUE | PRIMARY KEY | CHECK (<expr>) | DEFAULT <expr>}
//   FAMILY <familyname>, CREATE [IF NOT EXISTS] FAMILY [<familyname>]
//   REFERENCES <tablename> [( <colnames...> )] [ON DELETE {NO ACTION | RESTRICT}] [ON UPDATE {NO ACTION | RESTRICT}]
//   COLLATE <collationname>
//   AS ( <expr> ) STORED
//
// Interleave clause:
//    INTERLEAVE IN PARENT <tablename> ( <colnames...> ) [CASCADE | RESTRICT]
//
// On commit clause:
//    ON COMMIT {PRESERVE ROWS | DROP | DELETE ROWS}
//
// %SeeAlso: SHOW TABLES, CREATE VIEW, SHOW CREATE,
// WEBDOCS/create-table.html
// WEBDOCS/create-table-as.html
create_table_stmt:
  CREATE opt_temp_create_table TABLE table_name '(' opt_table_elem_list ')' opt_interleave opt_partition_by opt_table_with opt_create_table_on_commit
  {
    name := $4.unresolvedObjectName().ToTableName()
    $$.val = &ast.CreateTable{
      Table: name,
      IfNotExists: false,
      Interleave: $8.interleave(),
      Defs: $6.tblDefs(),
      AsSource: nil,
      PartitionBy: $9.partitionBy(),
      Temporary: $2.persistenceType(),
      StorageParams: $10.storageParams(),
      OnCommit: $11.createTableOnCommitSetting(),
    }
  }
| CREATE opt_temp_create_table TABLE IF NOT EXISTS table_name '(' opt_table_elem_list ')' opt_interleave opt_partition_by opt_table_with opt_create_table_on_commit
  {
    name := $7.unresolvedObjectName().ToTableName()
    $$.val = &ast.CreateTable{
      Table: name,
      IfNotExists: true,
      Interleave: $11.interleave(),
      Defs: $9.tblDefs(),
      AsSource: nil,
      PartitionBy: $12.partitionBy(),
      Temporary: $2.persistenceType(),
      StorageParams: $13.storageParams(),
      OnCommit: $14.createTableOnCommitSetting(),
    }
  }

opt_table_with:
  /* EMPTY */
  {
    $$.val = nil
  }
| WITHOUT OIDS
  {
    /* SKIP DOC */
    /* this is also the default in CockroachDB */
    $$.val = nil
  }
| WITH '(' storage_parameter_list ')'
  {
    /* SKIP DOC */
    $$.val = $3.storageParams()
  }
| WITH OIDS error
  {
    return unimplemented(sqllex, "create table with oids")
  }

opt_create_table_on_commit:
  /* EMPTY */
  {
    $$.val = ast.CreateTableOnCommitUnset
  }
| ON COMMIT PRESERVE ROWS
  {
    /* SKIP DOC */
    $$.val = ast.CreateTableOnCommitPreserveRows
  }
| ON COMMIT DELETE ROWS error
  {
    /* SKIP DOC */
    return unimplementedWithIssueDetail(sqllex, 46556, "delete rows")
  }
| ON COMMIT DROP error
  {
    /* SKIP DOC */
    return unimplementedWithIssueDetail(sqllex, 46556, "drop")
  }

storage_parameter:
  name '=' d_expr
  {
    $$.val = ast.StorageParam{Key: ast.Name($1), Value: $3.expr()}
  }
|  SCONST '=' d_expr
  {
    $$.val = ast.StorageParam{Key: ast.Name($1), Value: $3.expr()}
  }

storage_parameter_list:
  storage_parameter
  {
    $$.val = []ast.StorageParam{$1.storageParam()}
  }
|  storage_parameter_list ',' storage_parameter
  {
    $$.val = append($1.storageParams(), $3.storageParam())
  }

create_table_as_stmt:
  CREATE opt_temp_create_table TABLE table_name create_as_opt_col_list opt_table_with AS select_stmt opt_create_as_data opt_create_table_on_commit
  {
    name := $4.unresolvedObjectName().ToTableName()
    $$.val = &ast.CreateTable{
      Table: name,
      IfNotExists: false,
      Interleave: nil,
      Defs: $5.tblDefs(),
      AsSource: $8.slct(),
      StorageParams: $6.storageParams(),
      OnCommit: $10.createTableOnCommitSetting(),
    }
  }
| CREATE opt_temp_create_table TABLE IF NOT EXISTS table_name create_as_opt_col_list opt_table_with AS select_stmt opt_create_as_data opt_create_table_on_commit
  {
    name := $7.unresolvedObjectName().ToTableName()
    $$.val = &ast.CreateTable{
      Table: name,
      IfNotExists: true,
      Interleave: nil,
      Defs: $8.tblDefs(),
      AsSource: $11.slct(),
      StorageParams: $9.storageParams(),
      OnCommit: $13.createTableOnCommitSetting(),
    }
  }

opt_create_as_data:
  /* EMPTY */  { /* no error */ }
| WITH DATA    { /* SKIP DOC */ /* This is the default */ }
| WITH NO DATA { return unimplemented(sqllex, "create table as with no data") }

/*
 * Redundancy here is needed to avoid shift/reduce conflicts,
 * since TEMP is not a reserved word.  See also OptTempTableName.
 *
 * NOTE: we accept both GLOBAL and LOCAL options.  They currently do nothing,
 * but future versions might consider GLOBAL to request SQL-spec-compliant
 * temp table behavior.  Since we have no modules the
 * LOCAL keyword is really meaningless; furthermore, some other products
 * implement LOCAL as meaning the same as our default temp table behavior,
 * so we'll probably continue to treat LOCAL as a noise word.
 *
 * NOTE: PG only accepts GLOBAL/LOCAL keywords for temp tables -- not sequences
 * and views. These keywords are no-ops in PG. This behavior is replicated by
 * making the distinction between opt_temp and opt_temp_create_table.
 */
 opt_temp:
  TEMPORARY         { $$.val = true }
| TEMP              { $$.val = true }
| /*EMPTY*/         { $$.val = false }

opt_temp_create_table:
   opt_temp
|  LOCAL TEMPORARY   { $$.val = true }
| LOCAL TEMP        { $$.val = true }
| GLOBAL TEMPORARY  { $$.val = true }
| GLOBAL TEMP       { $$.val = true }
| UNLOGGED          { return unimplemented(sqllex, "create unlogged") }

opt_table_elem_list:
  table_elem_list
| /* EMPTY */
  {
    $$.val = ast.TableDefs(nil)
  }

table_elem_list:
  table_elem
  {
    $$.val = ast.TableDefs{$1.tblDef()}
  }
| table_elem_list ',' table_elem
  {
    $$.val = append($1.tblDefs(), $3.tblDef())
  }

table_elem:
  column_def
  {
    $$.val = $1.colDef()
  }
| index_def
| family_def
| table_constraint
  {
    $$.val = $1.constraintDef()
  }
| LIKE table_name like_table_option_list
  {
    $$.val = &ast.LikeTableDef{
      Name: $2.unresolvedObjectName().ToTableName(),
      Options: $3.likeTableOptionList(),
    }
  }

like_table_option_list:
  like_table_option_list INCLUDING like_table_option
  {
    $$.val = append($1.likeTableOptionList(), $3.likeTableOption())
  }
| like_table_option_list EXCLUDING like_table_option
  {
    opt := $3.likeTableOption()
    opt.Excluded = true
    $$.val = append($1.likeTableOptionList(), opt)
  }
| /* EMPTY */
  {
    $$.val = []ast.LikeTableOption(nil)
  }

like_table_option:
  COMMENTS			{ return unimplementedWithIssueDetail(sqllex, 47071, "like table in/excluding comments") }
| CONSTRAINTS		{ $$.val = ast.LikeTableOption{Opt: ast.LikeTableOptConstraints} }
| DEFAULTS			{ $$.val = ast.LikeTableOption{Opt: ast.LikeTableOptDefaults} }
| IDENTITY	  	{ return unimplementedWithIssueDetail(sqllex, 47071, "like table in/excluding identity") }
| GENERATED			{ $$.val = ast.LikeTableOption{Opt: ast.LikeTableOptGenerated} }
| INDEXES			{ $$.val = ast.LikeTableOption{Opt: ast.LikeTableOptIndexes} }
| STATISTICS		{ return unimplementedWithIssueDetail(sqllex, 47071, "like table in/excluding statistics") }
| STORAGE			{ return unimplementedWithIssueDetail(sqllex, 47071, "like table in/excluding storage") }
| ALL				{ $$.val = ast.LikeTableOption{Opt: ast.LikeTableOptAll} }


opt_interleave:
  INTERLEAVE IN PARENT table_name '(' name_list ')' opt_interleave_drop_behavior
  {
    name := $4.unresolvedObjectName().ToTableName()
    $$.val = &ast.InterleaveDef{
      Parent: name,
      Fields: $6.nameList(),
      DropBehavior: $8.dropBehavior(),
    }
  }
| /* EMPTY */
  {
    $$.val = (*ast.InterleaveDef)(nil)
  }

// TODO(dan): This can be removed in favor of opt_drop_behavior when #7854 is fixed.
opt_interleave_drop_behavior:
  CASCADE
  {
    /* SKIP DOC */
    $$.val = ast.DropCascade
  }
| RESTRICT
  {
    /* SKIP DOC */
    $$.val = ast.DropRestrict
  }
| /* EMPTY */
  {
    $$.val = ast.DropDefault
  }

partition:
  PARTITION partition_name
  {
    $$ = $2
  }

opt_partition:
  partition
| /* EMPTY */
  {
    $$ = ""
  }

opt_partition_by:
  partition_by
| /* EMPTY */
  {
    $$.val = (*ast.PartitionBy)(nil)
  }

partition_by:
  PARTITION BY LIST '(' name_list ')' '(' list_partitions ')'
  {
    $$.val = &ast.PartitionBy{
      Fields: $5.nameList(),
      List: $8.listPartitions(),
    }
  }
| PARTITION BY RANGE '(' name_list ')' '(' range_partitions ')'
  {
    $$.val = &ast.PartitionBy{
      Fields: $5.nameList(),
      Range: $8.rangePartitions(),
    }
  }
| PARTITION BY NOTHING
  {
    $$.val = (*ast.PartitionBy)(nil)
  }

list_partitions:
  list_partition
  {
    $$.val = []ast.ListPartition{$1.listPartition()}
  }
| list_partitions ',' list_partition
  {
    $$.val = append($1.listPartitions(), $3.listPartition())
  }

list_partition:
  partition VALUES IN '(' expr_list ')' opt_partition_by
  {
    $$.val = ast.ListPartition{
      Name: ast.UnrestrictedName($1),
      Exprs: $5.exprs(),
      Subpartition: $7.partitionBy(),
    }
  }

range_partitions:
  range_partition
  {
    $$.val = []ast.RangePartition{$1.rangePartition()}
  }
| range_partitions ',' range_partition
  {
    $$.val = append($1.rangePartitions(), $3.rangePartition())
  }

range_partition:
  partition VALUES FROM '(' expr_list ')' TO '(' expr_list ')' opt_partition_by
  {
    $$.val = ast.RangePartition{
      Name: ast.UnrestrictedName($1),
      From: $5.exprs(),
      To: $9.exprs(),
      Subpartition: $11.partitionBy(),
    }
  }

// Treat SERIAL pseudo-types as separate case so that types.T does not have to
// support them as first-class types (e.g. they should not be supported as CAST
// target types).
column_def:
  column_name typename col_qual_list
  {
    typ := $2.typeReference()
    tableDef, err := ast.NewColumnTableDef(ast.Name($1), typ, ast.IsReferenceSerialType(typ), $3.colQuals())
    if err != nil {
      return setErr(sqllex, err)
    }
    $$.val = tableDef
  }

col_qual_list:
  col_qual_list col_qualification
  {
    $$.val = append($1.colQuals(), $2.colQual())
  }
| /* EMPTY */
  {
    $$.val = []ast.NamedColumnQualification(nil)
  }

col_qualification:
  CONSTRAINT constraint_name col_qualification_elem
  {
    $$.val = ast.NamedColumnQualification{Name: ast.Name($2), Qualification: $3.colQualElem()}
  }
| col_qualification_elem
  {
    $$.val = ast.NamedColumnQualification{Qualification: $1.colQualElem()}
  }
| COLLATE collation_name
  {
    $$.val = ast.NamedColumnQualification{Qualification: ast.ColumnCollation($2)}
  }
| FAMILY family_name
  {
    $$.val = ast.NamedColumnQualification{Qualification: &ast.ColumnFamilyConstraint{Family: ast.Name($2)}}
  }
| CREATE FAMILY family_name
  {
    $$.val = ast.NamedColumnQualification{Qualification: &ast.ColumnFamilyConstraint{Family: ast.Name($3), Create: true}}
  }
| CREATE FAMILY
  {
    $$.val = ast.NamedColumnQualification{Qualification: &ast.ColumnFamilyConstraint{Create: true}}
  }
| CREATE IF NOT EXISTS FAMILY family_name
  {
    $$.val = ast.NamedColumnQualification{Qualification: &ast.ColumnFamilyConstraint{Family: ast.Name($6), Create: true, IfNotExists: true}}
  }

// DEFAULT NULL is already the default for Postgres. But define it here and
// carry it forward into the system to make it explicit.
// - thomas 1998-09-13
//
// WITH NULL and NULL are not SQL-standard syntax elements, so leave them
// out. Use DEFAULT NULL to explicitly indicate that a column may have that
// value. WITH NULL leads to shift/reduce conflicts with WITH TIME ZONE anyway.
// - thomas 1999-01-08
//
// DEFAULT expression must be b_expr not a_expr to prevent shift/reduce
// conflict on NOT (since NOT might start a subsequent NOT NULL constraint, or
// be part of a_expr NOT LIKE or similar constructs).
col_qualification_elem:
  NOT NULL
  {
    $$.val = ast.NotNullConstraint{}
  }
| NULL
  {
    $$.val = ast.NullConstraint{}
  }
| UNIQUE
  {
    $$.val = ast.UniqueConstraint{}
  }
| PRIMARY KEY
  {
    $$.val = ast.PrimaryKeyConstraint{}
  }
| PRIMARY KEY USING HASH WITH BUCKET_COUNT '=' a_expr
{
  $$.val = ast.ShardedPrimaryKeyConstraint{
    Sharded: true,
    ShardBuckets: $8.expr(),
  }
}
| CHECK '(' a_expr ')'
  {
    $$.val = &ast.ColumnCheckConstraint{Expr: $3.expr()}
  }
| DEFAULT b_expr
  {
    $$.val = &ast.ColumnDefault{Expr: $2.expr()}
  }
| REFERENCES table_name opt_name_parens key_match reference_actions
 {
    name := $2.unresolvedObjectName().ToTableName()
    $$.val = &ast.ColumnFKConstraint{
      Table: name,
      Col: ast.Name($3),
      Actions: $5.referenceActions(),
      Match: $4.compositeKeyMatchMethod(),
    }
 }
| generated_as '(' a_expr ')' STORED
 {
    $$.val = &ast.ColumnComputedDef{Expr: $3.expr()}
 }
| generated_as '(' a_expr ')' VIRTUAL
 {
    return unimplemented(sqllex, "virtual computed columns")
 }
| generated_as error
 {
    sqllex.Error("use AS ( <expr> ) STORED")
    return 1
 }

// GENERATED ALWAYS is a noise word for compatibility with Postgres.
generated_as:
  AS {}
| GENERATED_ALWAYS ALWAYS AS {}


index_def:
  INDEX opt_index_name '(' index_params ')' opt_hash_sharded opt_storing opt_interleave opt_partition_by opt_where_clause
  {
    $$.val = &ast.IndexTableDef{
      Name:    ast.Name($2),
      Columns: $4.idxElems(),
      Sharded: $6.shardedIndexDef(),
      Storing: $7.nameList(),
      Interleave: $8.interleave(),
      PartitionBy: $9.partitionBy(),
      Predicate: $10.expr(),
    }
  }
| UNIQUE INDEX opt_index_name '(' index_params ')' opt_hash_sharded opt_storing opt_interleave opt_partition_by opt_where_clause
  {
    $$.val = &ast.UniqueConstraintTableDef{
      IndexTableDef: ast.IndexTableDef {
        Name:    ast.Name($3),
        Columns: $5.idxElems(),
        Sharded: $7.shardedIndexDef(),
        Storing: $8.nameList(),
        Interleave: $9.interleave(),
        PartitionBy: $10.partitionBy(),
        Predicate: $11.expr(),
      },
    }
  }
| INVERTED INDEX opt_name '(' index_params ')' opt_where_clause
  {
    $$.val = &ast.IndexTableDef{
      Name:    ast.Name($3),
      Columns: $5.idxElems(),
      Inverted: true,
      Predicate: $7.expr(),
    }
  }

family_def:
  FAMILY opt_family_name '(' name_list ')'
  {
    $$.val = &ast.FamilyTableDef{
      Name: ast.Name($2),
      Columns: $4.nameList(),
    }
  }

// constraint_elem specifies constraint syntax which is not embedded into a
// column definition. col_qualification_elem specifies the embedded form.
// - thomas 1997-12-03
table_constraint:
  CONSTRAINT constraint_name constraint_elem
  {
    $$.val = $3.constraintDef()
    $$.val.(ast.ConstraintTableDef).SetName(ast.Name($2))
  }
| constraint_elem
  {
    $$.val = $1.constraintDef()
  }

constraint_elem:
  CHECK '(' a_expr ')' opt_deferrable
  {
    $$.val = &ast.CheckConstraintTableDef{
      Expr: $3.expr(),
    }
  }
| UNIQUE '(' index_params ')' opt_storing opt_interleave opt_partition_by opt_deferrable opt_where_clause
  {
    $$.val = &ast.UniqueConstraintTableDef{
      IndexTableDef: ast.IndexTableDef{
        Columns: $3.idxElems(),
        Storing: $5.nameList(),
        Interleave: $6.interleave(),
        PartitionBy: $7.partitionBy(),
        Predicate: $9.expr(),
      },
    }
  }
| PRIMARY KEY '(' index_params ')' opt_hash_sharded opt_interleave
  {
    $$.val = &ast.UniqueConstraintTableDef{
      IndexTableDef: ast.IndexTableDef{
        Columns: $4.idxElems(),
        Sharded: $6.shardedIndexDef(),
        Interleave: $7.interleave(),
      },
      PrimaryKey: true,
    }
  }
| FOREIGN KEY '(' name_list ')' REFERENCES table_name
    opt_column_list key_match reference_actions opt_deferrable
  {
    name := $7.unresolvedObjectName().ToTableName()
    $$.val = &ast.ForeignKeyConstraintTableDef{
      Table: name,
      FromCols: $4.nameList(),
      ToCols: $8.nameList(),
      Match: $9.compositeKeyMatchMethod(),
      Actions: $10.referenceActions(),
    }
  }
| EXCLUDE USING error
  {
    return unimplementedWithIssueDetail(sqllex, 46657, "add constraint exclude using")
  }


create_as_opt_col_list:
  '(' create_as_table_defs ')'
  {
    $$.val = $2.val
  }
| /* EMPTY */
  {
    $$.val = ast.TableDefs(nil)
  }

create_as_table_defs:
  column_name create_as_col_qual_list
  {
    tableDef, err := ast.NewColumnTableDef(ast.Name($1), nil, false, $2.colQuals())
    if err != nil {
      return setErr(sqllex, err)
    }

    var colToTableDef ast.TableDef = tableDef
    $$.val = ast.TableDefs{colToTableDef}
  }
| create_as_table_defs ',' column_name create_as_col_qual_list
  {
    tableDef, err := ast.NewColumnTableDef(ast.Name($3), nil, false, $4.colQuals())
    if err != nil {
      return setErr(sqllex, err)
    }

    var colToTableDef ast.TableDef = tableDef

    $$.val = append($1.tblDefs(), colToTableDef)
  }
| create_as_table_defs ',' family_def
  {
    $$.val = append($1.tblDefs(), $3.tblDef())
  }
| create_as_table_defs ',' create_as_constraint_def
{
  var constraintToTableDef ast.TableDef = $3.constraintDef()
  $$.val = append($1.tblDefs(), constraintToTableDef)
}

create_as_constraint_def:
  create_as_constraint_elem
  {
    $$.val = $1.constraintDef()
  }

create_as_constraint_elem:
  PRIMARY KEY '(' create_as_params ')'
  {
    $$.val = &ast.UniqueConstraintTableDef{
      IndexTableDef: ast.IndexTableDef{
        Columns: $4.idxElems(),
      },
      PrimaryKey:    true,
    }
  }

create_as_params:
  create_as_param
  {
    $$.val = ast.IndexElemList{$1.idxElem()}
  }
| create_as_params ',' create_as_param
  {
    $$.val = append($1.idxElems(), $3.idxElem())
  }

create_as_param:
  column_name
  {
    $$.val = ast.IndexElem{Column: ast.Name($1)}
  }

create_as_col_qual_list:
  create_as_col_qual_list create_as_col_qualification
  {
    $$.val = append($1.colQuals(), $2.colQual())
  }
| /* EMPTY */
  {
    $$.val = []ast.NamedColumnQualification(nil)
  }

create_as_col_qualification:
  create_as_col_qualification_elem
  {
    $$.val = ast.NamedColumnQualification{Qualification: $1.colQualElem()}
  }
| FAMILY family_name
  {
    $$.val = ast.NamedColumnQualification{Qualification: &ast.ColumnFamilyConstraint{Family: ast.Name($2)}}
  }

create_as_col_qualification_elem:
  PRIMARY KEY
  {
    $$.val = ast.PrimaryKeyConstraint{}
  }

opt_deferrable:
  /* EMPTY */ { /* no error */ }
| DEFERRABLE { return unimplementedWithIssueDetail(sqllex, 31632, "deferrable") }
| DEFERRABLE INITIALLY DEFERRED { return unimplementedWithIssueDetail(sqllex, 31632, "def initially deferred") }
| DEFERRABLE INITIALLY IMMEDIATE { return unimplementedWithIssueDetail(sqllex, 31632, "def initially immediate") }
| INITIALLY DEFERRED { return unimplementedWithIssueDetail(sqllex, 31632, "initially deferred") }
| INITIALLY IMMEDIATE { return unimplementedWithIssueDetail(sqllex, 31632, "initially immediate") }

storing:
  COVERING
| STORING
| INCLUDE

// TODO(pmattis): It would be nice to support a syntax like STORING
// ALL or STORING (*). The syntax addition is straightforward, but we
// need to be careful with the rest of the implementation. In
// particular, columns stored at indexes are currently encoded in such
// a way that adding a new column would require rewriting the existing
// index values. We will need to change the storage format so that it
// is a list of <columnID, value> pairs which will allow both adding
// and dropping columns without rewriting indexes that are storing the
// adjusted column.
opt_storing:
  storing '(' name_list ')'
  {
    $$.val = $3.nameList()
  }
| /* EMPTY */
  {
    $$.val = ast.NameList(nil)
  }

opt_hash_sharded:
  USING HASH WITH BUCKET_COUNT '=' a_expr
  {
    $$.val = &ast.ShardedIndexDef{
      ShardBuckets: $6.expr(),
    }
  }
  | /* EMPTY */
  {
    $$.val = (*ast.ShardedIndexDef)(nil)
  }

opt_column_list:
  '(' name_list ')'
  {
    $$.val = $2.nameList()
  }
| /* EMPTY */
  {
    $$.val = ast.NameList(nil)
  }

// https://www.postgresql.org/docs/10/sql-createtable.html
//
// "A value inserted into the referencing column(s) is matched against
// the values of the referenced table and referenced columns using the
// given match type. There are three match types: MATCH FULL, MATCH
// PARTIAL, and MATCH SIMPLE (which is the default). MATCH FULL will
// not allow one column of a multicolumn foreign key to be null unless
// all foreign key columns are null; if they are all null, the row is
// not required to have a match in the referenced table. MATCH SIMPLE
// allows any of the foreign key columns to be null; if any of them
// are null, the row is not required to have a match in the referenced
// table. MATCH PARTIAL is not yet implemented. (Of course, NOT NULL
// constraints can be applied to the referencing column(s) to prevent
// these cases from arising.)"
key_match:
  MATCH SIMPLE
  {
    $$.val = ast.MatchSimple
  }
| MATCH FULL
  {
    $$.val = ast.MatchFull
  }
| MATCH PARTIAL
  {
    return unimplementedWithIssueDetail(sqllex, 20305, "match partial")
  }
| /* EMPTY */
  {
    $$.val = ast.MatchSimple
  }

// We combine the update and delete actions into one value temporarily for
// simplicity of parsing, and then break them down again in the calling
// production.
reference_actions:
  reference_on_update
  {
     $$.val = ast.ReferenceActions{Update: $1.referenceAction()}
  }
| reference_on_delete
  {
     $$.val = ast.ReferenceActions{Delete: $1.referenceAction()}
  }
| reference_on_update reference_on_delete
  {
    $$.val = ast.ReferenceActions{Update: $1.referenceAction(), Delete: $2.referenceAction()}
  }
| reference_on_delete reference_on_update
  {
    $$.val = ast.ReferenceActions{Delete: $1.referenceAction(), Update: $2.referenceAction()}
  }
| /* EMPTY */
  {
    $$.val = ast.ReferenceActions{}
  }

reference_on_update:
  ON UPDATE reference_action
  {
    $$.val = $3.referenceAction()
  }

reference_on_delete:
  ON DELETE reference_action
  {
    $$.val = $3.referenceAction()
  }

reference_action:
// NO ACTION is currently the default behavior. It is functionally the same as
// RESTRICT.
  NO ACTION
  {
    $$.val = ast.NoAction
  }
| RESTRICT
  {
    $$.val = ast.Restrict
  }
| CASCADE
  {
    $$.val = ast.Cascade
  }
| SET NULL
  {
    $$.val = ast.SetNull
  }
| SET DEFAULT
  {
    $$.val = ast.SetDefault
  }

// %Help: CREATE SEQUENCE - create a new sequence
// %Category: DDL
// %Text:
// CREATE [TEMPORARY | TEMP] SEQUENCE <seqname>
//   [INCREMENT <increment>]
//   [MINVALUE <minvalue> | NO MINVALUE]
//   [MAXVALUE <maxvalue> | NO MAXVALUE]
//   [START [WITH] <start>]
//   [CACHE <cache>]
//   [NO CYCLE]
//   [VIRTUAL]
//
// %SeeAlso: CREATE TABLE
create_sequence_stmt:
  CREATE opt_temp SEQUENCE sequence_name opt_sequence_option_list
  {
    name := $4.unresolvedObjectName().ToTableName()
    $$.val = &ast.CreateSequence {
      Name: name,
      Temporary: $2.persistenceType(),
      Options: $5.seqOpts(),
    }
  }
| CREATE opt_temp SEQUENCE IF NOT EXISTS sequence_name opt_sequence_option_list
  {
    name := $7.unresolvedObjectName().ToTableName()
    $$.val = &ast.CreateSequence {
      Name: name, Options: $8.seqOpts(),
      Temporary: $2.persistenceType(),
      IfNotExists: true,
    }
  }
| CREATE opt_temp SEQUENCE error // SHOW HELP: CREATE SEQUENCE

opt_sequence_option_list:
  sequence_option_list
| /* EMPTY */          { $$.val = []ast.SequenceOption(nil) }

sequence_option_list:
  sequence_option_elem                       { $$.val = []ast.SequenceOption{$1.seqOpt()} }
| sequence_option_list sequence_option_elem  { $$.val = append($1.seqOpts(), $2.seqOpt()) }

sequence_option_elem:
  AS typename                  { return unimplementedWithIssueDetail(sqllex, 25110, $2.typeReference().SQLString()) }
| CYCLE                        { /* SKIP DOC */
                                 $$.val = ast.SequenceOption{Name: ast.SeqOptCycle} }
| NO CYCLE                     { $$.val = ast.SequenceOption{Name: ast.SeqOptNoCycle} }
| OWNED BY NONE                { $$.val = ast.SequenceOption{Name: ast.SeqOptOwnedBy, ColumnItemVal: nil} }
| OWNED BY column_path         { varName, err := $3.unresolvedName().NormalizeVarName()
                                     if err != nil {
                                       return setErr(sqllex, err)
                                     }
                                     columnItem, ok := varName.(*ast.ColumnItem)
                                     if !ok {
                                       sqllex.Error(fmt.Sprintf("invalid column name: %q", ast.ErrString($3.unresolvedName())))
                                             return 1
                                     }
                                 $$.val = ast.SequenceOption{Name: ast.SeqOptOwnedBy, ColumnItemVal: columnItem} }
| CACHE signed_iconst64        { /* SKIP DOC */
                                 x := $2.int64()
                                 $$.val = ast.SequenceOption{Name: ast.SeqOptCache, IntVal: &x} }
| INCREMENT signed_iconst64    { x := $2.int64()
                                 $$.val = ast.SequenceOption{Name: ast.SeqOptIncrement, IntVal: &x} }
| INCREMENT BY signed_iconst64 { x := $3.int64()
                                 $$.val = ast.SequenceOption{Name: ast.SeqOptIncrement, IntVal: &x, OptionalWord: true} }
| MINVALUE signed_iconst64     { x := $2.int64()
                                 $$.val = ast.SequenceOption{Name: ast.SeqOptMinValue, IntVal: &x} }
| NO MINVALUE                  { $$.val = ast.SequenceOption{Name: ast.SeqOptMinValue} }
| MAXVALUE signed_iconst64     { x := $2.int64()
                                 $$.val = ast.SequenceOption{Name: ast.SeqOptMaxValue, IntVal: &x} }
| NO MAXVALUE                  { $$.val = ast.SequenceOption{Name: ast.SeqOptMaxValue} }
| START signed_iconst64        { x := $2.int64()
                                 $$.val = ast.SequenceOption{Name: ast.SeqOptStart, IntVal: &x} }
| START WITH signed_iconst64   { x := $3.int64()
                                 $$.val = ast.SequenceOption{Name: ast.SeqOptStart, IntVal: &x, OptionalWord: true} }
| VIRTUAL                      { $$.val = ast.SequenceOption{Name: ast.SeqOptVirtual} }

// %Help: TRUNCATE - empty one or more tables
// %Category: DML
// %Text: TRUNCATE [TABLE] <tablename> [, ...] [CASCADE | RESTRICT]
// %SeeAlso: WEBDOCS/truncate.html
truncate_stmt:
  TRUNCATE opt_table relation_expr_list opt_drop_behavior
  {
    $$.val = &ast.Truncate{Tables: $3.tableNames(), DropBehavior: $4.dropBehavior()}
  }
| TRUNCATE error // SHOW HELP: TRUNCATE

password_clause:
  PASSWORD string_or_placeholder
  {
    $$.val = ast.KVOption{Key: ast.Name($1), Value: $2.expr()}
  }
| PASSWORD NULL
  {
    $$.val = ast.KVOption{Key: ast.Name($1), Value: ast.DNull}
  }

// %Help: CREATE ROLE - define a new role
// %Category: Priv
// %Text: CREATE ROLE [IF NOT EXISTS] <name> [ [WITH] <OPTIONS...> ]
// %SeeAlso: ALTER ROLE, DROP ROLE, SHOW ROLES
create_role_stmt:
  CREATE role_or_group_or_user string_or_placeholder opt_role_options
  {
    $$.val = &ast.CreateRole{Name: $3.expr(), KVOptions: $4.kvOptions(), IsRole: $2.bool()}
  }
| CREATE role_or_group_or_user IF NOT EXISTS string_or_placeholder opt_role_options
  {
    $$.val = &ast.CreateRole{Name: $6.expr(), IfNotExists: true, KVOptions: $7.kvOptions(), IsRole: $2.bool()}
  }
| CREATE role_or_group_or_user error // SHOW HELP: CREATE ROLE

// %Help: ALTER ROLE - alter a role
// %Category: Priv
// %Text: ALTER ROLE <name> [WITH] <options...>
// %SeeAlso: CREATE ROLE, DROP ROLE, SHOW ROLES
alter_role_stmt:
  ALTER role_or_group_or_user string_or_placeholder opt_role_options
{
  $$.val = &ast.AlterRole{Name: $3.expr(), KVOptions: $4.kvOptions(), IsRole: $2.bool()}
}
| ALTER role_or_group_or_user IF EXISTS string_or_placeholder opt_role_options
{
  $$.val = &ast.AlterRole{Name: $5.expr(), IfExists: true, KVOptions: $6.kvOptions(), IsRole: $2.bool()}
}
| ALTER role_or_group_or_user error // SHOW HELP: ALTER ROLE

// "CREATE GROUP is now an alias for CREATE ROLE"
// https://www.postgresql.org/docs/10/static/sql-creategroup.html
role_or_group_or_user:
  ROLE
  {
    $$.val = true
  }
| GROUP
  {
    /* SKIP DOC */
    $$.val = true
  }
| USER
  {
    $$.val = false
  }

// %Help: CREATE VIEW - create a new view
// %Category: DDL
// %Text: CREATE [TEMPORARY | TEMP] VIEW <viewname> [( <colnames...> )] AS <source>
// %SeeAlso: CREATE TABLE, SHOW CREATE, WEBDOCS/create-view.html
create_view_stmt:
  CREATE opt_temp opt_view_recursive VIEW view_name opt_column_list AS select_stmt
  {
    name := $5.unresolvedObjectName().ToTableName()
    $$.val = &ast.CreateView{
      Name: name,
      ColumnNames: $6.nameList(),
      AsSource: $8.slct(),
      Temporary: $2.persistenceType(),
      IfNotExists: false,
      Replace: false,
    }
  }
// We cannot use a rule like opt_or_replace here as that would cause a conflict
// with the opt_temp rule.
| CREATE OR REPLACE opt_temp opt_view_recursive VIEW view_name opt_column_list AS select_stmt
  {
    name := $7.unresolvedObjectName().ToTableName()
    $$.val = &ast.CreateView{
      Name: name,
      ColumnNames: $8.nameList(),
      AsSource: $10.slct(),
      Temporary: $4.persistenceType(),
      IfNotExists: false,
      Replace: true,
    }
  }
| CREATE opt_temp opt_view_recursive VIEW IF NOT EXISTS view_name opt_column_list AS select_stmt
  {
    name := $8.unresolvedObjectName().ToTableName()
    $$.val = &ast.CreateView{
      Name: name,
      ColumnNames: $9.nameList(),
      AsSource: $11.slct(),
      Temporary: $2.persistenceType(),
      IfNotExists: true,
      Replace: false,
    }
  }
| CREATE opt_temp opt_view_recursive VIEW error // SHOW HELP: CREATE VIEW

role_option:
  CREATEROLE
  {
    $$.val = ast.KVOption{Key: ast.Name($1), Value: nil}
  }
| NOCREATEROLE
	{
		$$.val = ast.KVOption{Key: ast.Name($1), Value: nil}
	}
| LOGIN
	{
		$$.val = ast.KVOption{Key: ast.Name($1), Value: nil}
	}
| NOLOGIN
	{
		$$.val = ast.KVOption{Key: ast.Name($1), Value: nil}
	}
| password_clause
| valid_until_clause

role_options:
  role_option
  {
    $$.val = []ast.KVOption{$1.kvOption()}
  }
|  role_options role_option
  {
    $$.val = append($1.kvOptions(), $2.kvOption())
  }

opt_role_options:
	opt_with role_options
	{
		$$.val = $2.kvOptions()
	}
| /* EMPTY */
	{
		$$.val = nil
	}

valid_until_clause:
  VALID UNTIL string_or_placeholder
  {
		$$.val = ast.KVOption{Key: ast.Name(fmt.Sprintf("%s_%s",$1, $2)), Value: $3.expr()}
  }
| VALID UNTIL NULL
  {
		$$.val = ast.KVOption{Key: ast.Name(fmt.Sprintf("%s_%s",$1, $2)), Value: ast.DNull}
	}

opt_view_recursive:
  /* EMPTY */ { /* no error */ }
| RECURSIVE { return unimplemented(sqllex, "create recursive view") }


// %Help: CREATE TYPE -- create a type
// %Category: DDL
// %Text: CREATE TYPE <type_name> AS ENUM (...)
create_type_stmt:
  // Enum types.
  CREATE TYPE type_name AS ENUM '(' opt_enum_val_list ')'
  {
    $$.val = &ast.CreateType{
      TypeName: $3.unresolvedObjectName(),
      Variety: ast.Enum,
      EnumLabels: $7.strs(),
    }
  }
| CREATE TYPE error // SHOW HELP: CREATE TYPE
  // Record/Composite types.
| CREATE TYPE type_name AS '(' error      { return unimplementedWithIssue(sqllex, 27792) }
  // Range types.
| CREATE TYPE type_name AS RANGE error    { return unimplementedWithIssue(sqllex, 27791) }
  // Base (primitive) types.
| CREATE TYPE type_name '(' error         { return unimplementedWithIssueDetail(sqllex, 27793, "base") }
  // Shell types, gateway to define base types using the previous syntax.
| CREATE TYPE type_name                   { return unimplementedWithIssueDetail(sqllex, 27793, "shell") }
  // Domain types.
| CREATE DOMAIN type_name error           { return unimplementedWithIssueDetail(sqllex, 27796, "create") }

opt_enum_val_list:
  enum_val_list
  {
    $$.val = $1.strs()
  }
| /* EMPTY */
  {
    $$.val = []string(nil)
  }

enum_val_list:
  SCONST
  {
    $$.val = []string{$1}
  }
| enum_val_list ',' SCONST
  {
    $$.val = append($1.strs(), $3)
  }

// %Help: CREATE INDEX - create a new index
// %Category: DDL
// %Text:
// CREATE [UNIQUE | INVERTED] INDEX [CONCURRENTLY] [IF NOT EXISTS] [<idxname>]
//        ON <tablename> ( <colname> [ASC | DESC] [, ...] )
//        [USING HASH WITH BUCKET_COUNT = <shard_buckets>] [STORING ( <colnames...> )] [<interleave>]
//
// Interleave clause:
//    INTERLEAVE IN PARENT <tablename> ( <colnames...> ) [CASCADE | RESTRICT]
//
// %SeeAlso: CREATE TABLE, SHOW INDEXES, SHOW CREATE,
// WEBDOCS/create-index.html
create_index_stmt:
  CREATE opt_unique INDEX opt_concurrently opt_index_name ON table_name opt_using_gin_btree '(' index_params ')' opt_hash_sharded opt_storing opt_interleave opt_partition_by opt_where_clause
  {
    table := $7.unresolvedObjectName().ToTableName()
    $$.val = &ast.CreateIndex{
      Name:    ast.Name($5),
      Table:   table,
      Unique:  $2.bool(),
      Columns: $10.idxElems(),
      Sharded: $12.shardedIndexDef(),
      Storing: $13.nameList(),
      Interleave: $14.interleave(),
      PartitionBy: $15.partitionBy(),
      Predicate: $16.expr(),
      Inverted: $8.bool(),
      Concurrently: $4.bool(),
    }
  }
| CREATE opt_unique INDEX opt_concurrently IF NOT EXISTS index_name ON table_name opt_using_gin_btree '(' index_params ')' opt_hash_sharded opt_storing opt_interleave opt_partition_by opt_where_clause
  {
    table := $10.unresolvedObjectName().ToTableName()
    $$.val = &ast.CreateIndex{
      Name:        ast.Name($8),
      Table:       table,
      Unique:      $2.bool(),
      IfNotExists: true,
      Columns:     $13.idxElems(),
      Sharded:     $15.shardedIndexDef(),
      Storing:     $16.nameList(),
      Interleave:  $17.interleave(),
      PartitionBy: $18.partitionBy(),
      Inverted:    $11.bool(),
      Predicate:   $19.expr(),
      Concurrently: $4.bool(),
    }
  }
| CREATE opt_unique INVERTED INDEX opt_concurrently opt_index_name ON table_name '(' index_params ')' opt_storing opt_interleave opt_partition_by opt_where_clause
  {
    table := $8.unresolvedObjectName().ToTableName()
    $$.val = &ast.CreateIndex{
      Name:       ast.Name($6),
      Table:      table,
      Unique:     $2.bool(),
      Inverted:   true,
      Columns:    $10.idxElems(),
      Storing:     $12.nameList(),
      Interleave:  $13.interleave(),
      PartitionBy: $14.partitionBy(),
      Predicate:   $15.expr(),
      Concurrently: $5.bool(),
    }
  }
| CREATE opt_unique INVERTED INDEX opt_concurrently IF NOT EXISTS index_name ON table_name '(' index_params ')' opt_storing opt_interleave opt_partition_by opt_where_clause
  {
    table := $11.unresolvedObjectName().ToTableName()
    $$.val = &ast.CreateIndex{
      Name:        ast.Name($9),
      Table:       table,
      Unique:      $2.bool(),
      Inverted:    true,
      IfNotExists: true,
      Columns:     $13.idxElems(),
      Storing:     $15.nameList(),
      Interleave:  $16.interleave(),
      PartitionBy: $17.partitionBy(),
      Predicate:   $18.expr(),
      Concurrently: $5.bool(),
    }
  }
| CREATE opt_unique INDEX error // SHOW HELP: CREATE INDEX

opt_using_gin_btree:
  USING name
  {
    /* FORCE DOC */
    switch $2 {
      case "gin":
        $$.val = true
      case "btree":
        $$.val = false
      case "hash", "gist", "spgist", "brin":
        return unimplemented(sqllex, "index using " + $2)
      default:
        sqllex.Error("unrecognized access method: " + $2)
        return 1
    }
  }
| /* EMPTY */
  {
    $$.val = false
  }

opt_concurrently:
  CONCURRENTLY
  {
    $$.val = true
  }
| /* EMPTY */
  {
    $$.val = false
  }

opt_unique:
  UNIQUE
  {
    $$.val = true
  }
| /* EMPTY */
  {
    $$.val = false
  }

index_params:
  index_elem
  {
    $$.val = ast.IndexElemList{$1.idxElem()}
  }
| index_params ',' index_elem
  {
    $$.val = append($1.idxElems(), $3.idxElem())
  }

// Index attributes can be either simple column references, or arbitrary
// expressions in parens. For backwards-compatibility reasons, we allow an
// expression that is just a function call to be written without parens.
index_elem:
  a_expr opt_asc_desc opt_nulls_order
  {
    /* FORCE DOC */
    e := $1.expr()
    dir := $2.dir()
    nullsOrder := $3.nullsOrder()
    // We currently only support the opposite of Postgres defaults.
    if nullsOrder != ast.DefaultNullsOrder {
      if dir == ast.Descending && nullsOrder == ast.NullsFirst {
        return unimplementedWithIssue(sqllex, 6224)
      }
      if dir != ast.Descending && nullsOrder == ast.NullsLast {
        return unimplementedWithIssue(sqllex, 6224)
      }
    }
    if colName, ok := e.(*ast.UnresolvedName); ok && colName.NumParts == 1 {
      $$.val = ast.IndexElem{Column: ast.Name(colName.Parts[0]), Direction: dir, NullsOrder: nullsOrder}
    } else {
      return unimplementedWithIssueDetail(sqllex, 9682, fmt.Sprintf("%T", e))
    }
  }

opt_collate:
  COLLATE collation_name { $$ = $2 }
| /* EMPTY */ { $$ = "" }

opt_asc_desc:
  ASC
  {
    $$.val = ast.Ascending
  }
| DESC
  {
    $$.val = ast.Descending
  }
| /* EMPTY */
  {
    $$.val = ast.DefaultDirection
  }

alter_rename_database_stmt:
  ALTER DATABASE database_name RENAME TO database_name
  {
    $$.val = &ast.RenameDatabase{Name: ast.Name($3), NewName: ast.Name($6)}
  }

alter_rename_table_stmt:
  ALTER TABLE relation_expr RENAME TO table_name
  {
    name := $3.unresolvedObjectName()
    newName := $6.unresolvedObjectName()
    $$.val = &ast.RenameTable{Name: name, NewName: newName, IfExists: false, IsView: false}
  }
| ALTER TABLE IF EXISTS relation_expr RENAME TO table_name
  {
    name := $5.unresolvedObjectName()
    newName := $8.unresolvedObjectName()
    $$.val = &ast.RenameTable{Name: name, NewName: newName, IfExists: true, IsView: false}
  }

alter_rename_view_stmt:
  ALTER VIEW relation_expr RENAME TO view_name
  {
    name := $3.unresolvedObjectName()
    newName := $6.unresolvedObjectName()
    $$.val = &ast.RenameTable{Name: name, NewName: newName, IfExists: false, IsView: true}
  }
| ALTER VIEW IF EXISTS relation_expr RENAME TO view_name
  {
    name := $5.unresolvedObjectName()
    newName := $8.unresolvedObjectName()
    $$.val = &ast.RenameTable{Name: name, NewName: newName, IfExists: true, IsView: true}
  }

alter_rename_sequence_stmt:
  ALTER SEQUENCE relation_expr RENAME TO sequence_name
  {
    name := $3.unresolvedObjectName()
    newName := $6.unresolvedObjectName()
    $$.val = &ast.RenameTable{Name: name, NewName: newName, IfExists: false, IsSequence: true}
  }
| ALTER SEQUENCE IF EXISTS relation_expr RENAME TO sequence_name
  {
    name := $5.unresolvedObjectName()
    newName := $8.unresolvedObjectName()
    $$.val = &ast.RenameTable{Name: name, NewName: newName, IfExists: true, IsSequence: true}
  }

alter_rename_index_stmt:
  ALTER INDEX table_index_name RENAME TO index_name
  {
    $$.val = &ast.RenameIndex{Index: $3.newTableIndexName(), NewName: ast.UnrestrictedName($6), IfExists: false}
  }
| ALTER INDEX IF EXISTS table_index_name RENAME TO index_name
  {
    $$.val = &ast.RenameIndex{Index: $5.newTableIndexName(), NewName: ast.UnrestrictedName($8), IfExists: true}
  }

opt_column:
  COLUMN {}
| /* EMPTY */ {}

opt_set_data:
  SET DATA {}
| /* EMPTY */ {}

// %Help: RELEASE - complete a sub-transaction
// %Category: Txn
// %Text: RELEASE [SAVEPOINT] <savepoint name>
// %SeeAlso: SAVEPOINT, WEBDOCS/savepoint.html
release_stmt:
  RELEASE savepoint_name
  {
    $$.val = &ast.ReleaseSavepoint{Savepoint: ast.Name($2)}
  }
| RELEASE error // SHOW HELP: RELEASE

// %Help: RESUME JOBS - resume background jobs
// %Category: Misc
// %Text:
// RESUME JOBS <selectclause>
// RESUME JOB <jobid>
// %SeeAlso: SHOW JOBS, CANCEL JOBS, PAUSE JOBS
resume_stmt:
  RESUME JOB a_expr
  {
    $$.val = &ast.ControlJobs{
      Jobs: &ast.Select{
        Select: &ast.ValuesClause{Rows: []ast.Exprs{ast.Exprs{$3.expr()}}},
      },
      Command: ast.ResumeJob,
    }
  }
| RESUME JOBS select_stmt
  {
    $$.val = &ast.ControlJobs{Jobs: $3.slct(), Command: ast.ResumeJob}
  }
| RESUME error // SHOW HELP: RESUME JOBS

// %Help: SAVEPOINT - start a sub-transaction
// %Category: Txn
// %Text: SAVEPOINT <savepoint name>
// %SeeAlso: RELEASE, WEBDOCS/savepoint.html
savepoint_stmt:
  SAVEPOINT name
  {
    $$.val = &ast.Savepoint{Name: ast.Name($2)}
  }
| SAVEPOINT error // SHOW HELP: SAVEPOINT

// BEGIN / START / COMMIT / END / ROLLBACK / ...
transaction_stmt:
  begin_stmt    // EXTEND WITH HELP: BEGIN
| commit_stmt   // EXTEND WITH HELP: COMMIT
| rollback_stmt // EXTEND WITH HELP: ROLLBACK
| abort_stmt    /* SKIP DOC */

// %Help: BEGIN - start a transaction
// %Category: Txn
// %Text:
// BEGIN [TRANSACTION] [ <txnparameter> [[,] ...] ]
// START TRANSACTION [ <txnparameter> [[,] ...] ]
//
// Transaction parameters:
//    ISOLATION LEVEL { SNAPSHOT | SERIALIZABLE }
//    PRIORITY { LOW | NORMAL | HIGH }
//
// %SeeAlso: COMMIT, ROLLBACK, WEBDOCS/begin-transaction.html
begin_stmt:
  BEGIN opt_transaction begin_transaction
  {
    $$.val = $3.stmt()
  }
| BEGIN error // SHOW HELP: BEGIN
| START TRANSACTION begin_transaction
  {
    $$.val = $3.stmt()
  }
| START error // SHOW HELP: BEGIN

// %Help: COMMIT - commit the current transaction
// %Category: Txn
// %Text:
// COMMIT [TRANSACTION]
// END [TRANSACTION]
// %SeeAlso: BEGIN, ROLLBACK, WEBDOCS/commit-transaction.html
commit_stmt:
  COMMIT opt_transaction
  {
    $$.val = &ast.CommitTransaction{}
  }
| COMMIT error // SHOW HELP: COMMIT
| END opt_transaction
  {
    $$.val = &ast.CommitTransaction{}
  }
| END error // SHOW HELP: COMMIT

abort_stmt:
  ABORT opt_abort_mod
  {
    $$.val = &ast.RollbackTransaction{}
  }

opt_abort_mod:
  TRANSACTION {}
| WORK        {}
| /* EMPTY */ {}

// %Help: ROLLBACK - abort the current (sub-)transaction
// %Category: Txn
// %Text:
// ROLLBACK [TRANSACTION]
// ROLLBACK [TRANSACTION] TO [SAVEPOINT] <savepoint name>
// %SeeAlso: BEGIN, COMMIT, SAVEPOINT, WEBDOCS/rollback-transaction.html
rollback_stmt:
  ROLLBACK opt_transaction
  {
     $$.val = &ast.RollbackTransaction{}
  }
| ROLLBACK opt_transaction TO savepoint_name
  {
     $$.val = &ast.RollbackToSavepoint{Savepoint: ast.Name($4)}
  }
| ROLLBACK error // SHOW HELP: ROLLBACK

opt_transaction:
  TRANSACTION {}
| /* EMPTY */ {}

savepoint_name:
  SAVEPOINT name
  {
    $$ = $2
  }
| name
  {
    $$ = $1
  }

begin_transaction:
  transaction_mode_list
  {
    $$.val = &ast.BeginTransaction{Modes: $1.transactionModes()}
  }
| /* EMPTY */
  {
    $$.val = &ast.BeginTransaction{}
  }

transaction_mode_list:
  transaction_mode
  {
    $$.val = $1.transactionModes()
  }
| transaction_mode_list opt_comma transaction_mode
  {
    a := $1.transactionModes()
    b := $3.transactionModes()
    err := a.Merge(b)
    if err != nil { return setErr(sqllex, err) }
    $$.val = a
  }

// The transaction mode list after BEGIN should use comma-separated
// modes as per the SQL standard, but PostgreSQL historically allowed
// them to be listed without commas too.
opt_comma:
  ','
  { }
| /* EMPTY */
  { }

transaction_mode:
  transaction_iso_level
  {
    /* SKIP DOC */
    $$.val = ast.TransactionModes{Isolation: $1.isoLevel()}
  }
| transaction_user_priority
  {
    $$.val = ast.TransactionModes{UserPriority: $1.userPriority()}
  }
| transaction_read_mode
  {
    $$.val = ast.TransactionModes{ReadWriteMode: $1.readWriteMode()}
  }
| as_of_clause
  {
    $$.val = ast.TransactionModes{AsOf: $1.asOfClause()}
  }

transaction_user_priority:
  PRIORITY user_priority
  {
    $$.val = $2.userPriority()
  }

transaction_iso_level:
  ISOLATION LEVEL iso_level
  {
    $$.val = $3.isoLevel()
  }

transaction_read_mode:
  READ ONLY
  {
    $$.val = ast.ReadOnly
  }
| READ WRITE
  {
    $$.val = ast.ReadWrite
  }

// %Help: CREATE DATABASE - create a new database
// %Category: DDL
// %Text: CREATE DATABASE [IF NOT EXISTS] <name>
// %SeeAlso: WEBDOCS/create-database.html
create_database_stmt:
  CREATE DATABASE database_name opt_with opt_template_clause opt_encoding_clause opt_lc_collate_clause opt_lc_ctype_clause
  {
    $$.val = &ast.CreateDatabase{
      Name: ast.Name($3),
      Template: $5,
      Encoding: $6,
      Collate: $7,
      CType: $8,
    }
  }
| CREATE DATABASE IF NOT EXISTS database_name opt_with opt_template_clause opt_encoding_clause opt_lc_collate_clause opt_lc_ctype_clause
  {
    $$.val = &ast.CreateDatabase{
      IfNotExists: true,
      Name: ast.Name($6),
      Template: $8,
      Encoding: $9,
      Collate: $10,
      CType: $11,
    }
   }
| CREATE DATABASE error // SHOW HELP: CREATE DATABASE

opt_template_clause:
  TEMPLATE opt_equal non_reserved_word_or_sconst
  {
    $$ = $3
  }
| /* EMPTY */
  {
    $$ = ""
  }

opt_encoding_clause:
  ENCODING opt_equal non_reserved_word_or_sconst
  {
    $$ = $3
  }
| /* EMPTY */
  {
    $$ = ""
  }

opt_lc_collate_clause:
  LC_COLLATE opt_equal non_reserved_word_or_sconst
  {
    $$ = $3
  }
| /* EMPTY */
  {
    $$ = ""
  }

opt_lc_ctype_clause:
  LC_CTYPE opt_equal non_reserved_word_or_sconst
  {
    $$ = $3
  }
| /* EMPTY */
  {
    $$ = ""
  }

opt_equal:
  '=' {}
| /* EMPTY */ {}

// %Help: INSERT - create new rows in a table
// %Category: DML
// %Text:
// INSERT INTO <tablename> [[AS] <name>] [( <colnames...> )]
//        <selectclause>
//        [ON CONFLICT [( <colnames...> )] {DO UPDATE SET ... [WHERE <expr>] | DO NOTHING}]
//        [RETURNING <exprs...>]
// %SeeAlso: UPSERT, UPDATE, DELETE, WEBDOCS/insert.html
insert_stmt:
  opt_with_clause INSERT INTO insert_target insert_rest returning_clause
  {
    $$.val = $5.stmt()
    $$.val.(*ast.Insert).With = $1.with()
    $$.val.(*ast.Insert).Table = $4.tblExpr()
    $$.val.(*ast.Insert).Returning = $6.retClause()
  }
| opt_with_clause INSERT INTO insert_target insert_rest on_conflict returning_clause
  {
    $$.val = $5.stmt()
    $$.val.(*ast.Insert).With = $1.with()
    $$.val.(*ast.Insert).Table = $4.tblExpr()
    $$.val.(*ast.Insert).OnConflict = $6.onConflict()
    $$.val.(*ast.Insert).Returning = $7.retClause()
  }
| opt_with_clause INSERT error // SHOW HELP: INSERT

// %Help: UPSERT - create or replace rows in a table
// %Category: DML
// %Text:
// UPSERT INTO <tablename> [AS <name>] [( <colnames...> )]
//        <selectclause>
//        [RETURNING <exprs...>]
// %SeeAlso: INSERT, UPDATE, DELETE, WEBDOCS/upsert.html
upsert_stmt:
  opt_with_clause UPSERT INTO insert_target insert_rest returning_clause
  {
    $$.val = $5.stmt()
    $$.val.(*ast.Insert).With = $1.with()
    $$.val.(*ast.Insert).Table = $4.tblExpr()
    $$.val.(*ast.Insert).OnConflict = &ast.OnConflict{}
    $$.val.(*ast.Insert).Returning = $6.retClause()
  }
| opt_with_clause UPSERT error // SHOW HELP: UPSERT

insert_target:
  table_name
  {
    name := $1.unresolvedObjectName().ToTableName()
    $$.val = &name
  }
// Can't easily make AS optional here, because VALUES in insert_rest would have
// a shift/reduce conflict with VALUES as an optional alias. We could easily
// allow unreserved_keywords as optional aliases, but that'd be an odd
// divergence from other places. So just require AS for now.
| table_name AS table_alias_name
  {
    name := $1.unresolvedObjectName().ToTableName()
    $$.val = &ast.AliasedTableExpr{Expr: &name, As: ast.AliasClause{Alias: ast.Name($3)}}
  }
| numeric_table_ref
  {
    $$.val = $1.tblExpr()
  }

insert_rest:
  select_stmt
  {
    $$.val = &ast.Insert{Rows: $1.slct()}
  }
| '(' insert_column_list ')' select_stmt
  {
    $$.val = &ast.Insert{Columns: $2.nameList(), Rows: $4.slct()}
  }
| DEFAULT VALUES
  {
    $$.val = &ast.Insert{Rows: &ast.Select{}}
  }

insert_column_list:
  insert_column_item
  {
    $$.val = ast.NameList{ast.Name($1)}
  }
| insert_column_list ',' insert_column_item
  {
    $$.val = append($1.nameList(), ast.Name($3))
  }

// insert_column_item represents the target of an INSERT/UPSERT or one
// of the LHS operands in an UPDATE SET statement.
//
//    INSERT INTO foo (x, y) VALUES ...
//                     ^^^^ here
//
//    UPDATE foo SET x = 1+2, (y, z) = (4, 5)
//                   ^^ here   ^^^^ here
//
// Currently CockroachDB only supports simple column names in this
// position. The rule below can be extended to support a sequence of
// field subscript or array indexing operators to designate a part of
// a field, when partial updates are to be supported. This likely will
// be needed together with support for composite types (#27792).
insert_column_item:
  column_name
| column_name '.' error { return unimplementedWithIssue(sqllex, 27792) }

on_conflict:
  ON CONFLICT opt_conf_expr DO UPDATE SET set_clause_list opt_where_clause
  {
    $$.val = &ast.OnConflict{Columns: $3.nameList(), Exprs: $7.updateExprs(), Where: ast.NewWhere(ast.AstWhere, $8.expr())}
  }
| ON CONFLICT opt_conf_expr DO NOTHING
  {
    $$.val = &ast.OnConflict{Columns: $3.nameList(), DoNothing: true}
  }

opt_conf_expr:
  '(' name_list ')'
  {
    $$.val = $2.nameList()
  }
| '(' name_list ')' where_clause { return unimplementedWithIssue(sqllex, 32557) }
| ON CONSTRAINT constraint_name { return unimplementedWithIssue(sqllex, 28161) }
| /* EMPTY */
  {
    $$.val = ast.NameList(nil)
  }

returning_clause:
  RETURNING target_list
  {
    ret := ast.ReturningExprs($2.selExprs())
    $$.val = &ret
  }
| RETURNING NOTHING
  {
    $$.val = ast.ReturningNothingClause
  }
| /* EMPTY */
  {
    $$.val = ast.AbsentReturningClause
  }

// %Help: UPDATE - update rows of a table
// %Category: DML
// %Text:
// UPDATE <tablename> [[AS] <name>]
//        SET ...
//        [WHERE <expr>]
//        [ORDER BY <exprs...>]
//        [LIMIT <expr>]
//        [RETURNING <exprs...>]
// %SeeAlso: INSERT, UPSERT, DELETE, WEBDOCS/update.html
update_stmt:
  opt_with_clause UPDATE table_expr_opt_alias_idx
    SET set_clause_list opt_from_list opt_where_clause opt_sort_clause opt_limit_clause returning_clause
  {
    $$.val = &ast.Update{
      With: $1.with(),
      Table: $3.tblExpr(),
      Exprs: $5.updateExprs(),
      From: $6.tblExprs(),
      Where: ast.NewWhere(ast.AstWhere, $7.expr()),
      OrderBy: $8.orderBy(),
      Limit: $9.limit(),
      Returning: $10.retClause(),
    }
  }
| opt_with_clause UPDATE error // SHOW HELP: UPDATE

opt_from_list:
  FROM from_list {
    $$.val = $2.tblExprs()
  }
| /* EMPTY */ {
    $$.val = ast.TableExprs{}
}

set_clause_list:
  set_clause
  {
    $$.val = ast.UpdateExprs{$1.updateExpr()}
  }
| set_clause_list ',' set_clause
  {
    $$.val = append($1.updateExprs(), $3.updateExpr())
  }

// TODO(knz): The LHS in these can be extended to support
// a path to a field member when compound types are supported.
// Keep it simple for now.
set_clause:
  single_set_clause
| multiple_set_clause

single_set_clause:
  column_name '=' a_expr
  {
    $$.val = &ast.UpdateExpr{Names: ast.NameList{ast.Name($1)}, Expr: $3.expr()}
  }
| column_name '.' error { return unimplementedWithIssue(sqllex, 27792) }

multiple_set_clause:
  '(' insert_column_list ')' '=' in_expr
  {
    $$.val = &ast.UpdateExpr{Tuple: true, Names: $2.nameList(), Expr: $5.expr()}
  }

// A complete SELECT statement looks like this.
//
// The rule returns either a single select_stmt node or a tree of them,
// representing a set-operation ast.
//
// There is an ambiguity when a sub-SELECT is within an a_expr and there are
// excess parentheses: do the parentheses belong to the sub-SELECT or to the
// surrounding a_expr?  We don't really care, but bison wants to know. To
// resolve the ambiguity, we are careful to define the grammar so that the
// decision is staved off as long as possible: as long as we can keep absorbing
// parentheses into the sub-SELECT, we will do so, and only when it's no longer
// possible to do that will we decide that parens belong to the expression. For
// example, in "SELECT (((SELECT 2)) + 3)" the extra parentheses are treated as
// part of the sub-select. The necessity of doing it that way is shown by
// "SELECT (((SELECT 2)) UNION SELECT 2)". Had we parsed "((SELECT 2))" as an
// a_expr, it'd be too late to go back to the SELECT viewpoint when we see the
// UNION.
//
// This approach is implemented by defining a nonterminal select_with_parens,
// which represents a SELECT with at least one outer layer of parentheses, and
// being careful to use select_with_parens, never '(' select_stmt ')', in the
// expression grammar. We will then have shift-reduce conflicts which we can
// resolve in favor of always treating '(' <select> ')' as a
// select_with_parens. To resolve the conflicts, the productions that conflict
// with the select_with_parens productions are manually given precedences lower
// than the precedence of ')', thereby ensuring that we shift ')' (and then
// reduce to select_with_parens) rather than trying to reduce the inner
// <select> nonterminal to something else. We use UMINUS precedence for this,
// which is a fairly arbitrary choice.
//
// To be able to define select_with_parens itself without ambiguity, we need a
// nonterminal select_no_parens that represents a SELECT structure with no
// outermost parentheses. This is a little bit tedious, but it works.
//
// In non-expression contexts, we use select_stmt which can represent a SELECT
// with or without outer parentheses.
select_stmt:
  select_no_parens %prec UMINUS
| select_with_parens %prec UMINUS
  {
    $$.val = &ast.Select{Select: $1.selectStmt()}
  }

select_with_parens:
  '(' select_no_parens ')'
  {
    $$.val = &ast.ParenSelect{Select: $2.slct()}
  }
| '(' select_with_parens ')'
  {
    $$.val = &ast.ParenSelect{Select: &ast.Select{Select: $2.selectStmt()}}
  }

// This rule parses the equivalent of the standard's <query expression>. The
// duplicative productions are annoying, but hard to get rid of without
// creating shift/reduce conflicts.
//
//      The locking clause (FOR UPDATE etc) may be before or after
//      LIMIT/OFFSET. In <=7.2.X, LIMIT/OFFSET had to be after FOR UPDATE We
//      now support both orderings, but prefer LIMIT/OFFSET before the locking
//      clause.
//      - 2002-08-28 bjm
select_no_parens:
  simple_select
  {
    $$.val = &ast.Select{Select: $1.selectStmt()}
  }
| select_clause sort_clause
  {
    $$.val = &ast.Select{Select: $1.selectStmt(), OrderBy: $2.orderBy()}
  }
| select_clause opt_sort_clause for_locking_clause opt_select_limit
  {
    $$.val = &ast.Select{Select: $1.selectStmt(), OrderBy: $2.orderBy(), Limit: $4.limit(), Locking: $3.lockingClause()}
  }
| select_clause opt_sort_clause select_limit opt_for_locking_clause
  {
    $$.val = &ast.Select{Select: $1.selectStmt(), OrderBy: $2.orderBy(), Limit: $3.limit(), Locking: $4.lockingClause()}
  }
| with_clause select_clause
  {
    $$.val = &ast.Select{With: $1.with(), Select: $2.selectStmt()}
  }
| with_clause select_clause sort_clause
  {
    $$.val = &ast.Select{With: $1.with(), Select: $2.selectStmt(), OrderBy: $3.orderBy()}
  }
| with_clause select_clause opt_sort_clause for_locking_clause opt_select_limit
  {
    $$.val = &ast.Select{With: $1.with(), Select: $2.selectStmt(), OrderBy: $3.orderBy(), Limit: $5.limit(), Locking: $4.lockingClause()}
  }
| with_clause select_clause opt_sort_clause select_limit opt_for_locking_clause
  {
    $$.val = &ast.Select{With: $1.with(), Select: $2.selectStmt(), OrderBy: $3.orderBy(), Limit: $4.limit(), Locking: $5.lockingClause()}
  }

for_locking_clause:
  for_locking_items { $$.val = $1.lockingClause() }
| FOR READ ONLY     { $$.val = (ast.LockingClause)(nil) }

opt_for_locking_clause:
  for_locking_clause { $$.val = $1.lockingClause() }
| /* EMPTY */        { $$.val = (ast.LockingClause)(nil) }

for_locking_items:
  for_locking_item
  {
    $$.val = ast.LockingClause{$1.lockingItem()}
  }
| for_locking_items for_locking_item
  {
    $$.val = append($1.lockingClause(), $2.lockingItem())
  }

for_locking_item:
  for_locking_strength opt_locked_rels opt_nowait_or_skip
  {
    $$.val = &ast.LockingItem{
      Strength:   $1.lockingStrength(),
      Targets:    $2.tableNames(),
      WaitPolicy: $3.lockingWaitPolicy(),
    }
  }

for_locking_strength:
  FOR UPDATE        { $$.val = ast.ForUpdate }
| FOR NO KEY UPDATE { $$.val = ast.ForNoKeyUpdate }
| FOR SHARE         { $$.val = ast.ForShare }
| FOR KEY SHARE     { $$.val = ast.ForKeyShare }

opt_locked_rels:
  /* EMPTY */        { $$.val = ast.TableNames{} }
| OF table_name_list { $$.val = $2.tableNames() }

opt_nowait_or_skip:
  /* EMPTY */ { $$.val = ast.LockWaitBlock }
| SKIP LOCKED { $$.val = ast.LockWaitSkip }
| NOWAIT      { $$.val = ast.LockWaitError }

select_clause:
// We only provide help if an open parenthesis is provided, because
// otherwise the rule is ambiguous with the top-level statement list.
  '(' error // SHOW HELP: <SELECTCLAUSE>
| simple_select
| select_with_parens

// This rule parses SELECT statements that can appear within set operations,
// including UNION, INTERSECT and EXCEPT. '(' and ')' can be used to specify
// the ordering of the set operations. Without '(' and ')' we want the
// operations to be ordered per the precedence specs at the head of this file.
//
// As with select_no_parens, simple_select cannot have outer parentheses, but
// can have parenthesized subclauses.
//
// Note that sort clauses cannot be included at this level --- SQL requires
//       SELECT foo UNION SELECT bar ORDER BY baz
// to be parsed as
//       (SELECT foo UNION SELECT bar) ORDER BY baz
// not
//       SELECT foo UNION (SELECT bar ORDER BY baz)
//
// Likewise for WITH, FOR UPDATE and LIMIT. Therefore, those clauses are
// described as part of the select_no_parens production, not simple_select.
// This does not limit functionality, because you can reintroduce these clauses
// inside parentheses.
//
// NOTE: only the leftmost component select_stmt should have INTO. However,
// this is not checked by the grammar; parse analysis must check it.
//
// %Help: <SELECTCLAUSE> - access tabular data
// %Category: DML
// %Text:
// Select clause:
//   TABLE <tablename>
//   VALUES ( <exprs...> ) [ , ... ]
//   SELECT ... [ { INTERSECT | UNION | EXCEPT } [ ALL | DISTINCT ] <selectclause> ]
simple_select:
  simple_select_clause // EXTEND WITH HELP: SELECT
| values_clause        // EXTEND WITH HELP: VALUES
| table_clause         // EXTEND WITH HELP: TABLE
| set_operation

// %Help: SELECT - retrieve rows from a data source and compute a result
// %Category: DML
// %Text:
// SELECT [DISTINCT [ ON ( <expr> [ , ... ] ) ] ]
//        { <expr> [[AS] <name>] | [ [<dbname>.] <tablename>. ] * } [, ...]
//        [ FROM <source> ]
//        [ WHERE <expr> ]
//        [ GROUP BY <expr> [ , ... ] ]
//        [ HAVING <expr> ]
//        [ WINDOW <name> AS ( <definition> ) ]
//        [ { UNION | INTERSECT | EXCEPT } [ ALL | DISTINCT ] <selectclause> ]
//        [ ORDER BY <expr> [ ASC | DESC ] [, ...] ]
//        [ LIMIT { <expr> | ALL } ]
//        [ OFFSET <expr> [ ROW | ROWS ] ]
// %SeeAlso: WEBDOCS/select-clause.html
simple_select_clause:
  SELECT opt_all_clause target_list
    from_clause opt_where_clause
    group_clause having_clause window_clause
  {
    $$.val = &ast.SelectClause{
      Exprs:   $3.selExprs(),
      From:    $4.from(),
      Where:   ast.NewWhere(ast.AstWhere, $5.expr()),
      GroupBy: $6.groupBy(),
      Having:  ast.NewWhere(ast.AstHaving, $7.expr()),
      Window:  $8.window(),
    }
  }
| SELECT distinct_clause target_list
    from_clause opt_where_clause
    group_clause having_clause window_clause
  {
    $$.val = &ast.SelectClause{
      Distinct: $2.bool(),
      Exprs:    $3.selExprs(),
      From:     $4.from(),
      Where:    ast.NewWhere(ast.AstWhere, $5.expr()),
      GroupBy:  $6.groupBy(),
      Having:   ast.NewWhere(ast.AstHaving, $7.expr()),
      Window:   $8.window(),
    }
  }
| SELECT distinct_on_clause target_list
    from_clause opt_where_clause
    group_clause having_clause window_clause
  {
    $$.val = &ast.SelectClause{
      Distinct:   true,
      DistinctOn: $2.distinctOn(),
      Exprs:      $3.selExprs(),
      From:       $4.from(),
      Where:      ast.NewWhere(ast.AstWhere, $5.expr()),
      GroupBy:    $6.groupBy(),
      Having:     ast.NewWhere(ast.AstHaving, $7.expr()),
      Window:     $8.window(),
    }
  }
| SELECT error // SHOW HELP: SELECT

set_operation:
  select_clause UNION all_or_distinct select_clause
  {
    $$.val = &ast.UnionClause{
      Type:  ast.UnionOp,
      Left:  &ast.Select{Select: $1.selectStmt()},
      Right: &ast.Select{Select: $4.selectStmt()},
      All:   $3.bool(),
    }
  }
| select_clause INTERSECT all_or_distinct select_clause
  {
    $$.val = &ast.UnionClause{
      Type:  ast.IntersectOp,
      Left:  &ast.Select{Select: $1.selectStmt()},
      Right: &ast.Select{Select: $4.selectStmt()},
      All:   $3.bool(),
    }
  }
| select_clause EXCEPT all_or_distinct select_clause
  {
    $$.val = &ast.UnionClause{
      Type:  ast.ExceptOp,
      Left:  &ast.Select{Select: $1.selectStmt()},
      Right: &ast.Select{Select: $4.selectStmt()},
      All:   $3.bool(),
    }
  }

// %Help: TABLE - select an entire table
// %Category: DML
// %Text: TABLE <tablename>
// %SeeAlso: SELECT, VALUES, WEBDOCS/table-expressions.html
table_clause:
  TABLE table_ref
  {
    $$.val = &ast.SelectClause{
      Exprs:       ast.SelectExprs{ast.StarSelectExpr()},
      From:        ast.From{Tables: ast.TableExprs{$2.tblExpr()}},
      TableSelect: true,
    }
  }
| TABLE error // SHOW HELP: TABLE

// SQL standard WITH clause looks like:
//
// WITH [ RECURSIVE ] <query name> [ (<column> [, ...]) ]
//        AS [ [ NOT ] MATERIALIZED ] (query) [ SEARCH or CYCLE clause ]
//
// We don't currently support the SEARCH or CYCLE clause.
//
// Recognizing WITH_LA here allows a CTE to be named TIME or ORDINALITY.
with_clause:
  WITH cte_list
  {
    $$.val = &ast.With{CTEList: $2.ctes()}
  }
| WITH_LA cte_list
  {
    /* SKIP DOC */
    $$.val = &ast.With{CTEList: $2.ctes()}
  }
| WITH RECURSIVE cte_list
  {
    $$.val = &ast.With{Recursive: true, CTEList: $3.ctes()}
  }

cte_list:
  common_table_expr
  {
    $$.val = []*ast.CTE{$1.cte()}
  }
| cte_list ',' common_table_expr
  {
    $$.val = append($1.ctes(), $3.cte())
  }

materialize_clause:
  MATERIALIZED
  {
    $$.val = true
  }
| NOT MATERIALIZED
  {
    $$.val = false
  }

common_table_expr:
  table_alias_name opt_column_list AS '(' preparable_stmt ')'
    {
      $$.val = &ast.CTE{
        Name: ast.AliasClause{Alias: ast.Name($1), Cols: $2.nameList() },
        Mtr: ast.MaterializeClause{
          Set: false,
        },
        Stmt: $5.stmt(),
      }
    }
| table_alias_name opt_column_list AS materialize_clause '(' preparable_stmt ')'
    {
      $$.val = &ast.CTE{
        Name: ast.AliasClause{Alias: ast.Name($1), Cols: $2.nameList() },
        Mtr: ast.MaterializeClause{
          Materialize: $4.bool(),
          Set: true,
        },
        Stmt: $6.stmt(),
      }
    }

opt_with:
  WITH {}
| /* EMPTY */ {}

opt_with_clause:
  with_clause
  {
    $$.val = $1.with()
  }
| /* EMPTY */
  {
    $$.val = nil
  }

opt_table:
  TABLE {}
| /* EMPTY */ {}

all_or_distinct:
  ALL
  {
    $$.val = true
  }
| DISTINCT
  {
    $$.val = false
  }
| /* EMPTY */
  {
    $$.val = false
  }

distinct_clause:
  DISTINCT
  {
    $$.val = true
  }

distinct_on_clause:
  DISTINCT ON '(' expr_list ')'
  {
    $$.val = ast.DistinctOn($4.exprs())
  }

opt_all_clause:
  ALL {}
| /* EMPTY */ {}

opt_sort_clause:
  sort_clause
  {
    $$.val = $1.orderBy()
  }
| /* EMPTY */
  {
    $$.val = ast.OrderBy(nil)
  }

sort_clause:
  ORDER BY sortby_list
  {
    $$.val = ast.OrderBy($3.orders())
  }

single_sort_clause:
  ORDER BY sortby
  {
    $$.val = ast.OrderBy([]*ast.Order{$3.order()})
  }
| ORDER BY sortby ',' sortby_list
  {
    sqllex.Error("multiple ORDER BY clauses are not supported in this function")
    return 1
  }

sortby_list:
  sortby
  {
    $$.val = []*ast.Order{$1.order()}
  }
| sortby_list ',' sortby
  {
    $$.val = append($1.orders(), $3.order())
  }

sortby:
  a_expr opt_asc_desc opt_nulls_order
  {
    /* FORCE DOC */
    dir := $2.dir()
    nullsOrder := $3.nullsOrder()
    // We currently only support the opposite of Postgres defaults.
    if nullsOrder != ast.DefaultNullsOrder {
      if dir == ast.Descending && nullsOrder == ast.NullsFirst {
        return unimplementedWithIssue(sqllex, 6224)
      }
      if dir != ast.Descending && nullsOrder == ast.NullsLast {
        return unimplementedWithIssue(sqllex, 6224)
      }
    }
    $$.val = &ast.Order{
      OrderType:  ast.OrderByColumn,
      Expr:       $1.expr(),
      Direction:  dir,
      NullsOrder: nullsOrder,
    }
  }
| PRIMARY KEY table_name opt_asc_desc
  {
    name := $3.unresolvedObjectName().ToTableName()
    $$.val = &ast.Order{OrderType: ast.OrderByIndex, Direction: $4.dir(), Table: name}
  }
| INDEX table_name '@' index_name opt_asc_desc
  {
    name := $2.unresolvedObjectName().ToTableName()
    $$.val = &ast.Order{
      OrderType: ast.OrderByIndex,
      Direction: $5.dir(),
      Table:     name,
      Index:     ast.UnrestrictedName($4),
    }
  }

opt_nulls_order:
  NULLS FIRST
  {
    $$.val = ast.NullsFirst
  }
| NULLS LAST
  {
    $$.val = ast.NullsLast
  }
| /* EMPTY */
  {
    $$.val = ast.DefaultNullsOrder
  }

// TODO(pmattis): Support ordering using arbitrary math ops?
// | a_expr USING math_op {}

select_limit:
  limit_clause offset_clause
  {
    if $1.limit() == nil {
      $$.val = $2.limit()
    } else {
      $$.val = $1.limit()
      $$.val.(*ast.Limit).Offset = $2.limit().Offset
    }
  }
| offset_clause limit_clause
  {
    $$.val = $1.limit()
    if $2.limit() != nil {
      $$.val.(*ast.Limit).Count = $2.limit().Count
      $$.val.(*ast.Limit).LimitAll = $2.limit().LimitAll
    }
  }
| limit_clause
| offset_clause

opt_select_limit:
  select_limit { $$.val = $1.limit() }
| /* EMPTY */  { $$.val = (*ast.Limit)(nil) }

opt_limit_clause:
  limit_clause
| /* EMPTY */ { $$.val = (*ast.Limit)(nil) }

limit_clause:
  LIMIT ALL
  {
    $$.val = &ast.Limit{LimitAll: true}
  }
| LIMIT a_expr
  {
    if $2.expr() == nil {
      $$.val = (*ast.Limit)(nil)
    } else {
      $$.val = &ast.Limit{Count: $2.expr()}
    }
  }
// SQL:2008 syntax
// To avoid shift/reduce conflicts, handle the optional value with
// a separate production rather than an opt_ expression. The fact
// that ONLY is fully reserved means that this way, we defer any
// decision about what rule reduces ROW or ROWS to the point where
// we can see the ONLY token in the lookahead slot.
| FETCH first_or_next select_fetch_first_value row_or_rows ONLY
  {
    $$.val = &ast.Limit{Count: $3.expr()}
  }
| FETCH first_or_next row_or_rows ONLY
	{
    $$.val = &ast.Limit{
      Count: ast.NewNumVal(constant.MakeInt64(1), "" /* origString */, false /* negative */),
    }
  }

offset_clause:
  OFFSET a_expr
  {
    $$.val = &ast.Limit{Offset: $2.expr()}
  }
  // SQL:2008 syntax
  // The trailing ROW/ROWS in this case prevent the full expression
  // syntax. c_expr is the best we can do.
| OFFSET select_fetch_first_value row_or_rows
  {
    $$.val = &ast.Limit{Offset: $2.expr()}
  }

// Allowing full expressions without parentheses causes various parsing
// problems with the trailing ROW/ROWS key words. SQL spec only calls for
// <simple value specification>, which is either a literal or a parameter (but
// an <SQL parameter reference> could be an identifier, bringing up conflicts
// with ROW/ROWS). We solve this by leveraging the presence of ONLY (see above)
// to determine whether the expression is missing rather than trying to make it
// optional in this rule.
//
// c_expr covers almost all the spec-required cases (and more), but it doesn't
// cover signed numeric literals, which are allowed by the spec. So we include
// those here explicitly.
select_fetch_first_value:
  c_expr
| only_signed_iconst
| only_signed_fconst

// noise words
row_or_rows:
  ROW {}
| ROWS {}

first_or_next:
  FIRST {}
| NEXT {}

// This syntax for group_clause tries to follow the spec quite closely.
// However, the spec allows only column references, not expressions,
// which introduces an ambiguity between implicit row constructors
// (a,b) and lists of column references.
//
// We handle this by using the a_expr production for what the spec calls
// <ordinary grouping set>, which in the spec represents either one column
// reference or a parenthesized list of column references. Then, we check the
// top node of the a_expr to see if it's an RowExpr, and if so, just grab and
// use the list, discarding the node. (this is done in parse analysis, not here)
//
// Each item in the group_clause list is either an expression tree or a
// GroupingSet node of some type.
group_clause:
  GROUP BY expr_list
  {
    $$.val = ast.GroupBy($3.exprs())
  }
| /* EMPTY */
  {
    $$.val = ast.GroupBy(nil)
  }

having_clause:
  HAVING a_expr
  {
    $$.val = $2.expr()
  }
| /* EMPTY */
  {
    $$.val = ast.Expr(nil)
  }

// Given "VALUES (a, b)" in a table expression context, we have to
// decide without looking any further ahead whether VALUES is the
// values clause or a set-generating function. Since VALUES is allowed
// as a function name both interpretations are feasible. We resolve
// the shift/reduce conflict by giving the first values_clause
// production a higher precedence than the VALUES token has, causing
// the parser to prefer to reduce, in effect assuming that the VALUES
// is not a function name.
//
// %Help: VALUES - select a given set of values
// %Category: DML
// %Text: VALUES ( <exprs...> ) [, ...]
// %SeeAlso: SELECT, TABLE, WEBDOCS/table-expressions.html
values_clause:
  VALUES '(' expr_list ')' %prec UMINUS
  {
    $$.val = &ast.ValuesClause{Rows: []ast.Exprs{$3.exprs()}}
  }
| VALUES error // SHOW HELP: VALUES
| values_clause ',' '(' expr_list ')'
  {
    valNode := $1.selectStmt().(*ast.ValuesClause)
    valNode.Rows = append(valNode.Rows, $4.exprs())
    $$.val = valNode
  }

// clauses common to all optimizable statements:
//  from_clause   - allow list of both JOIN expressions and table names
//  where_clause  - qualifications for joins or restrictions

from_clause:
  FROM from_list opt_as_of_clause
  {
    $$.val = ast.From{Tables: $2.tblExprs(), AsOf: $3.asOfClause()}
  }
| FROM error // SHOW HELP: <SOURCE>
| /* EMPTY */
  {
    $$.val = ast.From{}
  }

from_list:
  table_ref
  {
    $$.val = ast.TableExprs{$1.tblExpr()}
  }
| from_list ',' table_ref
  {
    $$.val = append($1.tblExprs(), $3.tblExpr())
  }

index_flags_param:
  FORCE_INDEX '=' index_name
  {
     $$.val = &ast.IndexFlags{Index: ast.UnrestrictedName($3)}
  }
| FORCE_INDEX '=' '[' iconst64 ']'
  {
    /* SKIP DOC */
    $$.val = &ast.IndexFlags{IndexID: ast.IndexID($4.int64())}
  }
| ASC
  {
    /* SKIP DOC */
    $$.val = &ast.IndexFlags{Direction: ast.Ascending}
  }
| DESC
  {
    /* SKIP DOC */
    $$.val = &ast.IndexFlags{Direction: ast.Descending}
  }
|
  NO_INDEX_JOIN
  {
    $$.val = &ast.IndexFlags{NoIndexJoin: true}
  }
|
  IGNORE_FOREIGN_KEYS
  {
    /* SKIP DOC */
    $$.val = &ast.IndexFlags{IgnoreForeignKeys: true}
  }

index_flags_param_list:
  index_flags_param
  {
    $$.val = $1.indexFlags()
  }
|
  index_flags_param_list ',' index_flags_param
  {
    a := $1.indexFlags()
    b := $3.indexFlags()
    if err := a.CombineWith(b); err != nil {
      return setErr(sqllex, err)
    }
    $$.val = a
  }

opt_index_flags:
  '@' index_name
  {
    $$.val = &ast.IndexFlags{Index: ast.UnrestrictedName($2)}
  }
| '@' '[' iconst64 ']'
  {
    $$.val = &ast.IndexFlags{IndexID: ast.IndexID($3.int64())}
  }
| '@' '{' index_flags_param_list '}'
  {
    flags := $3.indexFlags()
    if err := flags.Check(); err != nil {
      return setErr(sqllex, err)
    }
    $$.val = flags
  }
| /* EMPTY */
  {
    $$.val = (*ast.IndexFlags)(nil)
  }

// %Help: <SOURCE> - define a data source for SELECT
// %Category: DML
// %Text:
// Data sources:
//   <tablename> [ @ { <idxname> | <indexflags> } ]
//   <tablefunc> ( <exprs...> )
//   ( { <selectclause> | <source> } )
//   <source> [AS] <alias> [( <colnames...> )]
//   <source> [ <jointype> ] JOIN <source> ON <expr>
//   <source> [ <jointype> ] JOIN <source> USING ( <colnames...> )
//   <source> NATURAL [ <jointype> ] JOIN <source>
//   <source> CROSS JOIN <source>
//   <source> WITH ORDINALITY
//   '[' EXPLAIN ... ']'
//   '[' SHOW ... ']'
//
// Index flags:
//   '{' FORCE_INDEX = <idxname> [, ...] '}'
//   '{' NO_INDEX_JOIN [, ...] '}'
//   '{' IGNORE_FOREIGN_KEYS [, ...] '}'
//
// Join types:
//   { INNER | { LEFT | RIGHT | FULL } [OUTER] } [ { HASH | MERGE | LOOKUP } ]
//
// %SeeAlso: WEBDOCS/table-expressions.html
table_ref:
  numeric_table_ref opt_index_flags opt_ordinality opt_alias_clause
  {
    /* SKIP DOC */
    $$.val = &ast.AliasedTableExpr{
        Expr:       $1.tblExpr(),
        IndexFlags: $2.indexFlags(),
        Ordinality: $3.bool(),
        As:         $4.aliasClause(),
    }
  }
| relation_expr opt_index_flags opt_ordinality opt_alias_clause
  {
    name := $1.unresolvedObjectName().ToTableName()
    $$.val = &ast.AliasedTableExpr{
      Expr:       &name,
      IndexFlags: $2.indexFlags(),
      Ordinality: $3.bool(),
      As:         $4.aliasClause(),
    }
  }
| select_with_parens opt_ordinality opt_alias_clause
  {
    $$.val = &ast.AliasedTableExpr{
      Expr:       &ast.Subquery{Select: $1.selectStmt()},
      Ordinality: $2.bool(),
      As:         $3.aliasClause(),
    }
  }
| LATERAL select_with_parens opt_ordinality opt_alias_clause
  {
    $$.val = &ast.AliasedTableExpr{
      Expr:       &ast.Subquery{Select: $2.selectStmt()},
      Ordinality: $3.bool(),
      Lateral:    true,
      As:         $4.aliasClause(),
    }
  }
| joined_table
  {
    $$.val = $1.tblExpr()
  }
| '(' joined_table ')' opt_ordinality alias_clause
  {
    $$.val = &ast.AliasedTableExpr{Expr: &ast.ParenTableExpr{Expr: $2.tblExpr()}, Ordinality: $4.bool(), As: $5.aliasClause()}
  }
| func_table opt_ordinality opt_alias_clause
  {
    f := $1.tblExpr()
    $$.val = &ast.AliasedTableExpr{
      Expr: f,
      Ordinality: $2.bool(),
      // Technically, LATERAL is always implied on an SRF, but including it
      // here makes re-printing the AST slightly tricky.
      As: $3.aliasClause(),
    }
  }
| LATERAL func_table opt_ordinality opt_alias_clause
  {
    f := $2.tblExpr()
    $$.val = &ast.AliasedTableExpr{
      Expr: f,
      Ordinality: $3.bool(),
      Lateral: true,
      As: $4.aliasClause(),
    }
  }
// The following syntax is a CockroachDB extension:
//     SELECT ... FROM [ EXPLAIN .... ] WHERE ...
//     SELECT ... FROM [ SHOW .... ] WHERE ...
//     SELECT ... FROM [ INSERT ... RETURNING ... ] WHERE ...
// A statement within square brackets can be used as a table expression (data source).
// We use square brackets for two reasons:
// - the grammar would be terribly ambiguous if we used simple
//   parentheses or no parentheses at all.
// - it carries visual semantic information, by marking the table
//   expression as radically different from the other things.
//   If a user does not know this and encounters this syntax, they
//   will know from the unusual choice that something rather different
//   is going on and may be pushed by the unusual syntax to
//   investigate further in the docs.
| '[' row_source_extension_stmt ']' opt_ordinality opt_alias_clause
  {
    $$.val = &ast.AliasedTableExpr{Expr: &ast.StatementSource{ Statement: $2.stmt() }, Ordinality: $4.bool(), As: $5.aliasClause() }
  }

numeric_table_ref:
  '[' iconst64 opt_tableref_col_list alias_clause ']'
  {
    /* SKIP DOC */
    $$.val = &ast.TableRef{
      TableID: $2.int64(),
      Columns: $3.tableRefCols(),
      As:      $4.aliasClause(),
    }
  }

func_table:
  func_expr_windowless
  {
    $$.val = &ast.RowsFromExpr{Items: ast.Exprs{$1.expr()}}
  }
| ROWS FROM '(' rowsfrom_list ')'
  {
    $$.val = &ast.RowsFromExpr{Items: $4.exprs()}
  }

rowsfrom_list:
  rowsfrom_item
  { $$.val = ast.Exprs{$1.expr()} }
| rowsfrom_list ',' rowsfrom_item
  { $$.val = append($1.exprs(), $3.expr()) }

rowsfrom_item:
  func_expr_windowless opt_col_def_list
  {
    $$.val = $1.expr()
  }

opt_col_def_list:
  /* EMPTY */
  { }
| AS '(' error
  { return unimplemented(sqllex, "ROWS FROM with col_def_list") }

opt_tableref_col_list:
  /* EMPTY */               { $$.val = nil }
| '(' ')'                   { $$.val = []ast.ColumnID{} }
| '(' tableref_col_list ')' { $$.val = $2.tableRefCols() }

tableref_col_list:
  iconst64
  {
    $$.val = []ast.ColumnID{ast.ColumnID($1.int64())}
  }
| tableref_col_list ',' iconst64
  {
    $$.val = append($1.tableRefCols(), ast.ColumnID($3.int64()))
  }

opt_ordinality:
  WITH_LA ORDINALITY
  {
    $$.val = true
  }
| /* EMPTY */
  {
    $$.val = false
  }

// It may seem silly to separate joined_table from table_ref, but there is
// method in SQL's madness: if you don't do it this way you get reduce- reduce
// conflicts, because it's not clear to the parser generator whether to expect
// alias_clause after ')' or not. For the same reason we must treat 'JOIN' and
// 'join_type JOIN' separately, rather than allowing join_type to expand to
// empty; if we try it, the parser generator can't figure out when to reduce an
// empty join_type right after table_ref.
//
// Note that a CROSS JOIN is the same as an unqualified INNER JOIN, and an
// INNER JOIN/ON has the same shape but a qualification expression to limit
// membership. A NATURAL JOIN implicitly matches column names between tables
// and the shape is determined by which columns are in common. We'll collect
// columns during the later transformations.

joined_table:
  '(' joined_table ')'
  {
    $$.val = &ast.ParenTableExpr{Expr: $2.tblExpr()}
  }
| table_ref CROSS opt_join_hint JOIN table_ref
  {
    $$.val = &ast.JoinTableExpr{JoinType: ast.AstCross, Left: $1.tblExpr(), Right: $5.tblExpr(), Hint: $3}
  }
| table_ref join_type opt_join_hint JOIN table_ref join_qual
  {
    $$.val = &ast.JoinTableExpr{JoinType: $2, Left: $1.tblExpr(), Right: $5.tblExpr(), Cond: $6.joinCond(), Hint: $3}
  }
| table_ref JOIN table_ref join_qual
  {
    $$.val = &ast.JoinTableExpr{Left: $1.tblExpr(), Right: $3.tblExpr(), Cond: $4.joinCond()}
  }
| table_ref NATURAL join_type opt_join_hint JOIN table_ref
  {
    $$.val = &ast.JoinTableExpr{JoinType: $3, Left: $1.tblExpr(), Right: $6.tblExpr(), Cond: ast.NaturalJoinCond{}, Hint: $4}
  }
| table_ref NATURAL JOIN table_ref
  {
    $$.val = &ast.JoinTableExpr{Left: $1.tblExpr(), Right: $4.tblExpr(), Cond: ast.NaturalJoinCond{}}
  }

alias_clause:
  AS table_alias_name opt_column_list
  {
    $$.val = ast.AliasClause{Alias: ast.Name($2), Cols: $3.nameList()}
  }
| table_alias_name opt_column_list
  {
    $$.val = ast.AliasClause{Alias: ast.Name($1), Cols: $2.nameList()}
  }

opt_alias_clause:
  alias_clause
| /* EMPTY */
  {
    $$.val = ast.AliasClause{}
  }

as_of_clause:
  AS_LA OF SYSTEM TIME a_expr
  {
    $$.val = ast.AsOfClause{Expr: $5.expr()}
  }

opt_as_of_clause:
  as_of_clause
| /* EMPTY */
  {
    $$.val = ast.AsOfClause{}
  }

join_type:
  FULL join_outer
  {
    $$ = ast.AstFull
  }
| LEFT join_outer
  {
    $$ = ast.AstLeft
  }
| RIGHT join_outer
  {
    $$ = ast.AstRight
  }
| INNER
  {
    $$ = ast.AstInner
  }

// OUTER is just noise...
join_outer:
  OUTER {}
| /* EMPTY */ {}

// Join hint specifies that the join in the query should use a
// specific method.

// The semantics are as follows:
//  - HASH forces a hash join; in other words, it disables merge and lookup
//    join. A hash join is always possible; even if there are no equality
//    columns - we consider cartesian join a degenerate case of the hash join
//    (one bucket).
//  - MERGE forces a merge join, even if it requires resorting both sides of
//    the join.
//  - LOOKUP forces a lookup join into the right side; the right side must be
//    a table with a suitable index. `LOOKUP` can only be used with INNER and
//    LEFT joins (though this is not enforced by the syntax).
//  - If it is not possible to use the algorithm in the hint, an error is
//    returned.
//  - When a join hint is specified, the two tables will not be reordered
//    by the optimizer.
opt_join_hint:
  HASH
  {
    $$ = ast.AstHash
  }
| MERGE
  {
    $$ = ast.AstMerge
  }
| LOOKUP
  {
    $$ = ast.AstLookup
  }
| /* EMPTY */
  {
    $$ = ""
  }

// JOIN qualification clauses
// Possibilities are:
//      USING ( column list ) allows only unqualified column names,
//          which must match between tables.
//      ON expr allows more general qualifications.
//
// We return USING as a List node, while an ON-expr will not be a List.
join_qual:
  USING '(' name_list ')'
  {
    $$.val = &ast.UsingJoinCond{Cols: $3.nameList()}
  }
| ON a_expr
  {
    $$.val = &ast.OnJoinCond{Expr: $2.expr()}
  }

relation_expr:
  table_name              { $$.val = $1.unresolvedObjectName() }
| table_name '*'          { $$.val = $1.unresolvedObjectName() }
| ONLY table_name         { $$.val = $2.unresolvedObjectName() }
| ONLY '(' table_name ')' { $$.val = $3.unresolvedObjectName() }

relation_expr_list:
  relation_expr
  {
    name := $1.unresolvedObjectName().ToTableName()
    $$.val = ast.TableNames{name}
  }
| relation_expr_list ',' relation_expr
  {
    name := $3.unresolvedObjectName().ToTableName()
    $$.val = append($1.tableNames(), name)
  }

// Given "UPDATE foo set set ...", we have to decide without looking any
// further ahead whether the first "set" is an alias or the UPDATE's SET
// keyword. Since "set" is allowed as a column name both interpretations are
// feasible. We resolve the shift/reduce conflict by giving the first
// table_expr_opt_alias_idx production a higher precedence than the SET token
// has, causing the parser to prefer to reduce, in effect assuming that the SET
// is not an alias.
table_expr_opt_alias_idx:
  table_name_opt_idx %prec UMINUS
  {
     $$.val = $1.tblExpr()
  }
| table_name_opt_idx table_alias_name
  {
     alias := $1.tblExpr().(*ast.AliasedTableExpr)
     alias.As = ast.AliasClause{Alias: ast.Name($2)}
     $$.val = alias
  }
| table_name_opt_idx AS table_alias_name
  {
     alias := $1.tblExpr().(*ast.AliasedTableExpr)
     alias.As = ast.AliasClause{Alias: ast.Name($3)}
     $$.val = alias
  }
| numeric_table_ref opt_index_flags
  {
    /* SKIP DOC */
    $$.val = &ast.AliasedTableExpr{
      Expr: $1.tblExpr(),
      IndexFlags: $2.indexFlags(),
    }
  }

table_name_opt_idx:
  table_name opt_index_flags
  {
    name := $1.unresolvedObjectName().ToTableName()
    $$.val = &ast.AliasedTableExpr{
      Expr: &name,
      IndexFlags: $2.indexFlags(),
    }
  }

where_clause:
  WHERE a_expr
  {
    $$.val = $2.expr()
  }

opt_where_clause:
  where_clause
| /* EMPTY */
  {
    $$.val = ast.Expr(nil)
  }

// Type syntax
//   SQL introduces a large amount of type-specific syntax.
//   Define individual clauses to handle these cases, and use
//   the generic case to handle regular type-extensible Postgres syntax.
//   - thomas 1997-10-10

typename:
  simple_typename opt_array_bounds
  {
    if bounds := $2.int32s(); bounds != nil {
      var err error
      $$.val, err = arrayOf($1.typeReference(), bounds)
      if err != nil {
        return setErr(sqllex, err)
      }
    } else {
      $$.val = $1.typeReference()
    }
  }
  // SQL standard syntax, currently only one-dimensional
  // Undocumented but support for potential Postgres compat
| simple_typename ARRAY '[' ICONST ']' {
    /* SKIP DOC */
    var err error
    $$.val, err = arrayOf($1.typeReference(), nil)
    if err != nil {
      return setErr(sqllex, err)
    }
  }
| simple_typename ARRAY '[' ICONST ']' '[' error { return unimplementedWithIssue(sqllex, 32552) }
| simple_typename ARRAY {
    var err error
    $$.val, err = arrayOf($1.typeReference(), nil)
    if err != nil {
      return setErr(sqllex, err)
    }
  }

cast_target:
  typename
  {
    $$.val = $1.typeReference()
  }

opt_array_bounds:
  // TODO(justin): reintroduce multiple array bounds
  // opt_array_bounds '[' ']' { $$.val = append($1.int32s(), -1) }
  '[' ']' { $$.val = []int32{-1} }
| '[' ']' '[' error { return unimplementedWithIssue(sqllex, 32552) }
| '[' ICONST ']'
  {
    /* SKIP DOC */
    bound, err := $2.numVal().AsInt32()
    if err != nil {
      return setErr(sqllex, err)
    }
    $$.val = []int32{bound}
  }
| '[' ICONST ']' '[' error { return unimplementedWithIssue(sqllex, 32552) }
| /* EMPTY */ { $$.val = []int32(nil) }

// general_type_name is a variant of type_or_function_name but does not
// include some extra keywords (like FAMILY) which cause ambiguity with
// parsing of typenames in certain contexts.
general_type_name:
  type_function_name_no_crdb_extra

// complex_type_name mirrors the rule for complex_db_object_name, but uses
// general_type_name rather than db_object_name_component to avoid conflicts.
complex_type_name:
  general_type_name '.' unrestricted_name
  {
    aIdx := sqllex.(*lexer).NewAnnotation()
    res, err := ast.NewUnresolvedObjectName(2, [3]string{$3, $1}, aIdx)
    if err != nil { return setErr(sqllex, err) }
    $$.val = res
  }
| general_type_name '.' unrestricted_name '.' unrestricted_name
  {
    aIdx := sqllex.(*lexer).NewAnnotation()
    res, err := ast.NewUnresolvedObjectName(3, [3]string{$5, $3, $1}, aIdx)
    if err != nil { return setErr(sqllex, err) }
    $$.val = res
  }

simple_typename:
  general_type_name
  {
    /* FORCE DOC */
    // See https://www.postgresql.org/docs/9.1/static/datatype-character.html
    // Postgres supports a special character type named "char" (with the quotes)
    // that is a single-character column type. It's used by system tables.
    // Eventually this clause will be used to parse user-defined types as well,
    // since their names can be quoted.
    if $1 == "char" {
      $$.val = types.MakeQChar(0)
    } else if $1 == "serial" {
        switch sqllex.(*lexer).nakedIntType.Width() {
        case 32:
          $$.val = &types.Serial4Type
        default:
          $$.val = &types.Serial8Type
        }
    } else {
      // Check the the type is one of our "non-keyword" type names.
      // Otherwise, package it up as a type reference for later.
      var ok bool
      var err error
      var unimp int
      $$.val, ok, unimp = types.TypeForNonKeywordTypeName($1)
      if !ok {
        switch unimp {
          case 0:
            // In this case, we don't think this type is one of our
            // known unsupported types, so make a type reference for it.
            aIdx := sqllex.(*lexer).NewAnnotation()
            $$.val, err = ast.NewUnresolvedObjectName(1, [3]string{$1}, aIdx)
            if err != nil { return setErr(sqllex, err) }
          case -1:
            return unimplemented(sqllex, "type name " + $1)
          default:
            return unimplementedWithIssueDetail(sqllex, unimp, $1)
        }
      }
    }
  }
| '@' iconst32
  {
    id := $2.int32()
    $$.val = &ast.IDTypeReference{ID: uint32(id)}
  }
| complex_type_name
  {
    $$.val = $1.typeReference()
  }
| const_typename
| bit_with_length
| character_with_length
| interval_type
| POINT error { return unimplementedWithIssueDetail(sqllex, 21286, "point") } // needed or else it generates a syntax error.
| POLYGON error { return unimplementedWithIssueDetail(sqllex, 21286, "polygon") } // needed or else it generates a syntax error.

geo_shape_type:
  POINT { $$.val = geopb.ShapeType_Point }
| LINESTRING { $$.val = geopb.ShapeType_LineString }
| POLYGON { $$.val = geopb.ShapeType_Polygon }
| GEOMETRYCOLLECTION { $$.val = geopb.ShapeType_GeometryCollection }
| MULTIPOLYGON { $$.val = geopb.ShapeType_MultiPolygon }
| MULTILINESTRING { $$.val = geopb.ShapeType_MultiLineString }
| MULTIPOINT { $$.val = geopb.ShapeType_MultiPoint }
| GEOMETRY { $$.val = geopb.ShapeType_Geometry }

const_geo:
  GEOGRAPHY { $$.val = types.Geography }
| GEOMETRY  { $$.val = types.Geometry }
| GEOMETRY '(' geo_shape_type ')'
  {
    $$.val = types.MakeGeometry($3.geoShapeType(), 0)
  }
| GEOGRAPHY '(' geo_shape_type ')'
  {
    $$.val = types.MakeGeography($3.geoShapeType(), 0)
  }
| GEOMETRY '(' geo_shape_type ',' signed_iconst ')'
  {
    val, err := $5.numVal().AsInt32()
    if err != nil {
      return setErr(sqllex, err)
    }
    $$.val = types.MakeGeometry($3.geoShapeType(), geopb.SRID(val))
  }
| GEOGRAPHY '(' geo_shape_type ',' signed_iconst ')'
  {
    val, err := $5.numVal().AsInt32()
    if err != nil {
      return setErr(sqllex, err)
    }
    $$.val = types.MakeGeography($3.geoShapeType(), geopb.SRID(val))
  }

// We have a separate const_typename to allow defaulting fixed-length types
// such as CHAR() and BIT() to an unspecified length. SQL9x requires that these
// default to a length of one, but this makes no sense for constructs like CHAR
// 'hi' and BIT '0101', where there is an obvious better choice to make. Note
// that interval_type is not included here since it must be pushed up higher
// in the rules to accommodate the postfix options (e.g. INTERVAL '1'
// YEAR). Likewise, we have to handle the generic-type-name case in
// a_expr_const to avoid premature reduce/reduce conflicts against function
// names.
const_typename:
  numeric
| bit_without_length
| character_without_length
| const_datetime
| const_geo

opt_numeric_modifiers:
  '(' iconst32 ')'
  {
    dec, err := newDecimal($2.int32(), 0)
    if err != nil {
      return setErr(sqllex, err)
    }
    $$.val = dec
  }
| '(' iconst32 ',' iconst32 ')'
  {
    dec, err := newDecimal($2.int32(), $4.int32())
    if err != nil {
      return setErr(sqllex, err)
    }
    $$.val = dec
  }
| /* EMPTY */
  {
    $$.val = nil
  }

// SQL numeric data types
numeric:
  INT
  {
    $$.val = sqllex.(*lexer).nakedIntType
  }
| INTEGER
  {
    $$.val = sqllex.(*lexer).nakedIntType
  }
| SMALLINT
  {
    $$.val = types.Int2
  }
| BIGINT
  {
    $$.val = types.Int
  }
| REAL
  {
    $$.val = types.Float4
  }
| FLOAT opt_float
  {
    $$.val = $2.colType()
  }
| DOUBLE PRECISION
  {
    $$.val = types.Float
  }
| DECIMAL opt_numeric_modifiers
  {
    typ := $2.colType()
    if typ == nil {
      typ = types.Decimal
    }
    $$.val = typ
  }
| DEC opt_numeric_modifiers
  {
    typ := $2.colType()
    if typ == nil {
      typ = types.Decimal
    }
    $$.val = typ
  }
| NUMERIC opt_numeric_modifiers
  {
    typ := $2.colType()
    if typ == nil {
      typ = types.Decimal
    }
    $$.val = typ
  }
| BOOLEAN
  {
    $$.val = types.Bool
  }

opt_float:
  '(' ICONST ')'
  {
    nv := $2.numVal()
    prec, err := nv.AsInt64()
    if err != nil {
      return setErr(sqllex, err)
    }
    typ, err := newFloat(prec)
    if err != nil {
      return setErr(sqllex, err)
    }
    $$.val = typ
  }
| /* EMPTY */
  {
    $$.val = types.Float
  }

bit_with_length:
  BIT opt_varying '(' iconst32 ')'
  {
    bit, err := newBitType($4.int32(), $2.bool())
    if err != nil { return setErr(sqllex, err) }
    $$.val = bit
  }
| VARBIT '(' iconst32 ')'
  {
    bit, err := newBitType($3.int32(), true)
    if err != nil { return setErr(sqllex, err) }
    $$.val = bit
  }

bit_without_length:
  BIT
  {
    $$.val = types.MakeBit(1)
  }
| BIT VARYING
  {
    $$.val = types.VarBit
  }
| VARBIT
  {
    $$.val = types.VarBit
  }

character_with_length:
  character_base '(' iconst32 ')'
  {
    colTyp := *$1.colType()
    n := $3.int32()
    if n == 0 {
      sqllex.Error(fmt.Sprintf("length for type %s must be at least 1", colTyp.SQLString()))
      return 1
    }
    $$.val = types.MakeScalar(types.StringFamily, colTyp.Oid(), colTyp.Precision(), n, colTyp.Locale())
  }

character_without_length:
  character_base
  {
    $$.val = $1.colType()
  }

character_base:
  char_aliases
  {
    $$.val = types.MakeChar(1)
  }
| char_aliases VARYING
  {
    $$.val = types.VarChar
  }
| VARCHAR
  {
    $$.val = types.VarChar
  }
| STRING
  {
    $$.val = types.String
  }

char_aliases:
  CHAR
| CHARACTER

opt_varying:
  VARYING     { $$.val = true }
| /* EMPTY */ { $$.val = false }

// SQL date/time types
const_datetime:
  DATE
  {
    $$.val = types.Date
  }
| TIME opt_timezone
  {
    if $2.bool() {
      $$.val = types.TimeTZ
    } else {
      $$.val = types.Time
    }
  }
| TIME '(' iconst32 ')' opt_timezone
  {
    prec := $3.int32()
    if prec < 0 || prec > 6 {
      sqllex.Error(fmt.Sprintf("precision %d out of range", prec))
      return 1
    }
    if $5.bool() {
      $$.val = types.MakeTimeTZ(prec)
    } else {
      $$.val = types.MakeTime(prec)
    }
  }
| TIMETZ                             { $$.val = types.TimeTZ }
| TIMETZ '(' iconst32 ')'
  {
    prec := $3.int32()
    if prec < 0 || prec > 6 {
      sqllex.Error(fmt.Sprintf("precision %d out of range", prec))
      return 1
    }
    $$.val = types.MakeTimeTZ(prec)
  }
| TIMESTAMP opt_timezone
  {
    if $2.bool() {
      $$.val = types.TimestampTZ
    } else {
      $$.val = types.Timestamp
    }
  }
| TIMESTAMP '(' iconst32 ')' opt_timezone
  {
    prec := $3.int32()
    if prec < 0 || prec > 6 {
      sqllex.Error(fmt.Sprintf("precision %d out of range", prec))
      return 1
    }
    if $5.bool() {
      $$.val = types.MakeTimestampTZ(prec)
    } else {
      $$.val = types.MakeTimestamp(prec)
    }
  }
| TIMESTAMPTZ
  {
    $$.val = types.TimestampTZ
  }
| TIMESTAMPTZ '(' iconst32 ')'
  {
    prec := $3.int32()
    if prec < 0 || prec > 6 {
      sqllex.Error(fmt.Sprintf("precision %d out of range", prec))
      return 1
    }
    $$.val = types.MakeTimestampTZ(prec)
  }

opt_timezone:
  WITH_LA TIME ZONE { $$.val = true; }
| WITHOUT TIME ZONE { $$.val = false; }
| /*EMPTY*/         { $$.val = false; }

interval_type:
  INTERVAL
  {
    $$.val = types.Interval
  }
| INTERVAL interval_qualifier
  {
    $$.val = types.MakeInterval($2.intervalTypeMetadata())
  }
| INTERVAL '(' iconst32 ')'
  {
    prec := $3.int32()
    if prec < 0 || prec > 6 {
      sqllex.Error(fmt.Sprintf("precision %d out of range", prec))
      return 1
    }
    $$.val = types.MakeInterval(types.IntervalTypeMetadata{Precision: prec, PrecisionIsSet: true})
  }

interval_qualifier:
  YEAR
  {
    $$.val = types.IntervalTypeMetadata{
      DurationField: types.IntervalDurationField{
        DurationType: types.IntervalDurationType_YEAR,
      },
    }
  }
| MONTH
  {
    $$.val = types.IntervalTypeMetadata{
      DurationField: types.IntervalDurationField{
        DurationType: types.IntervalDurationType_MONTH,
      },
    }
  }
| DAY
  {
    $$.val = types.IntervalTypeMetadata{
      DurationField: types.IntervalDurationField{
        DurationType: types.IntervalDurationType_DAY,
      },
    }
  }
| HOUR
  {
    $$.val = types.IntervalTypeMetadata{
      DurationField: types.IntervalDurationField{
        DurationType: types.IntervalDurationType_HOUR,
      },
    }
  }
| MINUTE
  {
    $$.val = types.IntervalTypeMetadata{
      DurationField: types.IntervalDurationField{
        DurationType: types.IntervalDurationType_MINUTE,
      },
    }
  }
| interval_second
  {
    $$.val = $1.intervalTypeMetadata()
  }
// Like Postgres, we ignore the left duration field. See explanation:
// https://www.postgresql.org/message-id/20110510040219.GD5617%40tornado.gateway.2wire.net
| YEAR TO MONTH
  {
    $$.val = types.IntervalTypeMetadata{
      DurationField: types.IntervalDurationField{
        FromDurationType: types.IntervalDurationType_YEAR,
        DurationType: types.IntervalDurationType_MONTH,
      },
    }
  }
| DAY TO HOUR
  {
    $$.val = types.IntervalTypeMetadata{
      DurationField: types.IntervalDurationField{
        FromDurationType: types.IntervalDurationType_DAY,
        DurationType: types.IntervalDurationType_HOUR,
      },
    }
  }
| DAY TO MINUTE
  {
    $$.val = types.IntervalTypeMetadata{
      DurationField: types.IntervalDurationField{
        FromDurationType: types.IntervalDurationType_DAY,
        DurationType: types.IntervalDurationType_MINUTE,
      },
    }
  }
| DAY TO interval_second
  {
    ret := $3.intervalTypeMetadata()
    ret.DurationField.FromDurationType = types.IntervalDurationType_DAY
    $$.val = ret
  }
| HOUR TO MINUTE
  {
    $$.val = types.IntervalTypeMetadata{
      DurationField: types.IntervalDurationField{
        FromDurationType: types.IntervalDurationType_HOUR,
        DurationType: types.IntervalDurationType_MINUTE,
      },
    }
  }
| HOUR TO interval_second
  {
    ret := $3.intervalTypeMetadata()
    ret.DurationField.FromDurationType = types.IntervalDurationType_HOUR
    $$.val = ret
  }
| MINUTE TO interval_second
  {
    $$.val = $3.intervalTypeMetadata()
    ret := $3.intervalTypeMetadata()
    ret.DurationField.FromDurationType = types.IntervalDurationType_MINUTE
    $$.val = ret
  }

opt_interval_qualifier:
  interval_qualifier
| /* EMPTY */
  {
    $$.val = nil
  }

interval_second:
  SECOND
  {
    $$.val = types.IntervalTypeMetadata{
      DurationField: types.IntervalDurationField{
        DurationType: types.IntervalDurationType_SECOND,
      },
    }
  }
| SECOND '(' iconst32 ')'
  {
    prec := $3.int32()
    if prec < 0 || prec > 6 {
      sqllex.Error(fmt.Sprintf("precision %d out of range", prec))
      return 1
    }
    $$.val = types.IntervalTypeMetadata{
      DurationField: types.IntervalDurationField{
        DurationType: types.IntervalDurationType_SECOND,
      },
      PrecisionIsSet: true,
      Precision: prec,
    }
  }

// General expressions. This is the heart of the expression syntax.
//
// We have two expression types: a_expr is the unrestricted kind, and b_expr is
// a subset that must be used in some places to avoid shift/reduce conflicts.
// For example, we can't do BETWEEN as "BETWEEN a_expr AND a_expr" because that
// use of AND conflicts with AND as a boolean operator. So, b_expr is used in
// BETWEEN and we remove boolean keywords from b_expr.
//
// Note that '(' a_expr ')' is a b_expr, so an unrestricted expression can
// always be used by surrounding it with parens.
//
// c_expr is all the productions that are common to a_expr and b_expr; it's
// factored out just to eliminate redundant coding.
//
// Be careful of productions involving more than one terminal token. By
// default, bison will assign such productions the precedence of their last
// terminal, but in nearly all cases you want it to be the precedence of the
// first terminal instead; otherwise you will not get the behavior you expect!
// So we use %prec annotations freely to set precedences.
a_expr:
  c_expr
| a_expr TYPECAST cast_target
  {
    $$.val = &ast.CastExpr{Expr: $1.expr(), Type: $3.typeReference(), SyntaxMode: ast.CastShort}
  }
| a_expr TYPEANNOTATE typename
  {
    $$.val = &ast.AnnotateTypeExpr{Expr: $1.expr(), Type: $3.typeReference(), SyntaxMode: ast.AnnotateShort}
  }
| a_expr COLLATE collation_name
  {
    $$.val = &ast.CollateExpr{Expr: $1.expr(), Locale: $3}
  }
| a_expr AT TIME ZONE a_expr %prec AT
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction("timezone"), Exprs: ast.Exprs{$5.expr(), $1.expr()}}
  }
  // These operators must be called out explicitly in order to make use of
  // bison's automatic operator-precedence handling. All other operator names
  // are handled by the generic productions using "OP", below; and all those
  // operators will have the same precedence.
  //
  // If you add more explicitly-known operators, be sure to add them also to
  // b_expr and to the math_op list below.
| '+' a_expr %prec UMINUS
  {
    // Unary plus is a no-op. Desugar immediately.
    $$.val = $2.expr()
  }
| '-' a_expr %prec UMINUS
  {
    $$.val = unaryNegation($2.expr())
  }
| '~' a_expr %prec UMINUS
  {
    $$.val = &ast.UnaryExpr{Operator: ast.UnaryComplement, Expr: $2.expr()}
  }
| SQRT a_expr
  {
    $$.val = &ast.UnaryExpr{Operator: ast.UnarySqrt, Expr: $2.expr()}
  }
| CBRT a_expr
  {
    $$.val = &ast.UnaryExpr{Operator: ast.UnaryCbrt, Expr: $2.expr()}
  }
| a_expr '+' a_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.Plus, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '-' a_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.Minus, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '*' a_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.Mult, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '/' a_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.Div, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr FLOORDIV a_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.FloorDiv, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '%' a_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.Mod, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '^' a_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.Pow, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '#' a_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.Bitxor, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '&' a_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.Bitand, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '|' a_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.Bitor, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '<' a_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.LT, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '>' a_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.GT, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '?' a_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.JSONExists, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr JSON_SOME_EXISTS a_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.JSONSomeExists, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr JSON_ALL_EXISTS a_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.JSONAllExists, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr CONTAINS a_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.Contains, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr CONTAINED_BY a_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.ContainedBy, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '=' a_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.EQ, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr CONCAT a_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.Concat, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr LSHIFT a_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.LShift, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr RSHIFT a_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.RShift, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr FETCHVAL a_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.JSONFetchVal, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr FETCHTEXT a_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.JSONFetchText, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr FETCHVAL_PATH a_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.JSONFetchValPath, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr FETCHTEXT_PATH a_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.JSONFetchTextPath, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr REMOVE_PATH a_expr
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction("json_remove_path"), Exprs: ast.Exprs{$1.expr(), $3.expr()}}
  }
| a_expr INET_CONTAINED_BY_OR_EQUALS a_expr
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction("inet_contained_by_or_equals"), Exprs: ast.Exprs{$1.expr(), $3.expr()}}
  }
| a_expr AND_AND a_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.Overlaps, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr INET_CONTAINS_OR_EQUALS a_expr
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction("inet_contains_or_equals"), Exprs: ast.Exprs{$1.expr(), $3.expr()}}
  }
| a_expr LESS_EQUALS a_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.LE, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr GREATER_EQUALS a_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.GE, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr NOT_EQUALS a_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.NE, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr AND a_expr
  {
    $$.val = &ast.AndExpr{Left: $1.expr(), Right: $3.expr()}
  }
| a_expr OR a_expr
  {
    $$.val = &ast.OrExpr{Left: $1.expr(), Right: $3.expr()}
  }
| NOT a_expr
  {
    $$.val = &ast.NotExpr{Expr: $2.expr()}
  }
| NOT_LA a_expr %prec NOT
  {
    $$.val = &ast.NotExpr{Expr: $2.expr()}
  }
| a_expr LIKE a_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.Like, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr LIKE a_expr ESCAPE a_expr %prec ESCAPE
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction("like_escape"), Exprs: ast.Exprs{$1.expr(), $3.expr(), $5.expr()}}
  }
| a_expr NOT_LA LIKE a_expr %prec NOT_LA
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.NotLike, Left: $1.expr(), Right: $4.expr()}
  }
| a_expr NOT_LA LIKE a_expr ESCAPE a_expr %prec ESCAPE
 {
   $$.val = &ast.FuncExpr{Func: ast.WrapFunction("not_like_escape"), Exprs: ast.Exprs{$1.expr(), $4.expr(), $6.expr()}}
 }
| a_expr ILIKE a_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.ILike, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr ILIKE a_expr ESCAPE a_expr %prec ESCAPE
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction("ilike_escape"), Exprs: ast.Exprs{$1.expr(), $3.expr(), $5.expr()}}
  }
| a_expr NOT_LA ILIKE a_expr %prec NOT_LA
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.NotILike, Left: $1.expr(), Right: $4.expr()}
  }
| a_expr NOT_LA ILIKE a_expr ESCAPE a_expr %prec ESCAPE
 {
   $$.val = &ast.FuncExpr{Func: ast.WrapFunction("not_ilike_escape"), Exprs: ast.Exprs{$1.expr(), $4.expr(), $6.expr()}}
 }
| a_expr SIMILAR TO a_expr %prec SIMILAR
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.SimilarTo, Left: $1.expr(), Right: $4.expr()}
  }
| a_expr SIMILAR TO a_expr ESCAPE a_expr %prec ESCAPE
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction("similar_to_escape"), Exprs: ast.Exprs{$1.expr(), $4.expr(), $6.expr()}}
  }
| a_expr NOT_LA SIMILAR TO a_expr %prec NOT_LA
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.NotSimilarTo, Left: $1.expr(), Right: $5.expr()}
  }
| a_expr NOT_LA SIMILAR TO a_expr ESCAPE a_expr %prec ESCAPE
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction("not_similar_to_escape"), Exprs: ast.Exprs{$1.expr(), $5.expr(), $7.expr()}}
  }
| a_expr '~' a_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.RegMatch, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr NOT_REGMATCH a_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.NotRegMatch, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr REGIMATCH a_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.RegIMatch, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr NOT_REGIMATCH a_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.NotRegIMatch, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr IS NAN %prec IS
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.EQ, Left: $1.expr(), Right: ast.NewStrVal("NaN")}
  }
| a_expr IS NOT NAN %prec IS
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.NE, Left: $1.expr(), Right: ast.NewStrVal("NaN")}
  }
| a_expr IS NULL %prec IS
  {
    $$.val = &ast.IsNullExpr{Expr: $1.expr()}
  }
| a_expr ISNULL %prec IS
  {
    $$.val = &ast.IsNullExpr{Expr: $1.expr()}
  }
| a_expr IS NOT NULL %prec IS
  {
    $$.val = &ast.IsNotNullExpr{Expr: $1.expr()}
  }
| a_expr NOTNULL %prec IS
  {
    $$.val = &ast.IsNotNullExpr{Expr: $1.expr()}
  }
| row OVERLAPS row { return unimplemented(sqllex, "overlaps") }
| a_expr IS TRUE %prec IS
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.IsNotDistinctFrom, Left: $1.expr(), Right: ast.MakeDBool(true)}
  }
| a_expr IS NOT TRUE %prec IS
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.IsDistinctFrom, Left: $1.expr(), Right: ast.MakeDBool(true)}
  }
| a_expr IS FALSE %prec IS
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.IsNotDistinctFrom, Left: $1.expr(), Right: ast.MakeDBool(false)}
  }
| a_expr IS NOT FALSE %prec IS
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.IsDistinctFrom, Left: $1.expr(), Right: ast.MakeDBool(false)}
  }
| a_expr IS UNKNOWN %prec IS
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.IsNotDistinctFrom, Left: $1.expr(), Right: ast.DNull}
  }
| a_expr IS NOT UNKNOWN %prec IS
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.IsDistinctFrom, Left: $1.expr(), Right: ast.DNull}
  }
| a_expr IS DISTINCT FROM a_expr %prec IS
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.IsDistinctFrom, Left: $1.expr(), Right: $5.expr()}
  }
| a_expr IS NOT DISTINCT FROM a_expr %prec IS
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.IsNotDistinctFrom, Left: $1.expr(), Right: $6.expr()}
  }
| a_expr IS OF '(' type_list ')' %prec IS
  {
    $$.val = &ast.IsOfTypeExpr{Expr: $1.expr(), Types: $5.typeReferences()}
  }
| a_expr IS NOT OF '(' type_list ')' %prec IS
  {
    $$.val = &ast.IsOfTypeExpr{Not: true, Expr: $1.expr(), Types: $6.typeReferences()}
  }
| a_expr BETWEEN opt_asymmetric b_expr AND a_expr %prec BETWEEN
  {
    $$.val = &ast.RangeCond{Left: $1.expr(), From: $4.expr(), To: $6.expr()}
  }
| a_expr NOT_LA BETWEEN opt_asymmetric b_expr AND a_expr %prec NOT_LA
  {
    $$.val = &ast.RangeCond{Not: true, Left: $1.expr(), From: $5.expr(), To: $7.expr()}
  }
| a_expr BETWEEN SYMMETRIC b_expr AND a_expr %prec BETWEEN
  {
    $$.val = &ast.RangeCond{Symmetric: true, Left: $1.expr(), From: $4.expr(), To: $6.expr()}
  }
| a_expr NOT_LA BETWEEN SYMMETRIC b_expr AND a_expr %prec NOT_LA
  {
    $$.val = &ast.RangeCond{Not: true, Symmetric: true, Left: $1.expr(), From: $5.expr(), To: $7.expr()}
  }
| a_expr IN in_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.In, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr NOT_LA IN in_expr %prec NOT_LA
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.NotIn, Left: $1.expr(), Right: $4.expr()}
  }
| a_expr subquery_op sub_type a_expr %prec CONCAT
  {
    op := $3.cmpOp()
    subOp := $2.op()
    subOpCmp, ok := subOp.(ast.ComparisonOperator)
    if !ok {
      sqllex.Error(fmt.Sprintf("%s %s <array> is invalid because %q is not a boolean operator",
        subOp, op, subOp))
      return 1
    }
    $$.val = &ast.ComparisonExpr{
      Operator: op,
      SubOperator: subOpCmp,
      Left: $1.expr(),
      Right: $4.expr(),
    }
  }
| DEFAULT
  {
    $$.val = ast.DefaultVal{}
  }
// The UNIQUE predicate is a standard SQL feature but not yet implemented
// in PostgreSQL (as of 10.5).
| UNIQUE '(' error { return unimplemented(sqllex, "UNIQUE predicate") }

// Restricted expressions
//
// b_expr is a subset of the complete expression syntax defined by a_expr.
//
// Presently, AND, NOT, IS, and IN are the a_expr keywords that would cause
// trouble in the places where b_expr is used. For simplicity, we just
// eliminate all the boolean-keyword-operator productions from b_expr.
b_expr:
  c_expr
| b_expr TYPECAST cast_target
  {
    $$.val = &ast.CastExpr{Expr: $1.expr(), Type: $3.typeReference(), SyntaxMode: ast.CastShort}
  }
| b_expr TYPEANNOTATE typename
  {
    $$.val = &ast.AnnotateTypeExpr{Expr: $1.expr(), Type: $3.typeReference(), SyntaxMode: ast.AnnotateShort}
  }
| '+' b_expr %prec UMINUS
  {
    $$.val = $2.expr()
  }
| '-' b_expr %prec UMINUS
  {
    $$.val = unaryNegation($2.expr())
  }
| '~' b_expr %prec UMINUS
  {
    $$.val = &ast.UnaryExpr{Operator: ast.UnaryComplement, Expr: $2.expr()}
  }
| b_expr '+' b_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.Plus, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '-' b_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.Minus, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '*' b_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.Mult, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '/' b_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.Div, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr FLOORDIV b_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.FloorDiv, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '%' b_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.Mod, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '^' b_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.Pow, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '#' b_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.Bitxor, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '&' b_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.Bitand, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '|' b_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.Bitor, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '<' b_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.LT, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '>' b_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.GT, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '=' b_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.EQ, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr CONCAT b_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.Concat, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr LSHIFT b_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.LShift, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr RSHIFT b_expr
  {
    $$.val = &ast.BinaryExpr{Operator: ast.RShift, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr LESS_EQUALS b_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.LE, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr GREATER_EQUALS b_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.GE, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr NOT_EQUALS b_expr
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.NE, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr IS DISTINCT FROM b_expr %prec IS
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.IsDistinctFrom, Left: $1.expr(), Right: $5.expr()}
  }
| b_expr IS NOT DISTINCT FROM b_expr %prec IS
  {
    $$.val = &ast.ComparisonExpr{Operator: ast.IsNotDistinctFrom, Left: $1.expr(), Right: $6.expr()}
  }
| b_expr IS OF '(' type_list ')' %prec IS
  {
    $$.val = &ast.IsOfTypeExpr{Expr: $1.expr(), Types: $5.typeReferences()}
  }
| b_expr IS NOT OF '(' type_list ')' %prec IS
  {
    $$.val = &ast.IsOfTypeExpr{Not: true, Expr: $1.expr(), Types: $6.typeReferences()}
  }

// Productions that can be used in both a_expr and b_expr.
//
// Note: productions that refer recursively to a_expr or b_expr mostly cannot
// appear here. However, it's OK to refer to a_exprs that occur inside
// parentheses, such as function arguments; that cannot introduce ambiguity to
// the b_expr syntax.
//
c_expr:
  d_expr
| d_expr array_subscripts
  {
    $$.val = &ast.IndirectionExpr{
      Expr: $1.expr(),
      Indirection: $2.arraySubscripts(),
    }
  }
| case_expr
| EXISTS select_with_parens
  {
    $$.val = &ast.Subquery{Select: $2.selectStmt(), Exists: true}
  }

// Productions that can be followed by a postfix operator.
//
// Currently we support array indexing (see c_expr above).
//
// TODO(knz/jordan): this is the rule that can be extended to support
// composite types (#27792) with e.g.:
//
//     | '(' a_expr ')' field_access_ops
//
//     [...]
//
//     // field_access_ops supports the notations:
//     // - .a
//     // - .a[123]
//     // - .a.b[123][5456].c.d
//     // NOT [123] directly, this is handled in c_expr above.
//
//     field_access_ops:
//       field_access_op
//     | field_access_op other_subscripts
//
//     field_access_op:
//       '.' name
//     other_subscripts:
//       other_subscript
//     | other_subscripts other_subscript
//     other_subscript:
//        field_access_op
//     |  array_subscripts

d_expr:
  ICONST
  {
    $$.val = $1.numVal()
  }
| FCONST
  {
    $$.val = $1.numVal()
  }
| SCONST
  {
    $$.val = ast.NewStrVal($1)
  }
| BCONST
  {
    $$.val = ast.NewBytesStrVal($1)
  }
| BITCONST
  {
    d, err := ast.ParseDBitArray($1)
    if err != nil { return setErr(sqllex, err) }
    $$.val = d
  }
| func_name '(' expr_list opt_sort_clause ')' SCONST { return unimplemented(sqllex, $1.unresolvedName().String() + "(...) SCONST") }
| typed_literal
  {
    $$.val = $1.expr()
  }
| interval_value
  {
    $$.val = $1.expr()
  }
| TRUE
  {
    $$.val = ast.MakeDBool(true)
  }
| FALSE
  {
    $$.val = ast.MakeDBool(false)
  }
| NULL
  {
    $$.val = ast.DNull
  }
| column_path_with_star
  {
    $$.val = ast.Expr($1.unresolvedName())
  }
| '@' iconst64
  {
    colNum := $2.int64()
    if colNum < 1 || colNum > int64(MaxInt) {
      sqllex.Error(fmt.Sprintf("invalid column ordinal: @%d", colNum))
      return 1
    }
    $$.val = ast.NewOrdinalReference(int(colNum-1))
  }
| PLACEHOLDER
  {
    p := $1.placeholder()
    sqllex.(*lexer).UpdateNumPlaceholders(p)
    $$.val = p
  }
// TODO(knz/jordan): extend this for compound types. See explanation above.
| '(' a_expr ')' '.' '*'
  {
    $$.val = &ast.TupleStar{Expr: $2.expr()}
  }
| '(' a_expr ')' '.' unrestricted_name
  {
    $$.val = &ast.ColumnAccessExpr{Expr: $2.expr(), ColName: $5 }
  }
| '(' a_expr ')' '.' '@' ICONST
  {
    idx, err := $6.numVal().AsInt32()
    if err != nil || idx <= 0 { return setErr(sqllex, err) }
    $$.val = &ast.ColumnAccessExpr{Expr: $2.expr(), ByIndex: true, ColIndex: int(idx-1)}
  }
| '(' a_expr ')'
  {
    $$.val = &ast.ParenExpr{Expr: $2.expr()}
  }
| func_expr
| select_with_parens %prec UMINUS
  {
    $$.val = &ast.Subquery{Select: $1.selectStmt()}
  }
| labeled_row
  {
    $$.val = $1.tuple()
  }
| ARRAY select_with_parens %prec UMINUS
  {
    $$.val = &ast.ArrayFlatten{Subquery: &ast.Subquery{Select: $2.selectStmt()}}
  }
| ARRAY row
  {
    $$.val = &ast.Array{Exprs: $2.tuple().Exprs}
  }
| ARRAY array_expr
  {
    $$.val = $2.expr()
  }
| GROUPING '(' expr_list ')' { return unimplemented(sqllex, "d_expr grouping") }

func_application:
  func_name '(' ')'
  {
    $$.val = &ast.FuncExpr{Func: $1.resolvableFuncRefFromName()}
  }
| func_name '(' expr_list opt_sort_clause ')'
  {
    $$.val = &ast.FuncExpr{Func: $1.resolvableFuncRefFromName(), Exprs: $3.exprs(), OrderBy: $4.orderBy(), AggType: ast.GeneralAgg}
  }
| func_name '(' VARIADIC a_expr opt_sort_clause ')' { return unimplemented(sqllex, "variadic") }
| func_name '(' expr_list ',' VARIADIC a_expr opt_sort_clause ')' { return unimplemented(sqllex, "variadic") }
| func_name '(' ALL expr_list opt_sort_clause ')'
  {
    $$.val = &ast.FuncExpr{Func: $1.resolvableFuncRefFromName(), Type: ast.AllFuncType, Exprs: $4.exprs(), OrderBy: $5.orderBy(), AggType: ast.GeneralAgg}
  }
// TODO(ridwanmsharif): Once DISTINCT is supported by window aggregates,
// allow ordering to be specified below.
| func_name '(' DISTINCT expr_list ')'
  {
    $$.val = &ast.FuncExpr{Func: $1.resolvableFuncRefFromName(), Type: ast.DistinctFuncType, Exprs: $4.exprs()}
  }
| func_name '(' '*' ')'
  {
    $$.val = &ast.FuncExpr{Func: $1.resolvableFuncRefFromName(), Exprs: ast.Exprs{ast.StarExpr()}}
  }
| func_name '(' error { return helpWithFunction(sqllex, $1.resolvableFuncRefFromName()) }

// typed_literal represents expressions like INT '4', or generally <TYPE> SCONST.
// This rule handles both the case of qualified and non-qualified typenames.
typed_literal:
  // The key here is that none of the keywords in the func_name_no_crdb_extra
  // production can overlap with the type rules in const_typename, otherwise
  // we will have conflicts between this rule and the one below.
  func_name_no_crdb_extra SCONST
  {
    name := $1.unresolvedName()
    if name.NumParts == 1 {
      typName := name.Parts[0]
      /* FORCE DOC */
      // See https://www.postgresql.org/docs/9.1/static/datatype-character.html
      // Postgres supports a special character type named "char" (with the quotes)
      // that is a single-character column type. It's used by system tables.
      // Eventually this clause will be used to parse user-defined types as well,
      // since their names can be quoted.
      if typName == "char" {
        $$.val = &ast.CastExpr{Expr: ast.NewStrVal($2), Type: types.MakeQChar(0), SyntaxMode: ast.CastPrepend}
      } else if typName == "serial" {
        switch sqllex.(*lexer).nakedIntType.Width() {
        case 32:
          $$.val = &ast.CastExpr{Expr: ast.NewStrVal($2), Type: &types.Serial4Type, SyntaxMode: ast.CastPrepend}
        default:
          $$.val = &ast.CastExpr{Expr: ast.NewStrVal($2), Type: &types.Serial8Type, SyntaxMode: ast.CastPrepend}
        }
      } else {
        // Check the the type is one of our "non-keyword" type names.
        // Otherwise, package it up as a type reference for later.
        // However, if the type name is one of our known unsupported
        // types, return an unimplemented error message.
        var typ ast.ResolvableTypeReference
        var ok bool
        var err error
        var unimp int
        typ, ok, unimp = types.TypeForNonKeywordTypeName(typName)
        if !ok {
          switch unimp {
            case 0:
              // In this case, we don't think this type is one of our
              // known unsupported types, so make a type reference for it.
              aIdx := sqllex.(*lexer).NewAnnotation()
              typ, err = name.ToUnresolvedObjectName(aIdx)
              if err != nil { return setErr(sqllex, err) }
            case -1:
              return unimplemented(sqllex, "type name " + typName)
            default:
              return unimplementedWithIssueDetail(sqllex, unimp, typName)
          }
        }
      $$.val = &ast.CastExpr{Expr: ast.NewStrVal($2), Type: typ, SyntaxMode: ast.CastPrepend}
      }
    } else {
      aIdx := sqllex.(*lexer).NewAnnotation()
      res, err := name.ToUnresolvedObjectName(aIdx)
      if err != nil { return setErr(sqllex, err) }
      $$.val = &ast.CastExpr{Expr: ast.NewStrVal($2), Type: res, SyntaxMode: ast.CastPrepend}
    }
  }
| const_typename SCONST
  {
    $$.val = &ast.CastExpr{Expr: ast.NewStrVal($2), Type: $1.colType(), SyntaxMode: ast.CastPrepend}
  }

// func_expr and its cousin func_expr_windowless are split out from c_expr just
// so that we have classifications for "everything that is a function call or
// looks like one". This isn't very important, but it saves us having to
// document which variants are legal in places like "FROM function()" or the
// backwards-compatible functional-index syntax for CREATE INDEX. (Note that
// many of the special SQL functions wouldn't actually make any sense as
// functional index entries, but we ignore that consideration here.)
func_expr:
  func_application within_group_clause filter_clause over_clause
  {
    f := $1.expr().(*ast.FuncExpr)
    w := $2.expr().(*ast.FuncExpr)
    if w.AggType != 0 {
      f.AggType = w.AggType
      f.OrderBy = w.OrderBy
    }
    f.Filter = $3.expr()
    f.WindowDef = $4.windowDef()
    $$.val = f
  }
| func_expr_common_subexpr
  {
    $$.val = $1.expr()
  }

// As func_expr but does not accept WINDOW functions directly (but they can
// still be contained in arguments for functions etc). Use this when window
// expressions are not allowed, where needed to disambiguate the grammar
// (e.g. in CREATE INDEX).
func_expr_windowless:
  func_application { $$.val = $1.expr() }
| func_expr_common_subexpr { $$.val = $1.expr() }

// Special expressions that are considered to be functions.
func_expr_common_subexpr:
  COLLATION FOR '(' a_expr ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction("pg_collation_for"), Exprs: ast.Exprs{$4.expr()}}
  }
| CURRENT_DATE
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1)}
  }
| CURRENT_SCHEMA
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1)}
  }
// Special identifier current_catalog is equivalent to current_database().
// https://www.postgresql.org/docs/10/static/functions-info.html
| CURRENT_CATALOG
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction("current_database")}
  }
| CURRENT_TIMESTAMP
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1)}
  }
| CURRENT_TIME
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1)}
  }
| LOCALTIMESTAMP
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1)}
  }
| LOCALTIME
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1)}
  }
| CURRENT_USER
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1)}
  }
// Special identifier current_role is equivalent to current_user.
// https://www.postgresql.org/docs/10/static/functions-info.html
| CURRENT_ROLE
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction("current_user")}
  }
| SESSION_USER
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction("current_user")}
  }
| USER
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction("current_user")}
  }
| CAST '(' a_expr AS cast_target ')'
  {
    $$.val = &ast.CastExpr{Expr: $3.expr(), Type: $5.typeReference(), SyntaxMode: ast.CastExplicit}
  }
| ANNOTATE_TYPE '(' a_expr ',' typename ')'
  {
    $$.val = &ast.AnnotateTypeExpr{Expr: $3.expr(), Type: $5.typeReference(), SyntaxMode: ast.AnnotateExplicit}
  }
| IF '(' a_expr ',' a_expr ',' a_expr ')'
  {
    $$.val = &ast.IfExpr{Cond: $3.expr(), True: $5.expr(), Else: $7.expr()}
  }
| IFERROR '(' a_expr ',' a_expr ',' a_expr ')'
  {
    $$.val = &ast.IfErrExpr{Cond: $3.expr(), Else: $5.expr(), ErrCode: $7.expr()}
  }
| IFERROR '(' a_expr ',' a_expr ')'
  {
    $$.val = &ast.IfErrExpr{Cond: $3.expr(), Else: $5.expr()}
  }
| ISERROR '(' a_expr ')'
  {
    $$.val = &ast.IfErrExpr{Cond: $3.expr()}
  }
| ISERROR '(' a_expr ',' a_expr ')'
  {
    $$.val = &ast.IfErrExpr{Cond: $3.expr(), ErrCode: $5.expr()}
  }
| NULLIF '(' a_expr ',' a_expr ')'
  {
    $$.val = &ast.NullIfExpr{Expr1: $3.expr(), Expr2: $5.expr()}
  }
| IFNULL '(' a_expr ',' a_expr ')'
  {
    $$.val = &ast.CoalesceExpr{Name: "IFNULL", Exprs: ast.Exprs{$3.expr(), $5.expr()}}
  }
| COALESCE '(' expr_list ')'
  {
    $$.val = &ast.CoalesceExpr{Name: "COALESCE", Exprs: $3.exprs()}
  }
| special_function

special_function:
  CURRENT_DATE '(' ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1)}
  }
| CURRENT_DATE '(' error { return helpWithFunctionByName(sqllex, $1) }
| CURRENT_SCHEMA '(' ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1)}
  }
| CURRENT_SCHEMA '(' error { return helpWithFunctionByName(sqllex, $1) }
| CURRENT_TIMESTAMP '(' ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1)}
  }
| CURRENT_TIMESTAMP '(' a_expr ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1), Exprs: ast.Exprs{$3.expr()}}
  }
| CURRENT_TIMESTAMP '(' error { return helpWithFunctionByName(sqllex, $1) }
| CURRENT_TIME '(' ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1)}
  }
| CURRENT_TIME '(' a_expr ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1), Exprs: ast.Exprs{$3.expr()}}
  }
| CURRENT_TIME '(' error { return helpWithFunctionByName(sqllex, $1) }
| LOCALTIMESTAMP '(' ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1)}
  }
| LOCALTIMESTAMP '(' a_expr ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1), Exprs: ast.Exprs{$3.expr()}}
  }
| LOCALTIMESTAMP '(' error { return helpWithFunctionByName(sqllex, $1) }
| LOCALTIME '(' ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1)}
  }
| LOCALTIME '(' a_expr ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1), Exprs: ast.Exprs{$3.expr()}}
  }
| LOCALTIME '(' error { return helpWithFunctionByName(sqllex, $1) }
| CURRENT_USER '(' ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1)}
  }
| CURRENT_USER '(' error { return helpWithFunctionByName(sqllex, $1) }
| EXTRACT '(' extract_list ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1), Exprs: $3.exprs()}
  }
| EXTRACT '(' error { return helpWithFunctionByName(sqllex, $1) }
| EXTRACT_DURATION '(' extract_list ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1), Exprs: $3.exprs()}
  }
| EXTRACT_DURATION '(' error { return helpWithFunctionByName(sqllex, $1) }
| OVERLAY '(' overlay_list ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1), Exprs: $3.exprs()}
  }
| OVERLAY '(' error { return helpWithFunctionByName(sqllex, $1) }
| POSITION '(' position_list ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction("strpos"), Exprs: $3.exprs()}
  }
| SUBSTRING '(' substr_list ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1), Exprs: $3.exprs()}
  }
| SUBSTRING '(' error { return helpWithFunctionByName(sqllex, $1) }
| TREAT '(' a_expr AS typename ')' { return unimplemented(sqllex, "treat") }
| TRIM '(' BOTH trim_list ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction("btrim"), Exprs: $4.exprs()}
  }
| TRIM '(' LEADING trim_list ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction("ltrim"), Exprs: $4.exprs()}
  }
| TRIM '(' TRAILING trim_list ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction("rtrim"), Exprs: $4.exprs()}
  }
| TRIM '(' trim_list ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction("btrim"), Exprs: $3.exprs()}
  }
| GREATEST '(' expr_list ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1), Exprs: $3.exprs()}
  }
| GREATEST '(' error { return helpWithFunctionByName(sqllex, $1) }
| LEAST '(' expr_list ')'
  {
    $$.val = &ast.FuncExpr{Func: ast.WrapFunction($1), Exprs: $3.exprs()}
  }
| LEAST '(' error { return helpWithFunctionByName(sqllex, $1) }


// Aggregate decoration clauses
within_group_clause:
  WITHIN GROUP '(' single_sort_clause ')'
  {
    $$.val = &ast.FuncExpr{OrderBy: $4.orderBy(), AggType: ast.OrderedSetAgg}
  }
| /* EMPTY */
  {
    $$.val = &ast.FuncExpr{}
  }

filter_clause:
  FILTER '(' WHERE a_expr ')'
  {
    $$.val = $4.expr()
  }
| /* EMPTY */
  {
    $$.val = ast.Expr(nil)
  }

// Window Definitions
window_clause:
  WINDOW window_definition_list
  {
    $$.val = $2.window()
  }
| /* EMPTY */
  {
    $$.val = ast.Window(nil)
  }

window_definition_list:
  window_definition
  {
    $$.val = ast.Window{$1.windowDef()}
  }
| window_definition_list ',' window_definition
  {
    $$.val = append($1.window(), $3.windowDef())
  }

window_definition:
  window_name AS window_specification
  {
    n := $3.windowDef()
    n.Name = ast.Name($1)
    $$.val = n
  }

over_clause:
  OVER window_specification
  {
    $$.val = $2.windowDef()
  }
| OVER window_name
  {
    $$.val = &ast.WindowDef{Name: ast.Name($2)}
  }
| /* EMPTY */
  {
    $$.val = (*ast.WindowDef)(nil)
  }

window_specification:
  '(' opt_existing_window_name opt_partition_clause
    opt_sort_clause opt_frame_clause ')'
  {
    $$.val = &ast.WindowDef{
      RefName: ast.Name($2),
      Partitions: $3.exprs(),
      OrderBy: $4.orderBy(),
      Frame: $5.windowFrame(),
    }
  }

// If we see PARTITION, RANGE, ROWS, or GROUPS as the first token after the '('
// of a window_specification, we want the assumption to be that there is no
// existing_window_name; but those keywords are unreserved and so could be
// names. We fix this by making them have the same precedence as IDENT and
// giving the empty production here a slightly higher precedence, so that the
// shift/reduce conflict is resolved in favor of reducing the rule. These
// keywords are thus precluded from being an existing_window_name but are not
// reserved for any other purpose.
opt_existing_window_name:
  name
| /* EMPTY */ %prec CONCAT
  {
    $$ = ""
  }

opt_partition_clause:
  PARTITION BY expr_list
  {
    $$.val = $3.exprs()
  }
| /* EMPTY */
  {
    $$.val = ast.Exprs(nil)
  }

opt_frame_clause:
  RANGE frame_extent opt_frame_exclusion
  {
    $$.val = &ast.WindowFrame{
      Mode: ast.RANGE,
      Bounds: $2.windowFrameBounds(),
      Exclusion: $3.windowFrameExclusion(),
    }
  }
| ROWS frame_extent opt_frame_exclusion
  {
    $$.val = &ast.WindowFrame{
      Mode: ast.ROWS,
      Bounds: $2.windowFrameBounds(),
      Exclusion: $3.windowFrameExclusion(),
    }
  }
| GROUPS frame_extent opt_frame_exclusion
  {
    $$.val = &ast.WindowFrame{
      Mode: ast.GROUPS,
      Bounds: $2.windowFrameBounds(),
      Exclusion: $3.windowFrameExclusion(),
    }
  }
| /* EMPTY */
  {
    $$.val = (*ast.WindowFrame)(nil)
  }

frame_extent:
  frame_bound
  {
    startBound := $1.windowFrameBound()
    switch {
    case startBound.BoundType == ast.UnboundedFollowing:
      sqllex.Error("frame start cannot be UNBOUNDED FOLLOWING")
      return 1
    case startBound.BoundType == ast.OffsetFollowing:
      sqllex.Error("frame starting from following row cannot end with current row")
      return 1
    }
    $$.val = ast.WindowFrameBounds{StartBound: startBound}
  }
| BETWEEN frame_bound AND frame_bound
  {
    startBound := $2.windowFrameBound()
    endBound := $4.windowFrameBound()
    switch {
    case startBound.BoundType == ast.UnboundedFollowing:
      sqllex.Error("frame start cannot be UNBOUNDED FOLLOWING")
      return 1
    case endBound.BoundType == ast.UnboundedPreceding:
      sqllex.Error("frame end cannot be UNBOUNDED PRECEDING")
      return 1
    case startBound.BoundType == ast.CurrentRow && endBound.BoundType == ast.OffsetPreceding:
      sqllex.Error("frame starting from current row cannot have preceding rows")
      return 1
    case startBound.BoundType == ast.OffsetFollowing && endBound.BoundType == ast.OffsetPreceding:
      sqllex.Error("frame starting from following row cannot have preceding rows")
      return 1
    case startBound.BoundType == ast.OffsetFollowing && endBound.BoundType == ast.CurrentRow:
      sqllex.Error("frame starting from following row cannot have preceding rows")
      return 1
    }
    $$.val = ast.WindowFrameBounds{StartBound: startBound, EndBound: endBound}
  }

// This is used for both frame start and frame end, with output set up on the
// assumption it's frame start; the frame_extent productions must reject
// invalid cases.
frame_bound:
  UNBOUNDED PRECEDING
  {
    $$.val = &ast.WindowFrameBound{BoundType: ast.UnboundedPreceding}
  }
| UNBOUNDED FOLLOWING
  {
    $$.val = &ast.WindowFrameBound{BoundType: ast.UnboundedFollowing}
  }
| CURRENT ROW
  {
    $$.val = &ast.WindowFrameBound{BoundType: ast.CurrentRow}
  }
| a_expr PRECEDING
  {
    $$.val = &ast.WindowFrameBound{
      OffsetExpr: $1.expr(),
      BoundType: ast.OffsetPreceding,
    }
  }
| a_expr FOLLOWING
  {
    $$.val = &ast.WindowFrameBound{
      OffsetExpr: $1.expr(),
      BoundType: ast.OffsetFollowing,
    }
  }

opt_frame_exclusion:
  EXCLUDE CURRENT ROW
  {
    $$.val = ast.ExcludeCurrentRow
  }
| EXCLUDE GROUP
  {
    $$.val = ast.ExcludeGroup
  }
| EXCLUDE TIES
  {
    $$.val = ast.ExcludeTies
  }
| EXCLUDE NO OTHERS
  {
    // EXCLUDE NO OTHERS is equivalent to omitting the frame exclusion clause.
    $$.val = ast.NoExclusion
  }
| /* EMPTY */
  {
    $$.val = ast.NoExclusion
  }

// Supporting nonterminals for expressions.

// Explicit row production.
//
// SQL99 allows an optional ROW keyword, so we can now do single-element rows
// without conflicting with the parenthesized a_expr production. Without the
// ROW keyword, there must be more than one a_expr inside the parens.
row:
  ROW '(' opt_expr_list ')'
  {
    $$.val = &ast.Tuple{Exprs: $3.exprs(), Row: true}
  }
| expr_tuple_unambiguous
  {
    $$.val = $1.tuple()
  }

labeled_row:
  row
| '(' row AS name_list ')'
  {
    t := $2.tuple()
    labels := $4.nameList()
    t.Labels = make([]string, len(labels))
    for i, l := range labels {
      t.Labels[i] = string(l)
    }
    $$.val = t
  }

sub_type:
  ANY
  {
    $$.val = ast.Any
  }
| SOME
  {
    $$.val = ast.Some
  }
| ALL
  {
    $$.val = ast.All
  }

math_op:
  '+' { $$.val = ast.Plus  }
| '-' { $$.val = ast.Minus }
| '*' { $$.val = ast.Mult  }
| '/' { $$.val = ast.Div   }
| FLOORDIV { $$.val = ast.FloorDiv }
| '%' { $$.val = ast.Mod    }
| '&' { $$.val = ast.Bitand }
| '|' { $$.val = ast.Bitor  }
| '^' { $$.val = ast.Pow }
| '#' { $$.val = ast.Bitxor }
| '<' { $$.val = ast.LT }
| '>' { $$.val = ast.GT }
| '=' { $$.val = ast.EQ }
| LESS_EQUALS    { $$.val = ast.LE }
| GREATER_EQUALS { $$.val = ast.GE }
| NOT_EQUALS     { $$.val = ast.NE }

subquery_op:
  math_op
| LIKE         { $$.val = ast.Like     }
| NOT_LA LIKE  { $$.val = ast.NotLike  }
| ILIKE        { $$.val = ast.ILike    }
| NOT_LA ILIKE { $$.val = ast.NotILike }
  // cannot put SIMILAR TO here, because SIMILAR TO is a hack.
  // the regular expression is preprocessed by a function (similar_escape),
  // and the ~ operator for posix regular expressions is used.
  //        x SIMILAR TO y     ->    x ~ similar_escape(y)
  // this transformation is made on the fly by the parser upwards.
  // however the SubLink structure which handles any/some/all stuff
  // is not ready for such a thing.

// expr_tuple1_ambiguous is a tuple expression with at least one expression.
// The allowable syntax is:
// ( )         -- empty tuple.
// ( E )       -- just one value, this is potentially ambiguous with
//             -- grouping parentheses. The ambiguity is resolved
//             -- by only allowing expr_tuple1_ambiguous on the RHS
//             -- of a IN expression.
// ( E, E, E ) -- comma-separated values, no trailing comma allowed.
// ( E, )      -- just one value with a comma, makes the syntax unambiguous
//             -- with grouping parentheses. This is not usually produced
//             -- by SQL clients, but can be produced by pretty-printing
//             -- internally in CockroachDB.
expr_tuple1_ambiguous:
  '(' ')'
  {
    $$.val = &ast.Tuple{}
  }
| '(' tuple1_ambiguous_values ')'
  {
    $$.val = &ast.Tuple{Exprs: $2.exprs()}
  }

tuple1_ambiguous_values:
  a_expr
  {
    $$.val = ast.Exprs{$1.expr()}
  }
| a_expr ','
  {
    $$.val = ast.Exprs{$1.expr()}
  }
| a_expr ',' expr_list
  {
     $$.val = append(ast.Exprs{$1.expr()}, $3.exprs()...)
  }

// expr_tuple_unambiguous is a tuple expression with zero or more
// expressions. The allowable syntax is:
// ( )         -- zero values
// ( E, )      -- just one value. This is unambiguous with the (E) grouping syntax.
// ( E, E, E ) -- comma-separated values, more than 1.
expr_tuple_unambiguous:
  '(' ')'
  {
    $$.val = &ast.Tuple{}
  }
| '(' tuple1_unambiguous_values ')'
  {
    $$.val = &ast.Tuple{Exprs: $2.exprs()}
  }

tuple1_unambiguous_values:
  a_expr ','
  {
    $$.val = ast.Exprs{$1.expr()}
  }
| a_expr ',' expr_list
  {
     $$.val = append(ast.Exprs{$1.expr()}, $3.exprs()...)
  }

opt_expr_list:
  expr_list
| /* EMPTY */
  {
    $$.val = ast.Exprs(nil)
  }

expr_list:
  a_expr
  {
    $$.val = ast.Exprs{$1.expr()}
  }
| expr_list ',' a_expr
  {
    $$.val = append($1.exprs(), $3.expr())
  }

type_list:
  typename
  {
    $$.val = []ast.ResolvableTypeReference{$1.typeReference()}
  }
| type_list ',' typename
  {
    $$.val = append($1.typeReferences(), $3.typeReference())
  }

array_expr:
  '[' opt_expr_list ']'
  {
    $$.val = &ast.Array{Exprs: $2.exprs()}
  }
| '[' array_expr_list ']'
  {
    $$.val = &ast.Array{Exprs: $2.exprs()}
  }

array_expr_list:
  array_expr
  {
    $$.val = ast.Exprs{$1.expr()}
  }
| array_expr_list ',' array_expr
  {
    $$.val = append($1.exprs(), $3.expr())
  }

extract_list:
  extract_arg FROM a_expr
  {
    $$.val = ast.Exprs{ast.NewStrVal($1), $3.expr()}
  }
| expr_list
  {
    $$.val = $1.exprs()
  }

// TODO(vivek): Narrow down to just IDENT once the other
// terms are not keywords.
extract_arg:
  IDENT
| YEAR
| MONTH
| DAY
| HOUR
| MINUTE
| SECOND
| SCONST

// OVERLAY() arguments
// SQL99 defines the OVERLAY() function:
//   - overlay(text placing text from int for int)
//   - overlay(text placing text from int)
// and similarly for binary strings
overlay_list:
  a_expr overlay_placing substr_from substr_for
  {
    $$.val = ast.Exprs{$1.expr(), $2.expr(), $3.expr(), $4.expr()}
  }
| a_expr overlay_placing substr_from
  {
    $$.val = ast.Exprs{$1.expr(), $2.expr(), $3.expr()}
  }
| expr_list
  {
    $$.val = $1.exprs()
  }

overlay_placing:
  PLACING a_expr
  {
    $$.val = $2.expr()
  }

// position_list uses b_expr not a_expr to avoid conflict with general IN
position_list:
  b_expr IN b_expr
  {
    $$.val = ast.Exprs{$3.expr(), $1.expr()}
  }
| /* EMPTY */
  {
    $$.val = ast.Exprs(nil)
  }

// SUBSTRING() arguments
// SQL9x defines a specific syntax for arguments to SUBSTRING():
//   - substring(text from int for int)
//   - substring(text from int) get entire string from starting point "int"
//   - substring(text for int) get first "int" characters of string
//   - substring(text from pattern) get entire string matching pattern
//   - substring(text from pattern for escape) same with specified escape char
// We also want to support generic substring functions which accept
// the usual generic list of arguments. So we will accept both styles
// here, and convert the SQL9x style to the generic list for further
// processing. - thomas 2000-11-28
substr_list:
  a_expr substr_from substr_for
  {
    $$.val = ast.Exprs{$1.expr(), $2.expr(), $3.expr()}
  }
| a_expr substr_for substr_from
  {
    $$.val = ast.Exprs{$1.expr(), $3.expr(), $2.expr()}
  }
| a_expr substr_from
  {
    $$.val = ast.Exprs{$1.expr(), $2.expr()}
  }
| a_expr substr_for
  {
    $$.val = ast.Exprs{$1.expr(), ast.NewDInt(1), $2.expr()}
  }
| opt_expr_list
  {
    $$.val = $1.exprs()
  }

substr_from:
  FROM a_expr
  {
    $$.val = $2.expr()
  }

substr_for:
  FOR a_expr
  {
    $$.val = $2.expr()
  }

trim_list:
  a_expr FROM expr_list
  {
    $$.val = append($3.exprs(), $1.expr())
  }
| FROM expr_list
  {
    $$.val = $2.exprs()
  }
| expr_list
  {
    $$.val = $1.exprs()
  }

in_expr:
  select_with_parens
  {
    $$.val = &ast.Subquery{Select: $1.selectStmt()}
  }
| expr_tuple1_ambiguous

// Define SQL-style CASE clause.
// - Full specification
//      CASE WHEN a = b THEN c ... ELSE d END
// - Implicit argument
//      CASE a WHEN b THEN c ... ELSE d END
case_expr:
  CASE case_arg when_clause_list case_default END
  {
    $$.val = &ast.CaseExpr{Expr: $2.expr(), Whens: $3.whens(), Else: $4.expr()}
  }

when_clause_list:
  // There must be at least one
  when_clause
  {
    $$.val = []*ast.When{$1.when()}
  }
| when_clause_list when_clause
  {
    $$.val = append($1.whens(), $2.when())
  }

when_clause:
  WHEN a_expr THEN a_expr
  {
    $$.val = &ast.When{Cond: $2.expr(), Val: $4.expr()}
  }

case_default:
  ELSE a_expr
  {
    $$.val = $2.expr()
  }
| /* EMPTY */
  {
    $$.val = ast.Expr(nil)
  }

case_arg:
  a_expr
| /* EMPTY */
  {
    $$.val = ast.Expr(nil)
  }

array_subscript:
  '[' a_expr ']'
  {
    $$.val = &ast.ArraySubscript{Begin: $2.expr()}
  }
| '[' opt_slice_bound ':' opt_slice_bound ']'
  {
    $$.val = &ast.ArraySubscript{Begin: $2.expr(), End: $4.expr(), Slice: true}
  }

opt_slice_bound:
  a_expr
| /*EMPTY*/
  {
    $$.val = ast.Expr(nil)
  }

array_subscripts:
  array_subscript
  {
    $$.val = ast.ArraySubscripts{$1.arraySubscript()}
  }
| array_subscripts array_subscript
  {
    $$.val = append($1.arraySubscripts(), $2.arraySubscript())
  }

opt_asymmetric:
  ASYMMETRIC {}
| /* EMPTY */ {}

target_list:
  target_elem
  {
    $$.val = ast.SelectExprs{$1.selExpr()}
  }
| target_list ',' target_elem
  {
    $$.val = append($1.selExprs(), $3.selExpr())
  }

target_elem:
  a_expr AS target_name
  {
    $$.val = ast.SelectExpr{Expr: $1.expr(), As: ast.UnrestrictedName($3)}
  }
  // We support omitting AS only for column labels that aren't any known
  // keyword. There is an ambiguity against postfix operators: is "a ! b" an
  // infix expression, or a postfix expression and a column label?  We prefer
  // to resolve this as an infix expression, which we accomplish by assigning
  // IDENT a precedence higher than POSTFIXOP.
| a_expr IDENT
  {
    $$.val = ast.SelectExpr{Expr: $1.expr(), As: ast.UnrestrictedName($2)}
  }
| a_expr
  {
    $$.val = ast.SelectExpr{Expr: $1.expr()}
  }
| '*'
  {
    $$.val = ast.StarSelectExpr()
  }

// Names and constants.

table_index_name_list:
  table_index_name
  {
    $$.val = ast.TableIndexNames{$1.newTableIndexName()}
  }
| table_index_name_list ',' table_index_name
  {
    $$.val = append($1.newTableIndexNames(), $3.newTableIndexName())
  }

table_pattern_list:
  table_pattern
  {
    $$.val = ast.TablePatterns{$1.unresolvedName()}
  }
| table_pattern_list ',' table_pattern
  {
    $$.val = append($1.tablePatterns(), $3.unresolvedName())
  }

// An index can be specified in a few different ways:
//
//   - with explicit table name:
//       <table>@<index>
//       <schema>.<table>@<index>
//       <catalog/db>.<table>@<index>
//       <catalog/db>.<schema>.<table>@<index>
//
//   - without explicit table name:
//       <index>
//       <schema>.<index>
//       <catalog/db>.<index>
//       <catalog/db>.<schema>.<index>
table_index_name:
  table_name '@' index_name
  {
    name := $1.unresolvedObjectName().ToTableName()
    $$.val = ast.TableIndexName{
       Table: name,
       Index: ast.UnrestrictedName($3),
    }
  }
| standalone_index_name
  {
    // Treat it as a table name, then pluck out the ObjectName.
    name := $1.unresolvedObjectName().ToTableName()
    indexName := ast.UnrestrictedName(name.ObjectName)
    name.ObjectName = ""
    $$.val = ast.TableIndexName{
        Table: name,
        Index: indexName,
    }
  }

// table_pattern selects zero or more tables using a wildcard.
// Accepted patterns:
// - Patterns accepted by db_object_name
//   <table>
//   <schema>.<table>
//   <catalog/db>.<schema>.<table>
// - Wildcards:
//   <db/catalog>.<schema>.*
//   <schema>.*
//   *
table_pattern:
  simple_db_object_name
  {
     $$.val = $1.unresolvedObjectName().ToUnresolvedName()
  }
| complex_table_pattern

// complex_table_pattern is the part of table_pattern which recognizes
// every pattern not composed of a single identifier.
complex_table_pattern:
  complex_db_object_name
  {
     $$.val = $1.unresolvedObjectName().ToUnresolvedName()
  }
| db_object_name_component '.' unrestricted_name '.' '*'
  {
     $$.val = &ast.UnresolvedName{Star: true, NumParts: 3, Parts: ast.NameParts{"", $3, $1}}
  }
| db_object_name_component '.' '*'
  {
     $$.val = &ast.UnresolvedName{Star: true, NumParts: 2, Parts: ast.NameParts{"", $1}}
  }
| '*'
  {
     $$.val = &ast.UnresolvedName{Star: true, NumParts: 1}
  }

name_list:
  name
  {
    $$.val = ast.NameList{ast.Name($1)}
  }
| name_list ',' name
  {
    $$.val = append($1.nameList(), ast.Name($3))
  }

// Constants
numeric_only:
  signed_iconst
| signed_fconst

signed_iconst:
  ICONST
| only_signed_iconst

only_signed_iconst:
  '+' ICONST
  {
    $$.val = $2.numVal()
  }
| '-' ICONST
  {
    n := $2.numVal()
    n.SetNegative()
    $$.val = n
  }

signed_fconst:
  FCONST
| only_signed_fconst

only_signed_fconst:
  '+' FCONST
  {
    $$.val = $2.numVal()
  }
| '-' FCONST
  {
    n := $2.numVal()
    n.SetNegative()
    $$.val = n
  }

// iconst32 accepts only unsigned integer literals that fit in an int32.
iconst32:
  ICONST
  {
    val, err := $1.numVal().AsInt32()
    if err != nil { return setErr(sqllex, err) }
    $$.val = val
  }

// signed_iconst64 is a variant of signed_iconst which only accepts (signed) integer literals that fit in an int64.
// If you use signed_iconst, you have to call AsInt64(), which returns an error if the value is too big.
// This rule just doesn't match in that case.
signed_iconst64:
  signed_iconst
  {
    val, err := $1.numVal().AsInt64()
    if err != nil { return setErr(sqllex, err) }
    $$.val = val
  }

// iconst64 accepts only unsigned integer literals that fit in an int64.
iconst64:
  ICONST
  {
    val, err := $1.numVal().AsInt64()
    if err != nil { return setErr(sqllex, err) }
    $$.val = val
  }

interval_value:
  INTERVAL SCONST opt_interval_qualifier
  {
    var err error
    var d ast.Datum
    if $3.val == nil {
      d, err = ast.ParseDInterval($2)
    } else {
      d, err = ast.ParseDIntervalWithTypeMetadata($2, $3.intervalTypeMetadata())
    }
    if err != nil { return setErr(sqllex, err) }
    $$.val = d
  }
| INTERVAL '(' iconst32 ')' SCONST
  {
    prec := $3.int32()
    if prec < 0 || prec > 6 {
      sqllex.Error(fmt.Sprintf("precision %d out of range", prec))
      return 1
    }
    d, err := ast.ParseDIntervalWithTypeMetadata($5, types.IntervalTypeMetadata{
      Precision: prec,
      PrecisionIsSet: true,
    })
    if err != nil { return setErr(sqllex, err) }
    $$.val = d
  }

// Name classification hierarchy.
//
// IDENT is the lexeme returned by the lexer for identifiers that match no
// known keyword. In most cases, we can accept certain keywords as names, not
// only IDENTs. We prefer to accept as many such keywords as possible to
// minimize the impact of "reserved words" on programmers. So, we divide names
// into several possible classes. The classification is chosen in part to make
// keywords acceptable as names wherever possible.

// Names specific to syntactic positions.
//
// The non-terminals "name", "unrestricted_name", "non_reserved_word",
// "unreserved_keyword", "non_reserved_word_or_sconst" etc. defined
// below are low-level, structural constructs.
//
// They are separate only because having them all as one rule would
// make the rest of the grammar ambiguous. However, because they are
// separate the question is then raised throughout the rest of the
// grammar: which of the name non-terminals should one use when
// defining a grammar rule?  Is an index a "name" or
// "unrestricted_name"? A partition? What about an index option?
//
// To make the decision easier, this section of the grammar creates
// meaningful, purpose-specific aliases to the non-terminals. These
// both make it easier to decide "which one should I use in this
// context" and also improves the readability of
// automatically-generated syntax diagrams.

// Note: newlines between non-terminals matter to the doc generator.

collation_name:        unrestricted_name

partition_name:        unrestricted_name

index_name:            unrestricted_name

opt_index_name:        opt_name

zone_name:             unrestricted_name

target_name:           unrestricted_name

constraint_name:       name

database_name:         name

column_name:           name

family_name:           name

opt_family_name:       opt_name

table_alias_name:      name

statistics_name:       name

window_name:           name

view_name:             table_name

type_name:             db_object_name

sequence_name:         db_object_name

schema_name:           name

table_name:            db_object_name

standalone_index_name: db_object_name

explain_option_name:   non_reserved_word

cursor_name:           name

// Names for column references.
// Accepted patterns:
// <colname>
// <table>.<colname>
// <schema>.<table>.<colname>
// <catalog/db>.<schema>.<table>.<colname>
//
// Note: the rule for accessing compound types, if those are ever
// supported, is not to be handled here. The syntax `a.b.c.d....y.z`
// in `select a.b.c.d from t` *always* designates a column `z` in a
// table `y`, regardless of the meaning of what's before.
column_path:
  name
  {
      $$.val = &ast.UnresolvedName{NumParts:1, Parts: ast.NameParts{$1}}
  }
| prefixed_column_path

prefixed_column_path:
  db_object_name_component '.' unrestricted_name
  {
      $$.val = &ast.UnresolvedName{NumParts:2, Parts: ast.NameParts{$3,$1}}
  }
| db_object_name_component '.' unrestricted_name '.' unrestricted_name
  {
      $$.val = &ast.UnresolvedName{NumParts:3, Parts: ast.NameParts{$5,$3,$1}}
  }
| db_object_name_component '.' unrestricted_name '.' unrestricted_name '.' unrestricted_name
  {
      $$.val = &ast.UnresolvedName{NumParts:4, Parts: ast.NameParts{$7,$5,$3,$1}}
  }

// Names for column references and wildcards.
// Accepted patterns:
// - those from column_path
// - <table>.*
// - <schema>.<table>.*
// - <catalog/db>.<schema>.<table>.*
// The single unqualified star is handled separately by target_elem.
column_path_with_star:
  column_path
| db_object_name_component '.' unrestricted_name '.' unrestricted_name '.' '*'
  {
    $$.val = &ast.UnresolvedName{Star:true, NumParts:4, Parts: ast.NameParts{"",$5,$3,$1}}
  }
| db_object_name_component '.' unrestricted_name '.' '*'
  {
    $$.val = &ast.UnresolvedName{Star:true, NumParts:3, Parts: ast.NameParts{"",$3,$1}}
  }
| db_object_name_component '.' '*'
  {
    $$.val = &ast.UnresolvedName{Star:true, NumParts:2, Parts: ast.NameParts{"",$1}}
  }

// Names for functions.
// The production for a qualified func_name has to exactly match the production
// for a column_path, because we cannot tell which we are parsing until
// we see what comes after it ('(' or SCONST for a func_name, anything else for
// a name).
// However we cannot use column_path directly, because for a single function name
// we allow more possible tokens than a simple column name.
func_name:
  type_function_name
  {
    $$.val = &ast.UnresolvedName{NumParts:1, Parts: ast.NameParts{$1}}
  }
| prefixed_column_path

// func_name_no_crdb_extra is the same rule as func_name, but does not
// contain some CRDB specific keywords like FAMILY.
func_name_no_crdb_extra:
  type_function_name_no_crdb_extra
  {
    $$.val = &ast.UnresolvedName{NumParts:1, Parts: ast.NameParts{$1}}
  }
| prefixed_column_path

// Names for database objects (tables, sequences, views, stored functions).
// Accepted patterns:
// <table>
// <schema>.<table>
// <catalog/db>.<schema>.<table>
db_object_name:
  simple_db_object_name
| complex_db_object_name

// simple_db_object_name is the part of db_object_name that recognizes
// simple identifiers.
simple_db_object_name:
  db_object_name_component
  {
    aIdx := sqllex.(*lexer).NewAnnotation()
    res, err := ast.NewUnresolvedObjectName(1, [3]string{$1}, aIdx)
    if err != nil { return setErr(sqllex, err) }
    $$.val = res
  }

// complex_db_object_name is the part of db_object_name that recognizes
// composite names (not simple identifiers).
// It is split away from db_object_name in order to enable the definition
// of table_pattern.
complex_db_object_name:
  db_object_name_component '.' unrestricted_name
  {
    aIdx := sqllex.(*lexer).NewAnnotation()
    res, err := ast.NewUnresolvedObjectName(2, [3]string{$3, $1}, aIdx)
    if err != nil { return setErr(sqllex, err) }
    $$.val = res
  }
| db_object_name_component '.' unrestricted_name '.' unrestricted_name
  {
    aIdx := sqllex.(*lexer).NewAnnotation()
    res, err := ast.NewUnresolvedObjectName(3, [3]string{$5, $3, $1}, aIdx)
    if err != nil { return setErr(sqllex, err) }
    $$.val = res
  }

// DB object name component -- this cannot not include any reserved
// keyword because of ambiguity after FROM, but we've been too lax
// with reserved keywords and made INDEX and FAMILY reserved, so we're
// trying to gain them back here.
db_object_name_component:
  name
| type_func_name_crdb_extra_keyword
| cockroachdb_extra_reserved_keyword

// General name --- names that can be column, table, etc names.
name:
  IDENT
| unreserved_keyword
| col_name_keyword

opt_name:
  name
| /* EMPTY */
  {
    $$ = ""
  }

opt_name_parens:
  '(' name ')'
  {
    $$ = $2
  }
| /* EMPTY */
  {
    $$ = ""
  }

// Structural, low-level names

// Non-reserved word and also string literal constants.
non_reserved_word_or_sconst:
  non_reserved_word
| SCONST

// Type/function identifier --- names that can be type or function names.
type_function_name:
  IDENT
| unreserved_keyword
| type_func_name_keyword

// Type/function identifier without CRDB extra reserved keywords.
type_function_name_no_crdb_extra:
  IDENT
| unreserved_keyword
| type_func_name_no_crdb_extra_keyword

// Any not-fully-reserved word --- these names can be, eg, variable names.
non_reserved_word:
  IDENT
| unreserved_keyword
| col_name_keyword
| type_func_name_keyword

// Unrestricted name --- allowable names when there is no ambiguity with even
// reserved keywords, like in "AS" clauses. This presently includes *all*
// Postgres keywords.
unrestricted_name:
  IDENT
| unreserved_keyword
| col_name_keyword
| type_func_name_keyword
| reserved_keyword

// Keyword category lists. Generally, every keyword present in the Postgres
// grammar should appear in exactly one of these lists.
//
// Put a new keyword into the first list that it can go into without causing
// shift or reduce conflicts. The earlier lists define "less reserved"
// categories of keywords.
//
// "Unreserved" keywords --- available for use as any kind of name.
unreserved_keyword:
  ABORT
| ACTION
| ADD
| ADMIN
| AFTER
| AGGREGATE
| ALTER
| ALWAYS
| AT
| ATTRIBUTE
| AUTOMATIC
| AUTHORIZATION
| BACKUP
| BEFORE
| BEGIN
| BUCKET_COUNT
| BUNDLE
| BY
| CACHE
| CANCEL
| CASCADE
| CHANGEFEED
| CLOSE
| CLUSTER
| COLUMNS
| COMMENT
| COMMENTS
| COMMIT
| COMMITTED
| COMPACT
| COMPLETE
| CONFLICT
| CONFIGURATION
| CONFIGURATIONS
| CONFIGURE
| CONSTRAINTS
| CONVERSION
| COPY
| COVERING
| CREATEROLE
| CUBE
| CURRENT
| CYCLE
| DATA
| DATABASE
| DATABASES
| DAY
| DEALLOCATE
| DECLARE
| DELETE
| DEFAULTS
| DEFERRED
| DETACHED
| DISCARD
| DOMAIN
| DOUBLE
| DROP
| ENCODING
| ENCRYPTION_PASSPHRASE
| ENUM
| ESCAPE
| EXCLUDE
| EXCLUDING
| EXECUTE
| EXECUTION
| EXPERIMENTAL
| EXPERIMENTAL_AUDIT
| EXPERIMENTAL_FINGERPRINTS
| EXPERIMENTAL_RELOCATE
| EXPERIMENTAL_REPLICA
| EXPIRATION
| EXPLAIN
| EXPORT
| EXTENSION
| FILES
| FILTER
| FIRST
| FOLLOWING
| FORCE_INDEX
| FUNCTION
| GENERATED
| GEOMETRYCOLLECTION
| GLOBAL
| GRANTS
| GROUPS
| HASH
| HIGH
| HISTOGRAM
| HOUR
| IDENTITY
| IMMEDIATE
| IMPORT
| INCLUDE
| INCLUDING
| INCREMENT
| INCREMENTAL
| INDEXES
| INJECT
| INSERT
| INTERLEAVE
| INVERTED
| ISOLATION
| JOB
| JOBS
| JSON
| KEY
| KEYS
| KV
| LANGUAGE
| LAST
| LC_COLLATE
| LC_CTYPE
| LEASE
| LESS
| LEVEL
| LINESTRING
| LIST
| LOCAL
| LOCKED
| LOGIN
| LOOKUP
| LOW
| MATCH
| MATERIALIZED
| MAXVALUE
| MERGE
| MINUTE
| MINVALUE
| MULTILINESTRING
| MULTIPOINT
| MULTIPOLYGON
| MONTH
| NAMES
| NAN
| NEVER
| NEXT
| NO
| NORMAL
| NO_INDEX_JOIN
| NOCREATEROLE
| NOLOGIN
| NOWAIT
| NULLS
| IGNORE_FOREIGN_KEYS
| OF
| OFF
| OIDS
| OPERATOR
| OPT
| OPTION
| OPTIONS
| ORDINALITY
| OTHERS
| OVER
| OWNED
| OWNER
| PARENT
| PARTIAL
| PARTITION
| PARTITIONS
| PASSWORD
| PAUSE
| PHYSICAL
| PLAN
| PLANS
| PRECEDING
| PREPARE
| PRESERVE
| PRIORITY
| PUBLIC
| PUBLICATION
| QUERIES
| QUERY
| RANGE
| RANGES
| READ
| RECURRING
| RECURSIVE
| REF
| REINDEX
| RELEASE
| RENAME
| REPEATABLE
| REPLACE
| RESET
| RESTORE
| RESTRICT
| RESUME
| RETRY
| REVISION_HISTORY
| REVOKE
| ROLE
| ROLES
| ROLLBACK
| ROLLUP
| ROWS
| RULE
| SCHEDULE
| SETTING
| SETTINGS
| STATUS
| SAVEPOINT
| SCATTER
| SCHEMA
| SCHEMAS
| SCRUB
| SEARCH
| SECOND
| SERIALIZABLE
| SEQUENCE
| SEQUENCES
| SERVER
| SESSION
| SESSIONS
| SET
| SHARE
| SHOW
| SIMPLE
| SKIP
| SNAPSHOT
| SPLIT
| SQL
| START
| STATISTICS
| STDIN
| STORAGE
| STORE
| STORED
| STORING
| STRICT
| SUBSCRIPTION
| SYNTAX
| SYSTEM
| TABLES
| TEMP
| TEMPLATE
| TEMPORARY
| TENANT
| TESTING_RELOCATE
| TEXT
| TIES
| TRACE
| TRANSACTION
| TRIGGER
| TRUNCATE
| TRUSTED
| TYPE
| THROTTLING
| UNBOUNDED
| UNCOMMITTED
| UNKNOWN
| UNLOGGED
| UNSPLIT
| UNTIL
| UPDATE
| UPSERT
| USE
| USERS
| VALID
| VALIDATE
| VALUE
| VARYING
| VIEW
| WITHIN
| WITHOUT
| WRITE
| YEAR
| ZONE

// Column identifier --- keywords that can be column, table, etc names.
//
// Many of these keywords will in fact be recognized as type or function names
// too; but they have special productions for the purpose, and so can't be
// treated as "generic" type or function names.
//
// The type names appearing here are not usable as function names because they
// can be followed by '(' in typename productions, which looks too much like a
// function call for an LR(1) parser.
col_name_keyword:
  ANNOTATE_TYPE
| BETWEEN
| BIGINT
| BIT
| BOOLEAN
| CHAR
| CHARACTER
| CHARACTERISTICS
| COALESCE
| DEC
| DECIMAL
| EXISTS
| EXTRACT
| EXTRACT_DURATION
| FLOAT
| GEOGRAPHY
| GEOMETRY
| GREATEST
| GROUPING
| IF
| IFERROR
| IFNULL
| INT
| INTEGER
| INTERVAL
| ISERROR
| LEAST
| NULLIF
| NUMERIC
| OUT
| OVERLAY
| POINT
| POLYGON
| POSITION
| PRECISION
| REAL
| ROW
| SMALLINT
| STRING
| SUBSTRING
| TIME
| TIMETZ
| TIMESTAMP
| TIMESTAMPTZ
| TREAT
| TRIM
| VALUES
| VARBIT
| VARCHAR
| VIRTUAL
| WORK

// type_func_name_keyword contains both the standard set of
// type_func_name_keyword's along with the set of CRDB extensions.
type_func_name_keyword:
  type_func_name_no_crdb_extra_keyword
| type_func_name_crdb_extra_keyword

// Type/function identifier --- keywords that can be type or function names.
//
// Most of these are keywords that are used as operators in expressions; in
// general such keywords can't be column names because they would be ambiguous
// with variables, but they are unambiguous as function identifiers.
//
// Do not include POSITION, SUBSTRING, etc here since they have explicit
// productions in a_expr to support the goofy SQL9x argument syntax.
// - thomas 2000-11-28
//
// *** DO NOT ADD COCKROACHDB-SPECIFIC KEYWORDS HERE ***
//
// See type_func_name_crdb_extra_keyword below.
type_func_name_no_crdb_extra_keyword:
  COLLATION
| CROSS
| FULL
| INNER
| ILIKE
| IS
| ISNULL
| JOIN
| LEFT
| LIKE
| NATURAL
| NONE
| NOTNULL
| OUTER
| OVERLAPS
| RIGHT
| SIMILAR

// CockroachDB-specific keywords that can be used in type/function
// identifiers.
//
// *** REFRAIN FROM ADDING KEYWORDS HERE ***
//
// Adding keywords here creates non-resolvable incompatibilities with
// postgres clients.
//
type_func_name_crdb_extra_keyword:
  FAMILY

// Reserved keyword --- these keywords are usable only as a unrestricted_name.
//
// Keywords appear here if they could not be distinguished from variable, type,
// or function names in some contexts.
//
// *** NEVER ADD KEYWORDS HERE ***
//
// See cockroachdb_extra_reserved_keyword below.
//
reserved_keyword:
  ALL
| ANALYSE
| ANALYZE
| AND
| ANY
| ARRAY
| AS
| ASC
| ASYMMETRIC
| BOTH
| CASE
| CAST
| CHECK
| COLLATE
| COLUMN
| CONCURRENTLY
| CONSTRAINT
| CREATE
| CURRENT_CATALOG
| CURRENT_DATE
| CURRENT_ROLE
| CURRENT_SCHEMA
| CURRENT_TIME
| CURRENT_TIMESTAMP
| CURRENT_USER
| DEFAULT
| DEFERRABLE
| DESC
| DISTINCT
| DO
| ELSE
| END
| EXCEPT
| FALSE
| FETCH
| FOR
| FOREIGN
| FROM
| GRANT
| GROUP
| HAVING
| IN
| INITIALLY
| INTERSECT
| INTO
| LATERAL
| LEADING
| LIMIT
| LOCALTIME
| LOCALTIMESTAMP
| NOT
| NULL
| OFFSET
| ON
| ONLY
| OR
| ORDER
| PLACING
| PRIMARY
| REFERENCES
| RETURNING
| SELECT
| SESSION_USER
| SOME
| SYMMETRIC
| TABLE
| THEN
| TO
| TRAILING
| TRUE
| UNION
| UNIQUE
| USER
| USING
| VARIADIC
| WHEN
| WHERE
| WINDOW
| WITH
| cockroachdb_extra_reserved_keyword

// Reserved keywords in CockroachDB, in addition to those reserved in
// PostgreSQL.
//
// *** REFRAIN FROM ADDING KEYWORDS HERE ***
//
// Adding keywords here creates non-resolvable incompatibilities with
// postgres clients.
cockroachdb_extra_reserved_keyword:
  INDEX
| NOTHING

%%
