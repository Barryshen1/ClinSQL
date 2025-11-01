WITH 
-- Identify serum creatinine itemid
creatinine_itemid AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
  WHERE label LIKE '%Creatinine%'
),

-- Find nadir serum creatinine for each hospital stay for males with pneumonia
nadir_creatinine AS (
  SELECT 
    a.hadm_id,
    MIN(le.valuenum) AS nadir_creatinine
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le 
      ON a.hadm_id = le.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      ON a.hadm_id = di.hadm_id
  WHERE 
    p.gender = 'M'
    AND le.itemid IN (SELECT itemid FROM creatinine_itemid)
    AND di.icd_code LIKE '%Pneumonia%'
  GROUP BY 
    a.hadm_id
)

-- Calculate the interquartile range (IQR) of nadir creatinine
SELECT 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY nadir_creatinine) AS Q1,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY nadir_creatinine) AS Q3,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY nadir_creatinine) - 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY nadir_creatinine) AS IQR
FROM 
  nadir_creatinine;