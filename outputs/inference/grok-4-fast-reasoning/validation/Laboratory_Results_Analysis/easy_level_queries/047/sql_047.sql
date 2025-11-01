WITH hf_admissions AS (
  SELECT DISTINCT
    di.subject_id,
    di.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE 
    ((di.icd_version = 9 AND di.icd_code LIKE '428%') 
     OR 
     (di.icd_version = 10 AND di.icd_code LIKE 'I50%'))
),
admission_labs AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.valuenum
  FROM 
    hf_admissions ha
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON ha.subject_id = p.subject_id
      AND p.gender = 'M'
      AND p.anchor_age >= 18
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON ha.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON ha.subject_id = le.subject_id
      AND ha.hadm_id = le.hadm_id
    WHERE 
      le.itemid = 220615
      AND le.valuenum IS NOT NULL
      AND le.charttime >= a.admittime
      AND le.charttime <= a.admittime + INTERVAL 1 DAY
),
per_admission_max AS (
  SELECT 
    hadm_id,
    MAX(valuenum) AS max_creatinine
  FROM 
    admission_labs
  GROUP BY 
    hadm_id
)
SELECT 
  MAX(max_creatinine) AS maximum_serum_creatinine_first_24h
FROM 
  per_admission_max;