// Copyright 2017 The Cockroach Authors.
//
// Use of this software is governed by the Business Source License
// included in the file licenses/BSL.txt.
//
// As of the Change Date specified in that file, in accordance with
// the Business Source License, use of this software will be governed
// by the Apache License, Version 2.0, included in the file
// licenses/APL.txt.

package timeutil_test

import (
	"os"
	"testing"

	_ "github.com/ruiaylin/pgparser/utils/log" // for flags
	"github.com/ruiaylin/pgparser/utils/randutil"
)

func TestMain(m *testing.M) {
	randutil.SeedForTests()
	os.Exit(m.Run())
}
