# Steepfile for type checking

target :lib do
  signature "sig"

  check "lib"

  # Standard library
  library "json"
  library "base64"
  library "fileutils"
  library "uri"
  library "net-http"

  # Configure diagnostic severity
  # Start with lenient settings and tighten over time
  # Using :hint for issues that don't block CI, :warning for informational
  configure_code_diagnostics do |hash|
    # Ignore common Ruby patterns that are hard to type
    hash[Steep::Diagnostic::Ruby::UnannotatedEmptyCollection] = :hint

    # Gradual typing: treat missing methods and type mismatches as hints
    # These can be tightened to :warning or :error as type coverage improves
    hash[Steep::Diagnostic::Ruby::UnknownConstant] = :hint
    hash[Steep::Diagnostic::Ruby::NoMethod] = :hint
    hash[Steep::Diagnostic::Ruby::UnresolvedOverloading] = :hint
    hash[Steep::Diagnostic::Ruby::IncompatibleAssignment] = :hint
    hash[Steep::Diagnostic::Ruby::ArgumentTypeMismatch] = :hint
    hash[Steep::Diagnostic::Ruby::ReturnTypeMismatch] = :hint
    hash[Steep::Diagnostic::Ruby::BlockTypeMismatch] = :hint
    hash[Steep::Diagnostic::Ruby::BreakTypeMismatch] = :hint
    hash[Steep::Diagnostic::Ruby::ImplicitBreakValueMismatch] = :hint
    hash[Steep::Diagnostic::Ruby::UnexpectedBlockGiven] = :hint
    hash[Steep::Diagnostic::Ruby::UnexpectedPositionalArgument] = :hint
  end
end
