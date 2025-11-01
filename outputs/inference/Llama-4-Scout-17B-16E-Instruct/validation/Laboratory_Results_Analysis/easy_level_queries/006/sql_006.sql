WITH 
-- Identify serum sodium itemid
serum_sodium_itemid AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
  WHERE label LIKE '%Serum Sodium%'
),

-- Filter patients and extract nadir serum sodium levels
patients_nadir_sodium AS (
  SELECT 
    le.valuenum AS nadir_sodium
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON le.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      ON p.subject_id = di.subject_id
  WHERE 
    p.anchor_age = 50
    AND p.gender = 'F'
    AND di.icd_code LIKE '%COPD%'
    AND le.itemid IN (SELECT itemid FROM serum_sodium_itemid)
)

-- Calculate standard deviation of nadir serum sodium
SELECT 
  STDDEV(nadir_sodium) AS std_dev_nadir_sodium
FROM 
  patients_nadir_sodium;