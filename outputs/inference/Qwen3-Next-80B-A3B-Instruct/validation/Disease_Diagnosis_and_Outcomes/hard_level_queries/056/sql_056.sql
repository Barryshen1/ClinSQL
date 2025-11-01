WITH itemid for risk scores — but these are not consistently captured...`

This line was not a valid SQL statement — it was a comment mixed with non-SQL explanatory text, and the parser encountered `FOR` after `itemid`, which is not valid BigQuery syntax.

Additionally, the SQL contained multiple syntax errors:
1. **Invalid dataset references**: `physionet-data.mimiciv_3_1_hosp` is not valid BigQuery syntax. In BigQuery, dataset names must be quoted if they contain hyphens. The correct format is `physionet-data.mimiciv_3_1_hosp` → must be written as `` `physionet-data.mimiciv_3_1_hosp` `` (backticks).
2. **Incomplete CTE**: The `general_with_complications` CTE was cut off mid-statement (`AS has_major_comp;`), causing a syntax error.
3. **Misuse of comments**: Inline comments with non-SQL text were left in the query body — these must be removed or properly commented out with `--` only.
4. **Logic issue**: The septic shock condition was being counted as one of the 15+ diagnoses, which is correct — but the `diagnoses_icd` join was filtering only for `R65.21`, which would exclude other diagnoses. We need to find admissions with *at least one* `R65.21` and *more than 15 total diagnoses*.

Fixes applied:
- Enclosed all dataset names in backticks: `` `physionet-data.mimiciv_3_1_hosp` ``
- Removed all non-SQL explanatory text from the query body.
- Fixed the malformed CTE `general_with_complications` — completed the statement.
- Corrected the septic shock cohort logic: use `EXISTS` or `JOIN` to ensure the admission has at least one `R65.21` diagnosis, then count total diagnoses (>15) from all ICD codes in that admission.
- Used `COUNT(*)` over `diagnoses_icd` grouped by `hadm_id` to count total diagnoses per admission.
- Added 90-day mortality logic using `dod` from `patients` — if `dod` is not null and within 90 days of `admittime`.
- Used `icustays.los` for survivor LOS (as ICU stay length is the most consistently available LOS in MIMIC-IV ICU module).
- Computed percentile of 16 diagnoses within the septic shock cohort using `PERCENT_RANK()`.

Final query structure:
1. `septic_shock_cohort`: All male 63–73yo admissions with ≥1 diagnosis of R65.21 and >15 total diagnoses.
2. `complication_flags`: Flag if any complication ICD code present in admission.
3. `cohort_with_complications`: Join complications to septic shock cohort.
4. `survivor_los`: Get ICU LOS for survivors.
5. `general_inpatients`: General inpatient cohort (same age/gender, >15 diagnoses, no septic shock requirement).
6. `general_with_complications`: Add complication flags to general cohort.
7. Final SELECT: Compute means, rates, and percentile for the 68M/16-diagnosis profile.

sql
-- Define septic shock and complication ICD-10 codes
WITH septic_shock_cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    COUNT(di.icd_code) AS diagnosis_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND di.icd_version = 10
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2 
      WHERE di2.hadm_id = a.hadm_id 
        AND di2.icd_code = 'R65.21' 
        AND di2.icd_version = 10
    )
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.anchor_age, p.gender
  HAVING COUNT(di.icd_code) > 15
),
complication_flags AS (
  SELECT DISTINCT
    di.hadm_id,
    CASE WHEN di.icd_code IN ('N17.9', 'J96.00', 'I46.9') THEN 1 ELSE 0 END AS has_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE di.icd_version = 10
    AND di.icd_code IN ('N17.9', 'J96.00', 'I46.9')
),
cohort_with_complications AS (
  SELECT 
    s.*,
    MAX(c.has_complication) AS has_major_complication
  FROM septic_shock_cohort s
  LEFT JOIN complication_flags c ON s.hadm_id = c.hadm_id
  GROUP BY s.subject_id, s.hadm_id, s.admittime, s.dischtime, s.hospital_expire_flag, s.anchor_age, s.gender, s.diagnosis_count
),
survivor_los AS (
  SELECT 
    c.*,
    i.los AS icu_los
  FROM cohort_with_complications c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON c.hadm_id = i.hadm_id
  WHERE c.hospital_expire_flag = 0
),
general_inpatients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    COUNT(di.icd_code) AS diagnosis_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND di.icd_version = 10
  GROUP BY a.subject_id, a.hadm_id, a.hospital_expire_flag, p.anchor_age, p.gender
  HAVING COUNT(di.icd_code) > 15
),
general_with_complications AS (
  SELECT 
    g.*,
    MAX(c.has_complication) AS has_major_complication
  FROM general_inpatients g
  LEFT JOIN complication_flags c ON g.hadm_id = c.hadm_id
  GROUP BY g.subject_id, g.hadm_id, g.hospital_expire_flag, g.anchor_age, g.gender, g.diagnosis_count
),
percentile_calc AS (
  SELECT 
    diagnosis_count,
    PERCENT_RANK() OVER (ORDER BY diagnosis_count) AS percentile_rank
  FROM septic_shock_cohort
  WHERE diagnosis_count = 16
)
SELECT
  -- Septic shock cohort metrics
  AVG(CAST(c.hospital_expire_flag AS FLOAT64)) AS mean_hospital_mortality,
  AVG(CASE WHEN p.dod IS NOT NULL AND p.dod <= DATE_ADD(c.admittime, INTERVAL 90 DAY) THEN 1 ELSE 0 END) AS mean_90day_mortality,
  AVG(c.has_major_complication) AS mean_major_complication_rate,
  AVG(s.icu_los) AS mean_survivor_icu_los,
  -- General inpatient comparison
  AVG(CAST(g.has_major_complication AS FLOAT64)) AS general_major_complication_rate,
  AVG(gi.icu_los) AS general_survivor_icu_los,
  -- Percentile for 68M with 16 diagnoses
  pc.percentile_rank AS percentile_of_16_diagnoses
FROM cohort_with_complications c
LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON c.subject_id = p.subject_id
LEFT JOIN survivor_los s ON c.hadm_id = s.hadm_id
CROSS JOIN (
  SELECT AVG(CAST(has_major_complication AS FLOAT64)) AS icu_los
  FROM general_with_complications g2
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON g2.hadm;