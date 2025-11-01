WITH relevant_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 78 AND 88
),
pacemaker_icd_procedures AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE (icd_version = 9 AND long_title LIKE '%PACEMAKER%' OR long_title LIKE '%ICD%')
  OR (icd_version = 10 AND (long_title LIKE '%PACEMAKER%' OR long_title LIKE '%CARDIOVERTER%' OR long_title LIKE '%DEFIBRILLATOR%'))
),
patient_procedures AS (
  SELECT p.subject_id, COUNT(DISTINCT pi.icd_code) as num_procedures
  FROM relevant_patients p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi ON p.subject_id = pi.subject_id
  JOIN pacemaker_icd_procedures pip ON pi.icd_code = pip.icd_code AND pi.icd_version = pip.icd_version
  GROUP BY p.subject_id
)
SELECT 
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS percentile_25
FROM patient_procedures;