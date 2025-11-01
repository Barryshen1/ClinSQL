WITH acs_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON p.subject_id = d.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND (LOWER(dicd.long_title) LIKE '%acute coronary syndrome%'
         OR LOWER(dicd.long_title) LIKE '%myocardial infarction%'
         OR LOWER(dicd.long_title) LIKE '%unstable angina%')
),

initial_troponin AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
    AND le.valuenum > 0.014
)

SELECT
  COUNT(DISTINCT ap.subject_id) AS patient_count,
  COUNT(DISTINCT ap.hadm_id) AS admission_count,
  AVG(it.valuenum) AS mean_troponin,
  PERCENTILE_CONT(it.valuenum, 0.5) AS median_troponin,
  PERCENTILE_CONT(it.valuenum, 0.75) - PERCENTILE_CONT(it.valuenum, 0.25) AS iqr_troponin
FROM acs_patients ap
INNER JOIN initial_troponin it
  ON ap.hadm_id = it.hadm_id
WHERE it.rn = 1;