SELECT
  MIN(le.valuenum) AS min_serum_troponin
FROM
  `physionet-data.mimiciv_3_1_hosp.labevents` AS le
JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
  ON le.itemid = dli.itemid
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  ON le.hadm_id = a.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  ON di.subject_id = a.subject_id
  AND di.hadm_id = a.hadm_id
WHERE
  p.gender = 'Male'
  -- ACS: ICD-10 I2x codes; ICD-9 410x/411x
  AND (
    (di.icd_version = 10 AND di.icd_code LIKE 'I2%')
    OR
    (di.icd_version = 9 AND (di.icd_code LIKE '410%' OR di.icd_code LIKE '411%'))
  )
  -- troponin laboratory measurements
  AND LOWER(dli.label) LIKE '%troponin%'
  AND le.valuenum IS NOT NULL;