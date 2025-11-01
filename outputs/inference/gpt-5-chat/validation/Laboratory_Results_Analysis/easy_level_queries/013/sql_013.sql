WITH female_copd_hadm AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON di.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND UPPER(dd.long_title) LIKE '%CHRONIC OBSTRUCTIVE PULMONARY DISEASE%'
),
creatinine_labs AS (
  SELECT le.subject_id, le.hadm_id, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE UPPER(dli.label) LIKE '%CREATININE%'
    AND UPPER(dli.fluid) = 'BLOOD'
    AND UPPER(le.valueuom) = 'MG/DL'
    AND le.valuenum IS NOT NULL
)
SELECT MAX(valuenum) AS max_peak_serum_creatinine_mg_dl
FROM creatinine_labs cl
JOIN female_copd_hadm fc
  ON cl.subject_id = fc.subject_id
  AND cl.hadm_id = fc.hadm_id
;