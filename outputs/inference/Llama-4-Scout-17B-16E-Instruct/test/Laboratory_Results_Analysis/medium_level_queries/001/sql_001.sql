WITH 
  target_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 40 AND 50
  ),
  
  ami_admissions AS (
    SELECT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    WHERE d.icd_code LIKE '410%'  
      AND a.subject_id IN (SELECT subject_id FROM target_patients)
  ),
  
  troponin_values AS (
    SELECT 
      a.hadm_id,
      l.valuenum
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON a.hadm_id = l.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
    WHERE a.hadm_id IN (SELECT hadm_id FROM ami_admissions)
      AND d.label LIKE '%Troponin%'
      AND l.charttime = (SELECT MIN(charttime) FROM `physionet-data.mimiciv_3_1_hosp.labevents` l2 WHERE l2.hadm_id = a.hadm_id AND l2.itemid = l.itemid)
  )

SELECT 
  COUNT(CASE WHEN valuenum < 0.01 THEN 1 END) AS normal_count,
  COUNT(CASE WHEN valuenum >= 0.01 AND valuenum <= 0.1 THEN 1 END) AS borderline_count,
  COUNT(CASE WHEN valuenum > 0.1 THEN 1 END) AS elevated_count
FROM troponin_values;