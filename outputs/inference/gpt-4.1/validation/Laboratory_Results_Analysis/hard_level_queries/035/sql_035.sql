WITH
-- 1. Identify acute ischemic stroke ICD codes
stroke_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-10: I63.x
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I63'))
    -- ICD-9: 433.x1, 434.x
    OR (icd_version = 9 AND (
      REGEXP_CONTAINS(icd_code, r'^434')
      OR REGEXP_CONTAINS(icd_code, r'^433[0-9]1')
    ))
),

-- 2. Cohort: Female, age 78-88, with acute ischemic stroke
cohort_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN stroke_icd s
    ON d.icd_code = s.icd_code AND d.icd_version = s.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
),

-- 3. General inpatients (for comparison)
all_admissions AS (
  SELECT subject_id, hadm_id, admittime, dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- 4. Critical lab events in first 72h for cohort
cohort_lab_events AS (
  SELECT
    l.hadm_id,
    COUNTIF(
      -- Use flag if present, otherwise compare to reference ranges
      (l.flag = 'abnormal')
      OR (l.ref_range_lower IS NOT NULL AND SAFE_CAST(l.valuenum AS FLOAT64) < SAFE_CAST(l.ref_range_lower AS FLOAT64))
      OR (l.ref_range_upper IS NOT NULL AND SAFE_CAST(l.valuenum AS FLOAT64) > SAFE_CAST(l.ref_range_upper AS FLOAT64))
    ) AS critical_lab_events_72h
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN cohort_admissions a
    ON l.hadm_id = a.hadm_id
  WHERE
    l.charttime >= a.admittime
    AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY l.hadm_id
),

-- 5. Critical lab events in first 72h for all inpatients
all_lab_events AS (
  SELECT
    l.hadm_id,
    COUNTIF(
      (l.flag = 'abnormal')
      OR (l.ref_range_lower IS NOT NULL AND SAFE_CAST(l.valuenum AS FLOAT64) < SAFE_CAST(l.ref_range_lower AS FLOAT64))
      OR (l.ref_range_upper IS NOT NULL AND SAFE_CAST(l.valuenum AS FLOAT64) > SAFE_CAST(l.ref_range_upper AS FLOAT64))
    ) AS critical_lab_events_72h
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN all_admissions a
    ON l.hadm_id = a.hadm_id
  WHERE
    l.charttime >= a.admittime
    AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY l.hadm_id
),

-- 6. LOS and mortality for cohort
cohort_los_mortality AS (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24.0 AS los_days,
    a.hospital_expire_flag
  FROM cohort_admissions a
)

-- Final output
SELECT
  -- Minimum 72h lab instability score in cohort
  MIN(IFNULL(cle.critical_lab_events_72h, 0)) AS min_lab_instability_score_72h,
  -- Cohort average critical lab events (first 72h)
  AVG(IFNULL(cle.critical_lab_events_72h, 0)) AS cohort_avg_critical_lab_events_72h,
  -- General inpatient average critical lab events (first 72h)
  (SELECT AVG(IFNULL(ale.critical_lab_events_72h, 0)) FROM all_lab_events ale) AS general_inpatient_avg_critical_lab_events_72h,
  -- Cohort LOS (mean, median)
  AVG(clm.los_days) AS cohort_avg_los_days,
  APPROX_QUANTILES(clm.los_days, 2)[OFFSET(1)] AS cohort_median_los_days,
  -- Cohort in-hospital mortality rate
  AVG(clm.hospital_expire_flag) AS cohort_inhospital_mortality_rate
FROM cohort_admissions ca
LEFT JOIN cohort_lab_events cle
  ON ca.hadm_id = cle.hadm_id
LEFT JOIN cohort_los_mortality clm
  ON ca.hadm_id = clm.hadm_id;