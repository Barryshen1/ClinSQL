WITH first_admissions AS (
  -- First admission per subject
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 65 AND 75
),

cases_base AS (
  -- Pancreatitis cases (primary dx)
  SELECT 
    fa.*,
    DATE_DIFF(DATE(fa.dischtime), DATE(fa.admittime), DAY) AS LOS_days  -- LOS in days
  FROM first_admissions fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON fa.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE fa.rn = 1
    AND d.icd_version = '10'
    AND REGEXP_CONTAINS(d.icd_code, r'^K85')
    AND fa.dischtime > fa.admittime  -- Exclude same-day discharge
),

controls_base AS (
  -- Age-matched females without pancreatitis (any primary dx except K85)
  SELECT 
    fa.*,
    DATE_DIFF(DATE(fa.dischtime), DATE(fa.admittime), DAY) AS LOS_days
  FROM first_admissions fa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON fa.hadm_id = d.hadm_id AND d.seq_num = 1 AND d.icd_version = '10'
  WHERE fa.rn = 1
    AND (d.icd_code IS NULL OR NOT REGEXP_CONTAINS(d.icd_code, r'^K85'))
    AND fa.dischtime > fa.admittime
),

first48_labs_cases AS (
  SELECT 
    cb.subject_id,
    cb.hadm_id,
    cb.anchor_age,
    cb.LOS_days,
    cb.hospital_expire_flag,
    le.itemid,
    le.valuenum,
    le.valueuom,
    le.flag,
    -- Hardcoded normal ranges (median and half-width for deviation; fallback if ref_range null)
    CASE 
      WHEN le.itemid = 5131 THEN (4.5 + 11.0)/2  -- WBC median 7.75, half-width 3.25
      WHEN le.itemid = 50983 THEN (135 + 145)/2  -- Na 140, half 5
      WHEN le.itemid = 50971 THEN (3.5 + 5.0)/2  -- K 4.25, half 0.75
      WHEN le.itemid = 51006 THEN (0.6 + 1.2)/2  -- Cr 0.9, half 0.3
      WHEN le.itemid = 51265 THEN (0.5 + 2.0)/2  -- Lactate 1.25, half 0.75
      ELSE NULL 
    END AS ref_median,
    CASE 
      WHEN le.itemid = 5131 THEN 3.25
      WHEN le.itemid = 50983 THEN 5
      WHEN le.itemid = 50971 THEN 0.75
      WHEN le.itemid = 51006 THEN 0.3
      WHEN le.itemid = 51265 THEN 0.75
      ELSE 1  -- Default to avoid div0
    END AS ref_halfwidth
  FROM cases_base cb
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON cb.subject_id = le.subject_id 
    AND cb.hadm_id = le.hadm_id
  WHERE le.charttime >= cb.admittime 
    AND le.charttime < TIMESTAMP_ADD(cb.admittime, INTERVAL 48 HOUR)
    AND le.valuenum IS NOT NULL
    AND le.itemid IN (5131, 50983, 50971, 51006, 51265)  -- Core labs: WBC, Na, K, Cr, Lactate
),

instability_cases AS (
  SELECT 
    subject_id,
    hadm_id,
    anchor_age,
    LOS_days,
    hospital_expire_flag,
    -- Deviation: normalized distance from ref center
    AVG(
      SAFE_DIVIDE(
        ABS(valuenum - ref_median),  -- Use ref_median directly; SAFE_DIVIDE handles NULL
        ref_halfwidth
      )
    ) AS instability_score,
    -- Critical: any abnormal flag or extreme value
    LOGICAL_OR(
      flag = 'abnormal' OR 
      (itemid = 51265 AND valuenum > 4) OR  -- Lactate critical
      (itemid = 51006 AND valuenum > 3) OR  -- Cr critical
      (itemid = 50971 AND (valuenum < 2.5 OR valuenum > 6))  -- K critical
    ) AS has_critical_lab
  FROM first48_labs_cases
  GROUP BY subject_id, hadm_id, anchor_age, LOS_days, hospital_expire_flag
),

quintiles_cases AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY instability_score) AS quintile
  FROM instability_cases
  WHERE instability_score IS NOT NULL  -- Exclude no-labs (rare)
),

cases_summary AS (
  SELECT 
    quintile,
    COUNT(*) AS count,
    AVG(instability_score) AS mean_instability,
    AVG(LOS_days) AS mean_los,
    AVG(hospital_expire_flag) AS mean_mortality,
    SAFE_DIVIDE(COUNTIF(has_critical_lab), COUNT(*)) * 100 AS pct_critical_labs
  FROM quintiles_cases
  GROUP BY quintile
),

controls_labs AS (
  SELECT 
    cb.subject_id,
    cb.hadm_id,
    cb.anchor_age,
    cb.LOS_days,
    cb.hospital_expire_flag,
    le.itemid,
    le.valuenum,
    le.flag,
    -- Same ref ranges as cases
    CASE 
      WHEN le.itemid = 5131 THEN (4.5 + 11.0)/2
      WHEN le.itemid = 50983 THEN (135 + 145)/2
      WHEN le.itemid = 50971 THEN (3.5 + 5.0)/2
      WHEN le.itemid = 51006 THEN (0.6 + 1.2)/2
      WHEN le.itemid = 51265 THEN (0.5 + 2.0)/2
      ELSE NULL 
    END AS ref_median,
    CASE 
      WHEN le.itemid = 5131 THEN 3.25
      WHEN le.itemid = 50983 THEN 5
      WHEN le.itemid = 50971 THEN 0.75
      WHEN le.itemid = 51006 THEN 0.3
      WHEN le.itemid = 51265 THEN 0.75
      ELSE 1
    END AS ref_halfwidth
  FROM controls_base cb
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON cb.subject_id = le.subject_id 
    AND cb.hadm_id = le.hadm_id
  WHERE le.charttime >= cb.admittime 
    AND le.charttime < TIMESTAMP_ADD(cb.admittime, INTERVAL 48 HOUR)
    AND le.valuenum IS NOT NULL
    AND le.itemid IN (5131, 50983, 50971, 51006, 51265)
),

instability_controls AS (
  SELECT 
    subject_id,
    hadm_id,
    AVG(SAFE_DIVIDE(ABS(valuenum - ref_median), ref_halfwidth)) AS instability_score,
    LOGICAL_OR(flag = 'abnormal' OR 
      (itemid = 51265 AND valuenum > 4) OR 
      (itemid = 51006 AND valuenum > 3) OR 
      (itemid = 50971 AND (valuenum < 2.5 OR valuenum > 6))
    ) AS has_critical_lab
  FROM controls_labs
  GROUP BY subject_id, hadm_id
),

controls_summary AS (
  SELECT 
    'Controls' AS cohort,
    COUNT(*) AS count,
    AVG(instability_score) AS mean_instability,
    AVG(LOS_days) AS mean_los,
    AVG(hospital_expire_flag) AS mean_mortality,
    SAFE_DIVIDE(SUM(IF(has_critical_lab, 1, 0)), COUNT(*)) * 100 AS pct_critical_labs
  FROM controls_base cb
  INNER JOIN instability_controls ic
    ON cb.subject_id = ic.subject_id AND cb.hadm_id = ic.hadm_id
  WHERE ic.instability_score IS NOT NULL
)

-- Final output: Cases by quintile + Controls summary
SELECT 
  'Cases' AS cohort,
  CAST(quintile AS STRING) AS quintile,
  count,
  ROUND(mean_instability, 2) AS mean_instability,
  ROUND(mean_los, 2) AS mean_los,
  ROUND(mean_mortality * 100, 2) AS mortality_pct,
  ROUND(pct_critical_labs, 2) AS pct_critical_labs
FROM cases_summary

UNION ALL

SELECT 
  cohort,
  NULL AS quintile,
  count,
  ROUND(mean_instability, 2),
  ROUND(mean_los, 2),
  ROUND(mean_mortality * 100, 2),
  ROUND(pct_critical_labs, 2)
FROM controls_summary

ORDER BY cohort, quintile;