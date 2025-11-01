WITH target_patients AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
),
target_admissions AS (
  SELECT DISTINCT tp.subject_id, tp.hadm_id
  FROM target_patients tp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON tp.hadm_id = d.hadm_id
  WHERE 
    -- Chest pain codes
    (d.icd_version = 9 AND d.icd_code LIKE '7865%') OR
    (d.icd_version = 10 AND d.icd_code LIKE 'R07%') OR
    -- AMI codes
    (d.icd_version = 9 AND d.icd_code LIKE '410%') OR
    (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
),
first_troponin AS (
  SELECT 
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    l.charttime,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN target_admissions a 
    ON l.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d 
    ON l.itemid = d.itemid
  WHERE d.loinc_code = '6598-7'  -- High-sensitivity troponin T
    AND l.valuenum IS NOT NULL
)
SELECT 
  CASE 
    WHEN valuenum < 14 THEN 'Normal (<14 ng/L)'
    WHEN valuenum BETWEEN 14 AND 19 THEN 'Borderline (14-19 ng/L)'
    WHEN valuenum >= 20 THEN 'Myocardial injury (>=20 ng/L)'
  END AS category,
  COUNT(*) AS count
FROM first_troponin
WHERE rn = 1
GROUP BY category
ORDER BY category;