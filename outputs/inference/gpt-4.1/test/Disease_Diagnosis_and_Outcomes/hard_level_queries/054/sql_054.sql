WITH
-- 1. Get PE ICD codes (ICD-9: 4151*, ICD-10: I26*)
pe_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code LIKE '4151%')
     OR (icd_version = 10 AND icd_code LIKE 'I26%')
),

-- 2. Get cardio and neuro complication ICD codes
cardio_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- Acute MI
    (icd_version = 9 AND icd_code LIKE '410%')
    OR (icd_version = 10 AND icd_code LIKE 'I21%')
    -- Arrhythmia
    OR (icd_version = 9 AND icd_code LIKE '427%')
    OR (icd_version = 10 AND icd_code LIKE 'I47%')
    -- Heart failure
    OR (icd_version = 9 AND icd_code LIKE '428%')
    OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
neuro_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- Stroke
    (icd_version = 9 AND icd_code LIKE '434%')
    OR (icd_version = 10 AND icd_code LIKE 'I63%')
    -- TIA
    OR (icd_version = 9 AND icd_code LIKE '435%')
    OR (icd_version = 10 AND icd_code LIKE 'G45%')
    -- Seizure
    OR (icd_version = 9 AND icd_code LIKE '345%')
    OR (icd_version = 10 AND icd_code LIKE 'G40%')
),

-- 3. Map ICD codes to Charlson Comorbidity Index weights
cci_map AS (
  SELECT 'MI' AS comorb, 1 AS weight, '410%' AS icd9, 'I21%' AS icd10 UNION ALL
  SELECT 'CHF', 1, '428%', 'I50%' UNION ALL
  SELECT 'PVD', 1, '4439', 'I73.9' UNION ALL
  SELECT 'CVD', 1, '430%', 'I60%' UNION ALL
  SELECT 'Dementia', 1, '290%', 'F03%' UNION ALL
  SELECT 'COPD', 1, '496', 'J44%' UNION ALL
  SELECT 'Rheum', 1, '714%', 'M06%' UNION ALL
  SELECT 'PUD', 1, '531%', 'K25%' UNION ALL
  SELECT 'Mild liver', 1, '5712', 'K73%' UNION ALL
  SELECT 'Diabetes', 1, '250%', 'E10%' UNION ALL
  SELECT 'DiabComp', 2, '2504', 'E10.2%' UNION ALL
  SELECT 'Paraplegia', 2, '3441', 'G82%' UNION ALL
  SELECT 'Renal', 2, '585%', 'N18%' UNION ALL
  SELECT 'Cancer', 2, '140%', 'C00%' UNION ALL
  SELECT 'ModSevLiver', 3, '5722', 'K74.6%' UNION ALL
  SELECT 'Metastatic', 6, '196%', 'C77%' UNION ALL
  SELECT 'AIDS', 6, '042', 'B20%'
),

-- 4. For each admission, calculate CCI
admission_cci AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    MAX(pat.anchor_age) AS anchor_age,
    MAX(pat.gender) AS gender,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    -- CCI calculation
    SUM(
      CASE
        WHEN diag.icd_version = 9 THEN
          CASE
            WHEN diag.icd_code LIKE '410%' THEN 1
            WHEN diag.icd_code LIKE '428%' THEN 1
            WHEN diag.icd_code LIKE '4439' THEN 1
            WHEN diag.icd_code LIKE '430%' THEN 1
            WHEN diag.icd_code LIKE '290%' THEN 1
            WHEN diag.icd_code LIKE '496' THEN 1
            WHEN diag.icd_code LIKE '714%' THEN 1
            WHEN diag.icd_code LIKE '531%' THEN 1
            WHEN diag.icd_code LIKE '5712' THEN 1
            WHEN diag.icd_code LIKE '250%' THEN 1
            WHEN diag.icd_code LIKE '2504' THEN 2
            WHEN diag.icd_code LIKE '3441' THEN 2
            WHEN diag.icd_code LIKE '585%' THEN 2
            WHEN diag.icd_code LIKE '140%' THEN 2
            WHEN diag.icd_code LIKE '5722' THEN 3
            WHEN diag.icd_code LIKE '196%' THEN 6
            WHEN diag.icd_code LIKE '042' THEN 6
            ELSE 0
          END
        WHEN diag.icd_version = 10 THEN
          CASE
            WHEN diag.icd_code LIKE 'I21%' THEN 1
            WHEN diag.icd_code LIKE 'I50%' THEN 1
            WHEN diag.icd_code LIKE 'I73.9' THEN 1
            WHEN diag.icd_code LIKE 'I60%' THEN 1
            WHEN diag.icd_code LIKE 'F03%' THEN 1
            WHEN diag.icd_code LIKE 'J44%' THEN 1
            WHEN diag.icd_code LIKE 'M06%' THEN 1
            WHEN diag.icd_code LIKE 'K25%' THEN 1
            WHEN diag.icd_code LIKE 'K73%' THEN 1
            WHEN diag.icd_code LIKE 'E10%' THEN 1
            WHEN diag.icd_code LIKE 'E10.2%' THEN 2
            WHEN diag.icd_code LIKE 'G82%' THEN 2
            WHEN diag.icd_code LIKE 'N18%' THEN 2
            WHEN diag.icd_code LIKE 'C00%' THEN 2
            WHEN diag.icd_code LIKE 'K74.6%' THEN 3
            WHEN diag.icd_code LIKE 'C77%' THEN 6
            WHEN diag.icd_code LIKE 'B20%' THEN 6
            ELSE 0
          END
        ELSE 0
      END
    ) AS cci,
    -- PE flag
    MAX(
      CASE
        WHEN EXISTS (
          SELECT 1 FROM pe_icd
          WHERE pe_icd.icd_code = diag.icd_code AND pe_icd.icd_version = diag.icd_version
        ) THEN 1 ELSE 0
      END
    ) AS has_pe
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat ON adm.subject_id = pat.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.anchor_age BETWEEN 59 AND 69
    AND pat.gender = 'F'
  GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.deathtime, adm.hospital_expire_flag
),

-- 5. Identify cardio/neuro complications per admission
admission_complications AS (
  SELECT
    adm.hadm_id,
    MAX(
      CASE
        WHEN EXISTS (
          SELECT 1 FROM cardio_icd
          WHERE cardio_icd.icd_code = diag.icd_code AND cardio_icd.icd_version = diag.icd_version
        ) THEN 1 ELSE 0
      END
    ) AS cardio_complication,
    MAX(
      CASE
        WHEN EXISTS (
          SELECT 1 FROM neuro_icd
          WHERE neuro_icd.icd_code = diag.icd_code AND neuro_icd.icd_version = diag.icd_version
        ) THEN 1 ELSE 0
      END
    ) AS neuro_complication
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON diag.hadm_id = adm.hadm_id
  GROUP BY adm.hadm_id
),

-- 6. Merge CCI and complications
admission_full AS (
  SELECT
    a.*,
    c.cardio_complication,
    c.neuro_complication
  FROM admission_cci a
  LEFT JOIN admission_complications c ON a.hadm_id = c.hadm_id
),

-- 7. Define cohorts
pe_high_cci AS (
  SELECT *
  FROM admission_full
  WHERE has_pe = 1 AND cci >= 3
),
controls AS (
  SELECT *
  FROM admission_full
  WHERE has_pe = 0
),

-- 8. Calculate survivor LOS
pe_high_cci_survivors AS (
  SELECT
    *,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0 AS los_days
  FROM pe_high_cci
  WHERE hospital_expire_flag = 0
),
controls_survivors AS (
  SELECT
    *,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0 AS los_days
  FROM controls
  WHERE hospital_expire_flag = 0
),

-- 9. Calculate percentile of each PE+high CCI patient's CCI vs controls
pe_high_cci_percentiles AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.cci,
    ROUND(100.0 * (
      SELECT COUNT(*) FROM controls WHERE controls.cci <= p.cci
    ) / (SELECT COUNT(*) FROM controls), 1) AS cci_percentile_vs_controls
  FROM pe_high_cci p
)

-- 10. Final output
SELECT
  -- Mean CCI and 30-day mortality for PE+high CCI cohort
  (SELECT ROUND(AVG(cci),2) FROM pe_high_cci) AS pe_high_cci_mean_cci,
  (SELECT ROUND(100.0 * COUNTIF(
    hospital_expire_flag = 1 AND
    (deathtime IS NOT NULL AND TIMESTAMP_DIFF(deathtime, admittime, DAY) <= 30)
  ) / COUNT(*),1) FROM pe_high_cci) AS pe_high_cci_30day_mortality_pct,

  -- Cardio/neuro complication rates for PE+high CCI cohort
  (SELECT ROUND(100.0 * COUNTIF(cardio_complication = 1)/COUNT(*),1) FROM pe_high_cci) AS pe_high_cci_cardio_complication_pct,
  (SELECT ROUND(100.0 * COUNTIF(neuro_complication = 1)/COUNT(*),1) FROM pe_high_cci) AS pe_high_cci_neuro_complication_pct,

  -- Survivor LOS for PE+high CCI cohort
  (SELECT ROUND(AVG(los_days),2) FROM pe_high_cci_survivors) AS pe_high_cci_survivor_mean_los_days,

  -- Cardio/neuro complication rates for controls
  (SELECT ROUND(100.0 * COUNTIF(cardio_complication = 1)/COUNT(*),1) FROM controls) AS controls_cardio_complication_pct,
  (SELECT ROUND(100.0 * COUNTIF(neuro_complication = 1)/COUNT(*),1) FROM controls) AS controls_neuro_complication_pct,

  -- Survivor LOS for controls
  (SELECT ROUND(AVG(los_days),2) FROM controls_survivors) AS controls_survivor_mean_los_days,

  -- For each PE+high CCI patient, their CCI percentile vs controls
  ARRAY_AGG(STRUCT(subject_id, hadm_id, cci, cci_percentile_vs_controls)) AS pe_high_cci_patient_percentiles

FROM pe_high_cci_percentiles;