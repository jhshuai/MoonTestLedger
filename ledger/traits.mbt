///|
pub extend CaseKey with @debug.Debug::{to_repr}

///|
pub extend CaseKey with Eq::{equal, not_equal}

///|
pub extend CaseKey with Compare::{compare, op_lt, op_le, op_ge, op_gt}

///|
pub extend CaseKey with Hash::{hash, hash_combine}

///|
pub extend ExpectedReport with @debug.Debug::{to_repr}

///|
pub extend ExpectedReport with Eq::{equal, not_equal}

///|
pub extend RunPlan with @debug.Debug::{to_repr}

///|
pub extend RunPlan with Eq::{equal, not_equal}

///|
pub extend ReportBinding with @debug.Debug::{to_repr}

///|
pub extend ReportBinding with Eq::{equal, not_equal}

///|
pub extend Outcome with @debug.Debug::{to_repr}

///|
pub extend Outcome with Eq::{equal, not_equal}

///|
pub extend ProblemKind with @debug.Debug::{to_repr}

///|
pub extend ProblemKind with Eq::{equal, not_equal}

///|
pub extend Problem with @debug.Debug::{to_repr}

///|
pub extend Problem with Eq::{equal, not_equal}

///|
pub extend ObservedCase with @debug.Debug::{to_repr}

///|
pub extend ObservedCase with Eq::{equal, not_equal}

///|
pub extend ParsedReport with @debug.Debug::{to_repr}

///|
pub extend ParsedReport with Eq::{equal, not_equal}

///|
pub extend Document with @debug.Debug::{to_repr}

///|
pub extend Document with Eq::{equal, not_equal}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
pub extend Diagnostic with Eq::{equal, not_equal}

///|
pub extend InputError with @debug.Debug::{to_repr}

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Verdict with @debug.Debug::{to_repr}

///|
pub extend Verdict with Eq::{equal, not_equal}

///|
pub extend AttemptRecord with @debug.Debug::{to_repr}

///|
pub extend AttemptRecord with Eq::{equal, not_equal}

///|
pub extend CaseSummary with @debug.Debug::{to_repr}

///|
pub extend CaseSummary with Eq::{equal, not_equal}

///|
pub extend MissingCase with @debug.Debug::{to_repr}

///|
pub extend MissingCase with Eq::{equal, not_equal}

///|
pub extend Summary with @debug.Debug::{to_repr}

///|
pub extend Summary with Eq::{equal, not_equal}
