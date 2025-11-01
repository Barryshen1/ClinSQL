WITH
-- Get female patients aged 57-67
female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 57 AND 67
),

-- Get admissions with septic shock
septic_shock_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code
  WHERE a.subject_id IN (SELECT subject_id FROM female_patients)
    AND (d.icd_code = 'R65.21' OR di.long_title LIKE '%septic shock%')
),

-- Get ICU stays for these admissions
icu_stays AS (
  SELECT s.hadm_id, s.intime, s.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN septic_shock_admissions a ON s.hadm_id = a.hadm_id
),

-- Get ultrasounds from HOSP module (HCPCS events)
hosp_ultrasounds AS (
  SELECT h.hadm_id, h.hcpcs_cd, h.chartdate
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN septic_shock_admissions a ON h.hadm_id = a.hadm_id
  WHERE h.hcpcs_cd LIKE '%76%'  -- Common ultrasound HCPCS codes start with 76
     OR h.short_description LIKE '%ultrasound%'
     OR h.short_description LIKE '%echo%'
),

-- Get ultrasounds from ICU module (procedure events)
icu_ultrasounds AS (
  SELECT p.hadm_id, p.itemid, p.starttime
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN septic_shock_admissions a ON p.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON p.itemid = di.itemid
  WHERE di.label LIKE '%ultrasound%'
     OR di.label LIKE '%echo%'
),

-- Combine all ultrasounds and deduplicate
all_ultrasounds AS (
  SELECT hadm_id, COUNT(DISTINCT
    CASE
      WHEN hcpcs_cd IS NOT NULL THEN CONCAT(CAST(hadm_id AS STRING), '-hosp-', hcpcs_cd, '-', CAST(chartdate AS STRING))
      WHEN itemid IS NOT NULL THEN CONCAT(CAST(hadm_id AS STRING), '-icu-', CAST(itemid AS STRING), '-', CAST(starttime AS STRING))
    END) AS ultrasound_count
  FROM (
    SELECT hadm_id, hcpcs_cd, chartdate, NULL AS itemid, NULL AS starttime
    FROM hosp_ultrasounds
    UNION ALL
    SELECT hadm_id, NULL AS hcpcs_cd, NULL AS chartdate, itemid, starttime
    FROM icu_ultrasounds
  )
  GROUP BY hadm_id
),

-- Categorize admissions by LOS and ICU status
admission_categories AS (
  SELECT
    a.hadm_id,
    CASE
      WHEN a.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN a.los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL
    END AS los_category,
    CASE WHEN i.hadm_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_status
  FROM septic_shock_admissions a
  LEFT JOIN icu_stays i ON a.hadm_id = i.hadm_id
  WHERE a.los_days BETWEEN 1 AND 7
),

-- Final aggregation
final_counts AS (
  SELECT
    ac.los_category,
    ac.icu_status,
    au.ultrasound_count
  FROM admission_categories ac
  LEFT JOIN all_ultrasounds au ON ac.hadm_id = au.hadm_id
  WHERE au.hadm_id IS NOT NULL
)

-- Calculate percentiles
SELECT
  los_category,
  icu_status,
  COUNT(*) AS admission_count,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(3)] AS p75
FROM final_counts
GROUP BY los_category, icu_status
ORDER BY los_category, icu_status;