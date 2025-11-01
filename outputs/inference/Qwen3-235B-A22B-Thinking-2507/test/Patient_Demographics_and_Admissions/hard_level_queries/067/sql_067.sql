SELECT COUNT(*) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON a.hadm_id = diag.hadm_id
  AND diag.seq_num = 1  -- Principal diagnosis only
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
  ON diag.icd_code = d_icd.icd_code
  AND diag.icd_version = d_icd.icd_version
WHERE
  p.gender = 'F'
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'EMERGENCY ROOM'
  AND a.dischtime IS NOT NULL
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
  AND (
    LOWER(d_icd.long_title) LIKE '%bowel obstruction%'
    OR LOWER(d_icd.long_title) LIKE '%intestinal obstruction%'
  );