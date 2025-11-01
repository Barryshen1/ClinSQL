WITH cohort_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  WHERE UPPER(p.gender) = 'F'
    AND p.anchor_age BETWEEN 72 AND 82
    AND UPPER(a.insurance) LIKE '%MEDICARE%'
    AND a.admission_type = 'EMERGENCY'
    AND a.dischtime IS NOT NULL
    -- ensure the admission ended in discharge (not in-hospital death)
    AND a.hospital_expire_flag = 0
    AND di.seq_num = 1
    AND (di.icd_code LIKE '577%' OR di.icd_code LIKE 'K85%')
)
SELECT COUNT(*) AS total_admissions
FROM cohort_admissions;