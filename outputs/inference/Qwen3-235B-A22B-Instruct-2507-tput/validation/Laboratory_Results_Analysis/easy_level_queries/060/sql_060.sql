WITH male_pneumonia_admissions AS (
  SELECT DISTINCT a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age = 67
    AND LOWER(d.long_title) LIKE '%pneumonia%'
),
glucose_in_first_24h AS (
  SELECT 
    mpa.hadm_id,
    AVG(le.valuenum) AS mean_glucose_24h
  FROM male_pneumonia_admissions mpa
  JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le ON mpa.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems dli ON le.itemid = dli.itemid
  WHERE le.charttime >= mpa.admittime
    AND le.charttime < DATETIME_ADD(mpa.admittime, INTERVAL 24 HOUR)
    AND LOWER(dli.label) LIKE '%GLUCOSE%'
    AND LOWER(dli.fluid) = 'blood'
    AND le.valuenum IS NOT NULL
  GROUP BY mpa.hadm_id
)
SELECT
  APPROX_QUANTILES(mean_glucose_24h, 1000)[OFFSET(750)] AS glucose_75th_percentile
FROM glucose_in_first_24h;