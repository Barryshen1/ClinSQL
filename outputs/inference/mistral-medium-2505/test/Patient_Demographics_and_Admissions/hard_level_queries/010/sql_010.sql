WITH dka_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%diabetic ketoacidosis%'
     OR icd_code IN ('250.10', '250.11', '250.12', '250.13',
                     'E10.10', 'E10.11', 'E11.10', 'E11.11',
                     'E13.10', 'E13.11')
),

first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) as admission_rank
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.insurance = 'Medicare'
    AND (a.admission_location = 'EMERGENCY ROOM ADMIT'
         OR a.admission_type = 'EMERGENCY')
)

SELECT COUNT(DISTINCT fa.hadm_id) AS qualifying_admissions
FROM first_admissions fa
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON fa.hadm_id = di.hadm_id
JOIN dka_codes dc ON di.icd_code = dc.icd_code
WHERE
  fa.admission_rank = 1  -- Only first admission per patient
  AND di.seq_num = 1      -- Principal diagnosis
;