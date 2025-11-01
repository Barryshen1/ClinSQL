WITH sepsis_hadm AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON di.icd_code = dd.icd_code 
    AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%sepsis%'
),
male_adm AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
eligible_hadm AS (
  SELECT sh.hadm_id
  FROM sepsis_hadm sh
  JOIN male_adm ma ON sh.hadm_id = ma.hadm_id
),
first_creat AS (
  SELECT 
    le.hadm_id, 
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN eligible_hadm eh ON le.hadm_id = eh.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON le.hadm_id = a.hadm_id
  WHERE le.itemid = 220615
    AND le.valuenum IS NOT NULL
    AND le.charttime >= a.admittime
)
SELECT MAX(valuenum) AS max_index_creatinine
FROM first_creat
WHERE rn = 1;