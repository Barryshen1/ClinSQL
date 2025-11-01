SELECT COUNT(*) AS total_index_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON d.icd_code = dd.icd_code
  AND d.icd_version = dd.icd_version
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 38 AND 48
  AND a.insurance = 'Medicare'
  AND LOWER(a.admission_location) LIKE '%emergency%'
  AND d.seq_num = 1
  AND LOWER(dd.long_title) LIKE '%acute cholecystitis%';