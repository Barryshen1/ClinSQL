SELECT COUNT(DISTINCT a.hadm_id) AS total_admissions
FROM physionet-data.mimiciv_3_1_hosp.admissions a
JOIN physionet-data.mimiciv_3_1_hosp.patients p
  ON a.subject_id = p.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
  ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
WHERE p.gender = 'F'
  AND a.hospital_expire_flag = 0
  AND a.insurance = 'Medicare'
  AND a.admission_location LIKE '%EMER%'
  AND d.seq_num = 1
  AND LOWER(dd.long_title) LIKE '%acute pancreatitis%'
  AND (
    p.anchor_age + 
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year
  ) BETWEEN 72 AND 82;