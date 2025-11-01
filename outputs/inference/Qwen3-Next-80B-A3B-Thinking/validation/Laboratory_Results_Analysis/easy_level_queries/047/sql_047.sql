SELECT MAX(lab.valuenum) AS max_creatinine
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab ON a.subject_id = lab.subject_id AND a.hadm_id = lab.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d_lab ON lab.itemid = d_lab.itemid
WHERE p.gender = 'M'
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) = 66
  AND LOWER(d_icd.long_title) LIKE '%heart failure%'
  AND LOWER(d_lab.label) LIKE '%creatinine%'
  AND lab.charttime >= a.admittime
  AND lab.charttime <= a.admittime + INTERVAL 24 HOUR
  AND lab.valuenum IS NOT NULL;