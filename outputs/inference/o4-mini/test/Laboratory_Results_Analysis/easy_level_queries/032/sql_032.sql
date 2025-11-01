WITH cohort AS (
  -- Male, age 90, with at least one COPD diagnosis in this admission
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
   AND a.hadm_id    = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code    = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age = 90
    AND LOWER(dd.long_title) LIKE '%copd%'
),

creatinine_labs AS (
  -- Identify creatinine itemids
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%'
    AND LOWER(category) = 'chemistry'
),

labs_in_24h AS (
  -- All creatinine measurements in the first 24h of admission
  SELECT
    c.subject_id,
    c.hadm_id,
    le.valuenum
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id
   AND c.hadm_id    = le.hadm_id
  JOIN creatinine_labs cl
    ON le.itemid = cl.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.charttime BETWEEN c.admittime
                        AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
),

per_admission_avg AS (
  -- Average creatinine per admission
  SELECT
    subject_id,
    hadm_id,
    AVG(valuenum) AS avg_creat
  FROM labs_in_24h
  GROUP BY subject_id, hadm_id
)

-- Final standard deviation across admissions
SELECT
  STDDEV_SAMP(avg_creat) AS sd_of_avg_creatinine_24h
FROM per_admission_avg;