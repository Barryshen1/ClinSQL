SELECT COUNT(a.hadm_id) AS total_admissions
FROM physionet-data.mimiciv_3_1_hosp.admissions a
JOIN physionet-data.mimiciv_3_1_hosp.patients p
  ON a.subject_id = p.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
  ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
WHERE p.gender = 'M'
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'TRANSFER FROM HOSP/OTHER'
  AND a.dischtime IS NOT NULL
  AND d.seq_num = 1
  AND LOWER(did.long_title) LIKE '%unstable angina%'
  AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 72 AND 82;