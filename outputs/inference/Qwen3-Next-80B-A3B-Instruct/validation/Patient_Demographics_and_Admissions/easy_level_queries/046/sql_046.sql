WITH first_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM 
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),
dapt_admissions AS (
  SELECT DISTINCT
    p1.hadm_id
  FROM 
    physionet-data.mimiciv_3_1_hosp.prescriptions p1
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.prescriptions p2
    ON p1.hadm_id = p2.hadm_id
  WHERE 
    LOWER(p1.drug) LIKE '%aspirin%' 
    OR LOWER(p1.drug) LIKE '%acetylsalicylic acid%'
    OR LOWER(p1.drug) LIKE '%asa%'
  AND 
    (LOWER(p2.drug) LIKE '%clopidogrel%'
     OR LOWER(p2.drug) LIKE '%ticagrelor%'
     OR LOWER(p2.drug) LIKE '%prasugrel%')
)
SELECT 
  STDDEV_POP(f.hospital_expire_flag) AS sd_inhospital_mortality
FROM 
  first_admissions f
INNER JOIN 
  dapt_admissions d
  ON f.hadm_id = d.hadm_id
WHERE 
  f.rn = 1;