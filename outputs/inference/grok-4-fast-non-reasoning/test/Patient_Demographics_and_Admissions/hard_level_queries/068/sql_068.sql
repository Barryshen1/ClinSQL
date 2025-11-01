WITH dehydration_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 'ICD-10' AND STARTS_WITH(icd_code, 'E86'))
     OR (icd_version = 'ICD-9' AND icd_code = '2765')
)

SELECT COUNT(DISTINCT a.hadm_id) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
INNER JOIN dehydration_codes dc
  ON d.icd_code = dc.icd_code
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 43 AND 53
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'SNF'
  AND d.seq_num = 1
  AND a.hospital_expire_flag = 0
  AND ((d.icd_version = 9 AND d.icd_code = '2765') OR (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'E86')));