WITH sepsis_admissions AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code IN ('99591', '99592')) OR
    (icd_version = 10 AND icd_code IN ('R6520', 'R6521'))
),
index_creat AS (
  SELECT 
    l.subject_id, 
    l.hadm_id, 
    MIN(l.charttime) AS first_charttime,
    l.valuenum AS creat_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN sepsis_admissions s 
    ON l.hadm_id = s.hadm_id
  WHERE l.itemid = 50912  -- serum creatinine
  GROUP BY l.subject_id, l.hadm_id, l.valuenum
)
SELECT MAX(creat_value) AS max_index_creatinine
FROM index_creat ic
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON ic.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
  ON ic.hadm_id = a.hadm_id
WHERE 
  p.gender = 'M' 
  AND p.anchor_age = 83;