SELECT DISTINCT PERCENTILE_CONT(l.valuenum, 0.75) OVER() AS p75_serum_glucose
FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON l.hadm_id = a.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
WHERE p.gender = 'M'
  AND LOWER(did.long_title) LIKE '%pneumonia%'
  AND LOWER(d.label) LIKE '%glucose%'
  AND l.valuenum IS NOT NULL
  AND l.charttime >= TIMESTAMP_SUB(a.dischtime, INTERVAL 24 HOUR)
  AND l.charttime <= a.dischtime;