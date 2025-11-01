WITH pneumonia_icd_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10
    AND (
      icd_code LIKE 'J12%' OR
      icd_code LIKE 'J13%' OR
      icd_code LIKE 'J14%' OR
      icd_code LIKE 'J15%' OR
      icd_code LIKE 'J16%' OR
      icd_code LIKE 'J17%' OR
      icd_code LIKE 'J18%'
    )
)

SELECT COUNT(DISTINCT a.hadm_id) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
JOIN pneumonia_icd_codes pic
  ON d.icd_code = pic.icd_code
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 79 AND 89
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'EMERGENCY DEPARTMENT'
  AND d.seq_num = 1  -- Principal diagnosis
;