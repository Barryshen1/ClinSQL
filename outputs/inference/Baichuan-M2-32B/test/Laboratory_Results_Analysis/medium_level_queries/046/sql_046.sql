WITH patient_cohort AS (
  SELECT p.subject_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
),
first_admission_per_patient AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM patient_cohort p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE a.dischtime IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),
troponin_measurements AS (
  SELECT 
    fap.subject_id, 
    fap.anchor_age, 
    fap.hadm_id, 
    l.valuenum,
    l.ref_range_upper
  FROM first_admission_per_patient fap
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON fap.hadm_id = l.hadm_id AND fap.subject_id = l.subject_id
  WHERE l.itemid IN (51265, 51266)
    AND l.valuenum IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND l.valuenum > l.ref_range_upper
  QUALIFY ROW_NUMBER() OVER (PARTITION BY fap.subject_id, fap.hadm_id ORDER BY l.charttime) = 1
),
patient_stats AS (
  SELECT 
    COUNT(DISTINCT t.subject_id) AS N,
    AVG(t.anchor_age) AS mean_age,
    AVG(DATE_DIFF(CAST(t.dischtime AS DATE), CAST(t.admittime AS DATE), DAY)) AS mean_los
  FROM troponin_measurements t
),
troponin_stats AS (
  SELECT 
    MIN(valuenum) AS min_troponin,
    MAX(valuenum) AS max_troponin,
    AVG(valuenum) AS mean_troponin,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_troponin
  FROM troponin_measurements
)
SELECT 
  p.N,
  p.mean_age,
  p.mean_los,
  t.min_troponin,
  t.max_troponin,
  t.mean_troponin,
  t.median_troponin
FROM patient_stats p, troponin_stats t;