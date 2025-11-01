WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_year IS NOT NULL
    AND p.anchor_age IS NOT NULL
    AND TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 71 AND 81
),
icu_stays AS (
  SELECT 
    i.hadm_id,
    i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN eligible_admissions e
    ON i.hadm_id = e.hadm_id
),
dbp_measurements AS (
  SELECT 
    c.hadm_id,
    c.valuenum AS dbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON c.itemid = di.itemid
  INNER JOIN icu_stays i
    ON c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  WHERE 
    di.label LIKE '%diastolic%' 
    AND di.label LIKE '%blood pressure%'
    AND di.unitname = 'mmHg'
    AND c.valuenum > 0
),
max_dbp_per_admission AS (
  SELECT 
    hadm_id,
    MAX(dbp) AS max_dbp
  FROM dbp_measurements
  GROUP BY hadm_id
)
SELECT 
  APPROX_QUANTILES(max_dbp, 100)[OFFSET(50)] AS median_max_dbp
FROM max_dbp_per_admission;