WITH septic_shock_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
    AND (
      (d.icd_version = 9 AND d.icd_code = '78552') -- ICD-9 septic shock
      OR
      (d.icd_version = 10 AND d.icd_code = 'R6521') -- ICD-10 septic shock
    )
),

-- Step 2: All female inpatients aged 89-99 (for comparison)
general_female_8999 AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
),

-- Step 3: Abnormal labs in first 48h for cohort
cohort_abnormal_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    COUNTIF(
      SAFE_CAST(l.valuenum AS FLOAT64) < SAFE_CAST(l.ref_range_lower AS FLOAT64)
      OR SAFE_CAST(l.valuenum AS FLOAT64) > SAFE_CAST(l.ref_range_upper AS FLOAT64)
    ) AS abnormal_lab_count,
    COUNT(*) AS total_lab_count
  FROM physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN septic_shock_cohort c
    ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  WHERE
    l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
  GROUP BY l.subject_id, l.hadm_id
),

-- Step 4: Abnormal labs in first 48h for general cohort
general_abnormal_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    COUNTIF(
      SAFE_CAST(l.valuenum AS FLOAT64) < SAFE_CAST(l.ref_range_lower AS FLOAT64)
      OR SAFE_CAST(l.valuenum AS FLOAT64) > SAFE_CAST(l.ref_range_upper AS FLOAT64)
    ) AS abnormal_lab_count,
    COUNT(*) AS total_lab_count
  FROM physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN general_female_8999 g
    ON l.subject_id = g.subject_id AND l.hadm_id = g.hadm_id
  WHERE
    l.charttime BETWEEN g.admittime AND TIMESTAMP_ADD(g.admittime, INTERVAL 48 HOUR)
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
  GROUP BY l.subject_id, l.hadm_id
),

-- Step 5: Abnormal vital signs in first 48h for cohort (ICU only)
-- We'll use chartevents for common vitals: Heart Rate, SBP, RR, Temp
-- Get itemids for these from d_items
vital_itemids AS (
  SELECT itemid, LOWER(label) AS label
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE LOWER(label) IN ('heart rate', 'systolic blood pressure', 'respiratory rate', 'temperature')
),

cohort_abnormal_vitals AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    COUNTIF(
      (vi.label = 'heart rate' AND SAFE_CAST(ce.valuenum AS FLOAT64) > 100)
      OR (vi.label = 'systolic blood pressure' AND SAFE_CAST(ce.valuenum AS FLOAT64) < 90)
      OR (vi.label = 'respiratory rate' AND SAFE_CAST(ce.valuenum AS FLOAT64) > 20)
      OR (vi.label = 'temperature' AND (SAFE_CAST(ce.valuenum AS FLOAT64) < 36 OR SAFE_CAST(ce.valuenum AS FLOAT64) > 38))
    ) AS abnormal_vital_count,
    COUNT(*) AS total_vital_count
  FROM physionet-data.mimiciv_3_1_icu.chartevents ce
  JOIN septic_shock_cohort c
    ON ce.subject_id = c.subject_id AND ce.hadm_id = c.hadm_id
  JOIN vital_itemids vi
    ON ce.itemid = vi.itemid
  WHERE
    ce.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.subject_id, ce.hadm_id
),

-- Step 6: Combine abnormal labs and vitals for instability score
cohort_instability AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COALESCE(l.abnormal_lab_count, 0) + COALESCE(v.abnormal_vital_count, 0) AS instability_score,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag
  FROM septic_shock_cohort c
  LEFT JOIN cohort_abnormal_labs l
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
  LEFT JOIN cohort_abnormal_vitals v
    ON c.subject_id = v.subject_id AND c.hadm_id = v.hadm_id
),

-- Step 7: LOS and mortality for cohort
cohort_los_mortality AS (
  SELECT
    COUNT(*) AS n_patients,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0) AS avg_los_days,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END)/COUNT(*) AS mortality_rate
  FROM septic_shock_cohort
)

-- Final output
SELECT
  -- Part 1: Instability score stats
  APPROX_QUANTILES(instability_score, 4)[OFFSET(1)] AS Q1,
  APPROX_QUANTILES(instability_score, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS Q3,
  APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] - APPROX_QUANTILES(instability_score, 4)[OFFSET(1)] AS IQR,

  -- Part 2: Abnormal lab frequency
  (SELECT SAFE_DIVIDE(SUM(abnormal_lab_count), SUM(total_lab_count)) FROM cohort_abnormal_labs) AS cohort_abnormal_lab_freq,
  (SELECT SAFE_DIVIDE(SUM(abnormal_lab_count), SUM(total_lab_count)) FROM general_abnormal_labs) AS general_abnormal_lab_freq,

  -- LOS and mortality
  (SELECT avg_los_days FROM cohort_los_mortality) AS avg_los_days,
  (SELECT mortality_rate FROM cohort_los_mortality) AS mortality_rate,
  (SELECT n_patients FROM cohort_los_mortality) AS n_patients
FROM cohort_instability;