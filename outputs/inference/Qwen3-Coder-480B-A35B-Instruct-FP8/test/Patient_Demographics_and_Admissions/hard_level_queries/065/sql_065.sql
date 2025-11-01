SELECT COUNT(DISTINCT a.hadm_id) AS total_admissions
FROM physionet-data.mimiciv_3_1_hosp.admissions a
JOIN physionet-data.mimiciv_3_1_hosp.patients p
  ON a.subject_id = p.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
  ON d.icd_code = dd.icd_code
  AND d.icd_version = dd.icd_version
WHERE
  p.gender = 'M'
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'TRANSFER FROM HOSPITAL'
  AND d.seq_num = 1
  AND dd.long_title = 'Unstable angina'
  AND a.dischtime IS NOT NULL
  AND (
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 72 AND 82
  );