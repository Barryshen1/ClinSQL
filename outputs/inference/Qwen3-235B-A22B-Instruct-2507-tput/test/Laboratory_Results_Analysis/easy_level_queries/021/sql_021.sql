WITH male_pneumonia_admissions AS (
  SELECT DISTINCT a.hadm_id, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND LOWER(d.long_title) LIKE '%pneumonia%'
),
glucose_at_discharge AS (
  SELECT 
    le.hadm_id,
    le.valuenum AS glucose_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
  JOIN male_pneumonia_admissions mpa ON le.hadm_id = mpa.hadm_id
  WHERE LOWER(dli.label) = 'glucose'
    AND LOWER(dli.fluid) = 'blood'
    AND le.charttime <= mpa.dischtime
    AND le.valuenum IS NOT NULL
),
latest_glucose AS (
  SELECT 
    hadm_id,
    glucose_value,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime DESC) AS rn
  FROM (
    SELECT 
      le.hadm_id,
      le.valuenum AS glucose_value,
      le.charttime
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
    JOIN male_pneumonia_admissions mpa ON le.hadm_id = mpa.hadm_id
    WHERE LOWER(dli.label) = 'glucose'
      AND LOWER(dli.fluid) = 'blood'
      AND le.charttime <= mpa.dischtime
      AND le.valuenum IS NOT NULL
  )
)
SELECT 
  APPROX_QUANTILES(glucose_value, 1000)[OFFSET(750)] AS glucose_75th_percentile
FROM latest_glucose
WHERE rn = 1;