WITH age_calc AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
),
-- Define lower GI bleed ICD-10 codes
gi_blood_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE (
    SUBSTR(icd_code, 1, 3) IN ('K57', 'K62', 'K63') OR
    (icd_code = 'K922' AND icd_version = 10) -- K92.2 in ICD-10
  )
),
cohort AS (
  SELECT DISTINCT ac.*
  FROM age_calc ac
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON ac.hadm_id = di.hadm_id
  INNER JOIN gi_blood_codes gbc
    ON di.icd_code = gbc.icd_code AND di.icd_version = 10
  WHERE ac.gender = 'F'
    AND ac.age_at_admit >= 65 AND ac.age_at_admit <= 75
),
lab_72h AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper,
    -- Flag abnormal: outside reference range
    CASE
      WHEN l.valuenum < l.ref_range_lower THEN 1
      WHEN l.valuenum > l.ref_range_upper THEN 1
      ELSE 0
    END AS is_abnormal
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents l
  INNER JOIN cohort c
    ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  WHERE l.charttime >= c.admittime
    AND l.charttime <= DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
    AND (l.ref_range_lower IS NOT NULL OR l.ref_range_upper IS NOT NULL)
),
abnormal_lab_counts AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(is_abnormal) AS abnormal_lab_count
  FROM lab_72h
  GROUP BY subject_id, hadm_id
),
-- For comparison: general inpatient cohort (all adults with lab in first 72h)
general_inpatients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE (p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime))) >= 18
),
general_lab_72h AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    CASE
      WHEN l.valuenum < l.ref_range_lower THEN 1
      WHEN l.valuenum > l.ref_range_upper THEN 1
      ELSE 0
    END AS is_abnormal
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents l
  INNER JOIN general_inpatients g
    ON l.subject_id = g.subject_id AND l.hadm_id = g.hadm_id
  WHERE l.charttime >= g.admittime
    AND l.charttime <= DATETIME_ADD(g.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
    AND (l.ref_range_lower IS NOT NULL OR l.ref_range_upper IS NOT NULL)
),
general_abnormal_counts AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(is_abnormal) AS abnormal_lab_count
  FROM general_lab_72h
  GROUP BY subject_id, hadm_id
),
-- Summary statistics
cohort_stats AS (
  SELECT
    -- 25th percentile of abnormal lab count in GI bleed cohort
    APPROX_QUANTILES(CAST(abnormal_lab_count AS FLOAT64), 100)[OFFSET(25)] AS p25_lab_instability_score,
    -- Median LOS in days
    APPROX_QUANTILES(DATETIME_DIFF(dischtime, admittime, SECOND) / (24*60*60), 100)[OFFSET(50)] AS median_los_days,
    -- Hospital mortality rate
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality_rate
  FROM abnormal_lab_counts alc
  INNER JOIN cohort c
    USING (subject_id, hadm_id)
),
general_stats AS (
  SELECT
    APPROX_QUANTILES(CAST(abnormal_lab_count AS FLOAT64), 100)[OFFSET(25)] AS general_p25_lab_instability
  FROM general_abnormal_counts
)
-- Final output
SELECT
  cs.p25_lab_instability_score,
  cs.median_los_days,
  cs.hospital_mortality_rate,
  gs.general_p25_lab_instability
FROM cohort_stats cs
CROSS JOIN general_stats gs;