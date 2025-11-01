SELECT AVG(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS avg_los
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
WHERE p.gender = 'F'
  AND d.seq_num = 1
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 61 AND 71
  AND LOWER(di.long_title) LIKE '%heart failure%';