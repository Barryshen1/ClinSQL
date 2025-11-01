WITH
-- 1. Identify sepsis and septic shock ICD codes
sepsis_icd AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-10 sepsis codes
    (icd_version = 10 AND (
      REGEXP_CONTAINS(icd_code, r'^A41') OR
      icd_code IN ('R652', 'R6521', 'R6520', 'R6522')
    ))
    -- ICD-9 sepsis codes
    OR (icd_version = 9 AND (
      REGEXP_CONTAINS(icd_code, r'^038') OR
      icd_code IN ('99591', '99592')
    ))
),
septic_shock_icd AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-10 septic shock codes
    (icd_version = 10 AND icd_code IN ('R6521'))
    -- ICD-9 septic shock codes
    OR (icd_version = 9 AND icd_code IN ('78552'))
),
-- 2. Get all admissions for females age 53-63
base_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
),
-- 3. Assign sepsis/septic shock group per admission
admission_sepsis_group AS (
  SELECT
    b.*,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN septic_shock_icd ssi
          ON d.icd_code = ssi.icd_code AND d.icd_version = ssi.icd_version
        WHERE d.subject_id = b.subject_id AND d.hadm_id = b.hadm_id
      ) THEN 'septic shock'
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN sepsis_icd si
          ON d.icd_code = si.icd_code AND d.icd_version = si.icd_version
        WHERE d.subject_id = b.subject_id AND d.hadm_id = b.hadm_id
      ) THEN 'sepsis'
      ELSE NULL
    END AS sepsis_group
  FROM base_cohort b
),
-- 4. Get first ICU stay per admission
first_icu_stay AS (
  SELECT
    subject_id,
    hadm_id,
    MIN(stay_id) AS stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY subject_id, hadm_id
),
icu_stay_details AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN first_icu_stay f
    ON i.subject_id = f.subject_id AND i.hadm_id = f.hadm_id AND i.stay_id = f.stay_id
),
-- 5. Merge all together and assign LOS group
final_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.anchor_age,
    a.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.sepsis_group,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.los,
    CASE
      WHEN i.los <= 7 THEN 'LOS ≤7'
      WHEN i.los > 7 THEN 'LOS >7'
      ELSE NULL
    END AS los_group
  FROM admission_sepsis_group a
  JOIN icu_stay_details i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE a.sepsis_group IS NOT NULL AND (i.los <= 7 OR i.los > 7)
),
-- 6. Aggregate stats per group
group_stats AS (
  SELECT
    sepsis_group,
    los_group,
    COUNT(*) AS N,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) * 100 AS mortality_pct,
    -- Median time-to-death for non-survivors (in days)
    APPROX_QUANTILES(
      DATE_DIFF(deathtime, icu_intime, DAY),
      2
    )[OFFSET(1)] AS median_time_to_death_days
  FROM final_cohort
  GROUP BY sepsis_group, los_group
),
-- 7. Pivot for mortality difference calculations
pivot_stats AS (
  SELECT
    sepsis_group,
    MAX(CASE WHEN los_group = 'LOS ≤7' THEN N END) AS N_los_le7,
    MAX(CASE WHEN los_group = 'LOS >7' THEN N END) AS N_los_gt7,
    MAX(CASE WHEN los_group = 'LOS ≤7' THEN deaths END) AS deaths_los_le7,
    MAX(CASE WHEN los_group = 'LOS >7' THEN deaths END) AS deaths_los_gt7,
    MAX(CASE WHEN los_group = 'LOS ≤7' THEN mortality_pct END) AS mortality_pct_los_le7,
    MAX(CASE WHEN los_group = 'LOS >7' THEN mortality_pct END) AS mortality_pct_los_gt7,
    MAX(CASE WHEN los_group = 'LOS ≤7' THEN median_time_to_death_days END) AS median_time_to_death_los_le7,
    MAX(CASE WHEN los_group = 'LOS >7' THEN median_time_to_death_days END) AS median_time_to_death_los_gt7
  FROM group_stats
  GROUP BY sepsis_group
)
-- 8. Final output: stats per group and mortality differences
SELECT
  sepsis_group,
  N_los_le7 AS N_LOS_le7,
  N_los_gt7 AS N_LOS_gt7,
  deaths_los_le7 AS deaths_LOS_le7,
  deaths_los_gt7 AS deaths_LOS_gt7,
  ROUND(mortality_pct_los_le7,1) AS mortality_pct_LOS_le7,
  ROUND(mortality_pct_los_gt7,1) AS mortality_pct_LOS_gt7,
  median_time_to_death_los_le7 AS median_time_to_death_LOS_le7,
  median_time_to_death_los_gt7 AS median_time_to_death_LOS_gt7,
  -- Absolute mortality difference
  ROUND(mortality_pct_los_gt7 - mortality_pct_los_le7,1) AS abs_mortality_diff_pct,
  -- Relative mortality difference
  ROUND(SAFE_DIVIDE(mortality_pct_los_gt7 - mortality_pct_los_le7, mortality_pct_los_le7)*100,1) AS rel_mortality_diff_pct
FROM pivot_stats
ORDER BY sepsis_group;