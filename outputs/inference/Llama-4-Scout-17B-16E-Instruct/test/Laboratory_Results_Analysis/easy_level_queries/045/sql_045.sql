WITH 
serum_creatinine_itemid AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
  WHERE label = 'Serum Creatinine'
),

sepsis_admissions AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE di.icd_code LIKE '995.92'  -- Sepsis ICD-9 code
     OR di.icd_code LIKE 'S sepsis'  -- Sepsis ICD-10 code
)

SELECT 
  MAX(le.valuenum) AS max_serum_creatinine
FROM 
  sepsis_admissions sa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON sa.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON sa.subject_id = p.subject_id
  JOIN serum_creatinine_itemid sci 
    ON le.itemid = sci.itemid
WHERE 
  p.gender = 'M'
  AND p.anchor_age >= 80;