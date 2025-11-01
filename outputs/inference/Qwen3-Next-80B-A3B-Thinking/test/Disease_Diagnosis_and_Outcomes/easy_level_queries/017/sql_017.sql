SELECT MAX(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS max_los
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
WHERE p.gender = 'M'
  AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 84 AND 94
  AND d.seq_num = 1
  AND d.icd_code LIKE 'I63%';