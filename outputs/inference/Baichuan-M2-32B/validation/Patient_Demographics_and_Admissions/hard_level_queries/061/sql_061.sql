SELECT COUNT(DISTINCT a.hadm_id) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id AND p.subject_id = d.subject_id
WHERE 
  p.gender = 'F'
  AND a.insurance = 'Medicare'
  AND a.admission_location LIKE '%Transfer from another hospital%'
  AND d.seq_num = 1
  AND (
    (d.icd_version = 10 AND d.icd_code = 'I48') 
    OR 
    (d.icd_version = 9 AND d.icd_code LIKE '427.3%')
  )
  AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 63 AND 73
  AND p.anchor_year IS NOT NULL
  AND p.anchor_age IS NOT NULL
  AND a.admittime IS NOT NULL;