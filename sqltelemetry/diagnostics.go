// Copyright 2019 The Cockroach Authors.
//
// Use of this software is governed by the Business Source License
// included in the file licenses/BSL.txt.
//
// As of the Change Date specified in that file, in accordance with
// the Business Source License, use of this software will be governed
// by the Apache License, Version 2.0, included in the file
// licenses/APL.txt.

package sqltelemetry

import "github.com/ruiaylin/pgparser/telemetry"

// StatementDiagnosticsCollectedCounter is to be incremented whenever a query is
// run with diagnostic collection (as a result of a user request through the
// UI). This does not include diagnostics collected through
// EXPLAIN ANALYZE (DEBUG), which has a separate counter.
// distributed across multiple nodes.
var StatementDiagnosticsCollectedCounter = telemetry.GetCounterOnce("sql.diagnostics.collected")
