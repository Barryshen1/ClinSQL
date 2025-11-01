SELECT COUNT(DISTINCT a.hadm_id) AS index_admission_count
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id AND d.seq_num = 1
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
WHERE p.gender = 'F'
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'EMERGENCY ROOM'
  AND a.dischtime IS NOT NULL
  AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 68 AND 78
  AND LOWER(dd.long_title) LIKE '%hemorrhagic%'
  AND LOWER(dd.long_title) LIKE '%stroke%';