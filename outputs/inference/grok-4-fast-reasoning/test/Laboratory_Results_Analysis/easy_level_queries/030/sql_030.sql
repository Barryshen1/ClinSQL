SELECT MIN(le.valuenum) AS min_troponin
FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
  ON le.itemid = dli.itemid
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON le.subject_id = a.subject_id AND le.hadm_id = a.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
WHERE p.gender = 'M'
  AND LOWER(dli.label) LIKE '%troponin%'
  AND le.valuenum IS NOT NULL
  AND le.charttime BETWEEN a.admittime AND a.dischtime
  AND (
    (di.icd_version = 9 AND (di.icd_code LIKE '410%' OR di.icd_code = '4111'))
    OR
    (di.icd_version = 10 AND (di.icd_code = 'I20.0' OR di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
  );