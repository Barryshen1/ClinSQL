SELECT
  MAX(le.valuenum) AS max_creatinine_first_24h
FROM
  physionet-data.mimiciv_3_1_hosp.patients p
JOIN
  physionet-data.mimiciv_3_1_hosp.admissions a
  ON p.subject_id = a.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  ON a.hadm_id = di.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
  ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
JOIN
  physionet-data.mimiciv_3_1_hosp.labevents le
  ON a.hadm_id = le.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_labitems dl
  ON le.itemid = dl.itemid
WHERE
  p.gender = 'M'
  AND dl.label = 'creatinine'
  AND dl.fluid = 'blood'
  AND le.valuenum IS NOT NULL
  AND le.charttime >= a.admittime
  AND le.charttime <= DATETIME_ADD(a.admittime, INTERVAL 24 HOUR)
  AND (
    (d.icd_version = 9 AND d.icd_code LIKE '428%')
    OR
    (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
  );