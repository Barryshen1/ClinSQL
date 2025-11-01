SELECT COUNT(DISTINCT a.hadm_id) AS completed_admissions_count
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 43 AND 53
  AND a.insurance LIKE '%Medicare%'
  AND a.admission_location LIKE '%EMERGENCY%'
  AND d.seq_num = 1
  AND LOWER(di.long_title) LIKE '%bowel obstruction%'
  AND a.dischtime IS NOT NULL;