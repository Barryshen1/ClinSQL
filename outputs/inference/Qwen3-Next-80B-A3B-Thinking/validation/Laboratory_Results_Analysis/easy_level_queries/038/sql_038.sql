SELECT MIN(l.valuenum) AS min_hemoglobin
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON a.hadm_id = l.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON l.itemid = di.itemid
WHERE p.gender = 'M'
  AND p.anchor_age = 50
  AND (
    (d.icd_version = 9 AND (d.icd_code LIKE '433%' OR d.icd_code LIKE '434%'))
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
  )
  AND di.label LIKE '%hemoglobin%'
  AND l.charttime >= a.admittime
  AND l.charttime <= a.admittime + INTERVAL '24' HOUR
  AND l.valuenum IS NOT NULL;