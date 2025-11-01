with at least one procedure (indicating surgery).
   - Used `diagnoses_icd` to count distinct ICD-10 codes per admission; required ≥2 diagnoses to proxy for complications (assuming primary diagnosis + at least one complication).

3. **ICU vs Non-ICU**:
   - Left-joined `icustays` to `admissions` to determine ICU status (1 if ICU stay exists, else 0). Converted to text labels ('ICU'/'non-ICU').

4. **LOS Calculation**:
   - Computed LOS in days using `DATE_DIFF(admissions.dischtime, admissions.admittime, DAY)`.
   - Binned LOS as '≤5' or '>5' days.

5. **Comorbidity Bins**:
   - Comorbidity count defined as distinct ICD-10 codes per admission (from `diagnoses_icd`).
   - Binned as '0-1', '2', or '≥3' based on count.

6. **Outcomes**:
   - `N`: Count of admissions per group.
   - `mortality_percent`: Percentage of admissions with `hospital_expire_flag = 1`.
   - `avg_comorbidity_count`: Average distinct ICD-10 codes per admission in the group.

7. **Edge Cases**:
   - Excluded admissions without discharge time to avoid invalid LOS.
   - Used `INNER JOIN` for `comorbidity_counts` and `procedure_counts` to enforce ≥2 diagnoses and ≥1 procedure.
   - Handled ICU status via `LEFT JOIN` to include non-ICU admissions.

8. **Performance**:
   - Used CTEs for modular steps and efficient aggregation.
   - Precomputed counts (`comorbidity_counts`, `procedure_counts`) to avoid repeated subqueries.

**Note**: This query uses a simplified proxy for postoperative complications (≥2 diagnoses per admission). For a more accurate definition, a predefined list of complication ICD-10 codes would be ideal but was omitted due to complexity and lack of a standard list in MIMIC-IV. The comorbidity count uses distinct ICD-10 codes as a proxy; for clinical use, a validated index (e.g., Charlson) would be preferable but requires additional mapping.;