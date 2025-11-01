SELECT
  p.subject_id,
  p.hadm_id,
  p.drug,
  p.starttime,
  p.stoptime,
  DATE_DIFF(DATE(p.stoptime), DATE(p.starttime), DAY) AS duration_days
FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON p.subject_id = pt.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.hadm_id = a.hadm_id
WHERE pt.gender = 'F'
  AND pt.anchor_age BETWEEN 38 AND 48
  AND p.hadm_id IS NOT NULL
  AND p.starttime IS NOT NULL
  AND p.stoptime IS NOT NULL
  AND p.starttime >= a.admittime
  AND p.starttime <= a.dischtime
  AND p.stoptime >= p.starttime
  AND REGEXP_CONTAINS(LOWER(COALESCE(p.drug, '')),
       r'\b(lisinopril|enalapril|captopril|ramipril|perindopril|benazepril|moexipril|fosinopril|quinapril|trandolapril|cilazapril)\b')
ORDER BY duration_days DESC
LIMIT 1;