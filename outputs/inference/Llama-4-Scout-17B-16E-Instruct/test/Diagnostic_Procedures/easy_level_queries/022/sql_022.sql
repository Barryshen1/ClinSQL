WITH eligible_patients AS (
  SELECT subject_id, anchor_age, gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 82 AND 92
),
pacemaker_icd_procedures AS (
  SELECT p.subject_id, a.hadm_id, p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN eligible_patients e ON p.subject_id = e.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.hadm_id = a.hadm_id
  WHERE p.icd_code IN ('37.86', '37.87', '0.05', '0.06')  -- Example codes for pacemaker/ICD
)
SELECT hadm_id, COUNT(DISTINCT icd_code) AS num_distinct_procedures
FROM pacemaker_icd_procedures
GROUP BY hadm_id
HAVING COUNT(DISTINCT icd_code) > 0
ORDER BY num_distinct_procedures ASC
LIMIT 1;