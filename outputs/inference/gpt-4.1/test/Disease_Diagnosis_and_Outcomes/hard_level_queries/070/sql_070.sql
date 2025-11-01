WITH dvt_icd_codes AS (
  -- DVT ICD-9 and ICD-10 codes
  SELECT '45340' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '45341', 9 UNION ALL
  SELECT '45342', 9 UNION ALL
  SELECT '4538', 9 UNION ALL
  SELECT '4539', 9 UNION ALL
  SELECT 'I82401', 10 UNION ALL
  SELECT 'I82402', 10 UNION ALL
  SELECT 'I82409', 10 UNION ALL
  SELECT 'I82410', 10 UNION ALL
  SELECT 'I82411', 10 UNION ALL
  SELECT 'I82419', 10 UNION ALL
  SELECT 'I82420', 10 UNION ALL
  SELECT 'I82421', 10 UNION ALL
  SELECT 'I82429', 10 UNION ALL
  SELECT 'I82490', 10 UNION ALL
  SELECT 'I82491', 10 UNION ALL
  SELECT 'I82499', 10
),
major_complication_icd_codes AS (
  -- PE, major bleeding, stroke, MI, sepsis (ICD-9 and ICD-10, partial list)
  SELECT '41519' AS icd_code, 9 AS icd_version UNION ALL -- PE
  SELECT 'I2690', 10 UNION ALL -- PE
  SELECT 'I2693', 10 UNION ALL -- PE
  SELECT '430', 9 UNION ALL -- Intracranial hemorrhage
  SELECT '431', 9 UNION ALL
  SELECT '4321', 9 UNION ALL
  SELECT 'I601', 10 UNION ALL
  SELECT 'I602', 10 UNION ALL
  SELECT 'I603', 10 UNION ALL
  SELECT 'I604', 10 UNION ALL
  SELECT 'I605', 10 UNION ALL
  SELECT 'I606', 10 UNION ALL
  SELECT 'I607', 10 UNION ALL
  SELECT 'I608', 10 UNION ALL
  SELECT 'I609', 10 UNION ALL
  SELECT 'I63', 10 UNION ALL -- Ischemic stroke
  SELECT 'I21', 10 UNION ALL -- MI
  SELECT '410', 9 UNION ALL -- MI
  SELECT '99591', 9 UNION ALL -- Sepsis
  SELECT '99592', 9 UNION ALL -- Severe sepsis
  SELECT 'A419', 10 UNION ALL -- Sepsis
  SELECT 'R6520', 10 UNION ALL -- Severe sepsis
  SELECT 'R6521', 10
),
-- Step 1: Get all admissions for females 59-69 with DVT
dvt_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    pat.gender,
    pat.anchor_age,
    pat.dod
  FROM physionet-data.mimiciv_3_1_hosp.admissions adm
  JOIN physionet-data.mimiciv_3_1_hosp.patients pat
    ON adm.subject_id = pat.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
    ON adm.hadm_id = diag.hadm_id
  JOIN dvt_icd_codes dvt
    ON diag.icd_code = dvt.icd_code AND diag.icd_version = dvt.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 59 AND 69
),
-- Step 2: Calculate Charlson Comorbidity Index (CCI) per admission
cci_map AS (
  -- Map ICD codes to CCI weights (simplified, partial mapping)
  SELECT 'I10' AS icd_code, 10 AS icd_version, 1 AS cci_weight UNION ALL -- Hypertension
  SELECT 'I25' , 10, 1 UNION ALL -- CAD
  SELECT 'I50' , 10, 1 UNION ALL -- CHF
  SELECT 'I63' , 10, 1 UNION ALL -- Stroke
  SELECT 'E119', 10, 1 UNION ALL -- Diabetes
  SELECT 'E112', 10, 2 UNION ALL -- Diabetes with complications
  SELECT 'C34' , 10, 2 UNION ALL -- Cancer
  SELECT 'C90' , 10, 2 UNION ALL -- Cancer
  SELECT 'B20' , 10, 6 UNION ALL -- AIDS
  SELECT 'N18' , 10, 2 UNION ALL -- CKD
  SELECT 'J44' , 10, 1 UNION ALL -- COPD
  SELECT 'I48' , 10, 1 UNION ALL -- AFib
  SELECT '4280', 9, 1 UNION ALL -- CHF
  SELECT '25000', 9, 1 UNION ALL -- Diabetes
  SELECT '25002', 9, 2 UNION ALL -- Diabetes with complications
  SELECT '585', 9, 2 UNION ALL -- CKD
  SELECT '49121', 9, 1 UNION ALL -- COPD
  SELECT '41401', 9, 1 UNION ALL -- CAD
  SELECT 'V420', 9, 2 UNION ALL -- Cancer
  SELECT '042', 9, 6 -- AIDS
),
cci_per_admission AS (
  SELECT
    diag.hadm_id,
    SUM(cci_map.cci_weight) AS cci
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
  JOIN cci_map
    ON diag.icd_code = cci_map.icd_code AND diag.icd_version = cci_map.icd_version
  GROUP BY diag.hadm_id
),
-- Step 3: Merge DVT admissions with CCI
dvt_admissions_with_cci AS (
  SELECT
    dvt.*,
    IFNULL(cci_per_admission.cci, 0) AS cci
  FROM dvt_admissions dvt
  LEFT JOIN cci_per_admission
    ON dvt.hadm_id = cci_per_admission.hadm_id
),
-- Step 4: Calculate 75th percentile CCI threshold
cci_percentiles AS (
  SELECT
    APPROX_QUANTILES(cci, 4) AS cci_quartiles
  FROM dvt_admissions_with_cci
),
cci_75th AS (
  SELECT cci_quartiles[OFFSET(3)] AS cci_75th
  FROM cci_percentiles
),
-- Step 5: Filter cohort to those above 75th percentile
final_cohort AS (
  SELECT
    dvt.*
  FROM dvt_admissions_with_cci dvt
  CROSS JOIN cci_75th
  WHERE dvt.cci > cci_75th.cci_75th
),
-- Step 6: Major complication flag per admission
major_complications AS (
  SELECT
    diag.hadm_id,
    1 AS has_major_complication
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
  JOIN major_complication_icd_codes comp
    ON diag.icd_code = comp.icd_code AND diag.icd_version = comp.icd_version
  GROUP BY diag.hadm_id
),
-- Step 7: Survival calculations
survival AS (
  SELECT
    fc.hadm_id,
    fc.subject_id,
    fc.admittime,
    fc.deathtime,
    fc.dod,
    -- Use earliest death time (admissions.deathtime or patients.dod)
    CASE
      WHEN fc.deathtime IS NOT NULL AND fc.dod IS NOT NULL THEN LEAST(fc.deathtime, fc.dod)
      WHEN fc.deathtime IS NOT NULL THEN fc.deathtime
      WHEN fc.dod IS NOT NULL THEN fc.dod
      ELSE NULL
    END AS death_time
  FROM final_cohort fc
),
-- Step 8: Composite risk score quartiles for cohort
cohort_cci_quartiles AS (
  SELECT
    APPROX_QUANTILES(cci, 4) AS cci_quartiles
  FROM final_cohort
),
-- Step 9: Extract quartiles as scalar fields
quartiles_extracted AS (
  SELECT
    cci_quartiles[OFFSET(1)] AS cci_25th_percentile,
    cci_quartiles[OFFSET(2)] AS cci_50th_percentile,
    cci_quartiles[OFFSET(3)] AS cci_75th_percentile,
    cci_quartiles[OFFSET(4)] AS cci_100th_percentile
  FROM cohort_cci_quartiles
)
-- Final output
SELECT
  COUNT(DISTINCT fc.hadm_id) AS cohort_size,
  -- 30-day mortality: died within 30 days of admission
  SUM(
    CASE
      WHEN s.death_time IS NOT NULL AND DATETIME_DIFF(s.death_time, s.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END
  ) / COUNT(DISTINCT fc.hadm_id) AS thirty_day_mortality_rate,
  -- Major complication rate
  SUM(
    CASE
      WHEN mc.has_major_complication = 1 THEN 1
      ELSE 0
    END
  ) / COUNT(DISTINCT fc.hadm_id) AS major_complication_rate,
  -- Median survival for decedents
  APPROX_QUANTILES(
    CASE
      WHEN s.death_time IS NOT NULL THEN DATETIME_DIFF(s.death_time, s.admittime, DAY)
      ELSE NULL
    END,
    2
  )[OFFSET(1)] AS median_survival_days_for_decedents,
  -- Composite risk score quartiles
  qe.cci_25th_percentile,
  qe.cci_50th_percentile,
  qe.cci_75th_percentile,
  qe.cci_100th_percentile
FROM final_cohort fc
LEFT JOIN major_complications mc
  ON fc.hadm_id = mc.hadm_id
LEFT JOIN survival s
  ON fc.hadm_id = s.hadm_id
CROSS JOIN quartiles_extracted qe;