SELECT MIN(l.valuenum) AS min_troponin
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON a.hadm_id = l.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
WHERE p.gender = 'M'
  AND (
    (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code = '411.1'))
    OR
    (d.icd_version = 10 AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%'))
  )
  AND dl.label LIKE '%troponin%'
  AND l.charttime BETWEEN a.admittime AND a.dischtime;