with `WITHIN GROUP`, which is not supported in BigQuery. Replaced with `APPROX_QUANTILES` which returns an array of approximate percentiles. Extracted the 25th, 50th, and 75th percentiles using array offsets (25, 50, 75 for 100 percentiles).
2. **ICD Version**: Added `d.icd_version = 10` to ensure only ICD-10 codes are considered for upper GI bleeding.
3. **Duration Group**: Moved `duration_group` calculation into `procedure_counts` CTE for efficiency and clarity.
4. **Procedure Counting**: Maintained distinct HCPCS code count per admission, filtered to 'Diagnostic' category via `d_hcpcs`.
5. **Ordering**: Kept the explicit ordering of duration groups for consistent output.
6. **Minimal Changes**: Only necessary adjustments made; preserved original logic where valid. Used exact table names and datasets as specified. 

**Note**: `APPROX_QUANTILES` provides approximate results suitable for large datasets. For exact percentiles, consider alternative methods (e.g., subquery with `NTILE`), but this meets the clinical question's requirements efficiently. Anchor age is used as a proxy for age at admission; ensure this aligns with study design.;