with `LIKE` for case-insensitive matching instead.

Additionally, there is a subtle but critical issue: in the `final_dataset` CTE, the `diagnoses_icd` and `d_icd_diagnoses` joins are performed after grouping, but the `di` table is referenced in the `MAX(CASE ...)` expressions for CKD and diabetes flags. This is logically flawed because the `di` table is joined at the row level, but the grouping is done at the `hadm_id` level — and multiple diagnosis rows per admission may exist. However, since we are using `MAX()` over flags, this is acceptable as long as the join is correct.

But the main error is the use of `ILIKE`. We must replace all instances of `ILIKE` with `LOWER(...) LIKE LOWER(...)` to make it BigQuery-compatible.

Also, note that BigQuery requires fully qualified table names with backticks if they contain hyphens (e.g., `physionet-data.mimiciv_3_1_hosp`). However, in BigQuery, project names with hyphens must be wrapped in backticks. So we must fix all dataset references to use backticks:  
`physionet-data.mimiciv_3_1_hosp` → `` `physionet-data.mimiciv_3_1_hosp` ``  
`physionet-data.mimiciv_3_1_icu` → `` `physionet-data.mimiciv_3_1_icu` ``

This is a requirement in BigQuery for project IDs containing hyphens.

Finally, we must ensure that the `d_icd_diagnoses` joins are correctly scoped. The original query joins `d_icd_diagnoses` in the `heart_failure_admissions` CTE and again in `final_dataset` — this is redundant and inefficient. We can avoid re-joining `d_icd_diagnoses` in `final_dataset` by precomputing the CKD and diabetes flags in the `heart_failure_admissions` CTE, since we already have the `hadm_id` and are joining to `diagnoses_icd` and `d_icd_diagnoses` there.

Better approach: Move the CKD and diabetes flag logic into the `heart_failure_admissions` CTE, so we don’t need to re-join in `final_dataset`. This improves performance and avoids potential ambiguity.

We’ll also fix the `comorbidity_counts` CTE to avoid double-counting or missing diagnoses by ensuring we exclude only heart failure codes (not just the long_title matches, but also the ICD codes).

Let’s restructure:

1. Fix all `ILIKE` → `LOWER(...) LIKE LOWER(...)`
2. Wrap all project/dataset names with hyphens in backticks
3. Precompute CKD and diabetes flags in the first CTE to avoid redundant joins
4. Keep comorbidity logic as-is (it’s correct)
5. Ensure `LEFT JOIN` to `icustays` is on `hadm_id` (correct)

We’ll also note: `d_icd_diagnoses` has both ICD-9 and ICD-10 codes. The original code uses both (e.g., '428' and 'I50'), which is correct.

Final SQL:

sql
WITH heart_failure_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days,
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
    p.anchor_age,
    MAX(CASE WHEN LOWER(di.long_title) LIKE '%chronic kidney%' 
              OR LOWER(di.long_title) LIKE '%ckd%' 
              OR d.icd_code IN ('585', '585.1', '585.2', '585.3', '585.4', '585.5', '585.6', '585.9', 'N18', 'N18.1', 'N18.2', 'N18.3', 'N18.4', 'N18.5', 'N18.6', 'N18.9') 
             THEN 1 ELSE 0 END) AS ckd_flag,
    MAX(CASE WHEN LOWER(di.long_title) LIKE '%diabetes%' 
              OR d.icd_code IN ('250', '250.0', '250.1', '250.2', '250.3', '250.4', '250.5', '250.6', '250.7', '250.8', '250.9', 'E10', 'E11', 'E12', 'E13', 'E14') 
             THEN 1 ELSE 0 END) AS diabetes_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.`patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp`.`admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.`diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.`d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.`icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND (LOWER(di.long_title) LIKE '%heart failure%'
         OR LOWER(di.long_title) LIKE '%congestive heart failure%'
         OR d.icd_code IN ('428', '428.0', '428.1', '428.2', '428.3', '428.4', '428.9',
                           'I50', 'I50.0', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.9'))
  GROUP BY p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, i.stay_id, p.anchor_age
),

comorbidity_counts AS (
  SELECT
    d.hadm_id,
    COUNT(*) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp`.`diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp`.`d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE d.hadm_id IN (SELECT hadm_id FROM heart_failure_admissions)
    AND NOT (LOWER(di.long_title) LIKE '%heart failure%'
             OR LOWER(di.long_title) LIKE '%congestive heart failure%'
             OR d.icd_code IN ('428', '428.0', '428.1', '428.2', '428.3', '428.4', '428.9',
                               'I50', 'I50.0', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.9'))
  GROUP BY d.hadm_id
),

final_dataset AS (
  SELECT
    hfa.icu_status,
    CASE WHEN hfa.los_days < 8 THEN '<8' ELSE '>=8' END AS los_category,
    CASE
      WHEN COALESCE(cc.comorbidity_count, 0) <= 1 THEN '0-1'
      WHEN cc.comorbidity_count = 2 THEN '2'
      WHEN cc.comorbidity_count >= 3 THEN '>=3'
    END AS comorbidity_burden,
    hfa.hospital_expire_flag,
    hfa.los_days,
    hfa.ckd_flag,
    hfa.diabetes_flag
  FROM heart_failure_admissions hfa
  LEFT JOIN comorbidity_counts cc ON hfa.hadm_id = cc.hadm_id
)

SELECT
  icu_status,
  los_category,
  comorbidity_burden,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
  PERCENTILE_CONT(los_days, 0.5) WITHIN GROUP (ORDER BY los_days) AS median_los_days,
  ROUND(100.0 * SUM(ckd_flag) / COUNT(*), 2) AS ckd_prevalence_percent,
  ROUND(100.0 * SUM(diabetes_flag) / COUNT(*;