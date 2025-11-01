WITH filtered_admissions AS (
  SELECT a.hadm_id, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 80 AND 90
  AND a.admission_location = 'EMERGENCY ROOM ADMIT'
)
SELECT COUNT(DISTINCT fa.hadm_id)
FROM filtered_admissions fa
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
ON fa.hadm_id = di.hadm_id
WHERE di.seq_num = 1  
AND (
  (di.icd_version = 9 AND di.icd_code LIKE '730%')
  OR (di.icd_version = 10 AND di.icd_code LIKE 'M86%')
);