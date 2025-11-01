WITH ugib_icd_codes AS (
  -- List of ICD codes for UGIB (ICD-9 and ICD-10)
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-9 codes for UGIB
    (icd_version = 9 AND (
      icd_code IN ('5780', '5781', '5789')
      OR LOWER(long_title) LIKE '%upper gastrointestinal%'
      OR LOWER(long_title) LIKE '%hematemesis%'
      OR LOWER(long_title) LIKE '%melena%'
      OR LOWER(long_title) LIKE '%gastric ulcer with hemorrhage%'
      OR LOWER(long_title) LIKE '%duodenal ulcer with hemorrhage%'
      OR LOWER(long_title) LIKE '%gastrojejunal ulcer with hemorrhage%'
      OR LOWER(long_title) LIKE '%dieulafoy%'
      OR LOWER(long_title) LIKE '%hemorrhagic gastritis%'
    ))
    OR
    -- ICD-10 codes for UGIB
    (icd_version = 10 AND (
      icd_code IN ('K920', 'K921', 'K250', 'K251', 'K252', 'K260', 'K261', 'K262', 'K280', 'K281', 'K282', 'K290', 'K226')
      OR LOWER(long_title) LIKE '%upper gastrointestinal%'
      OR LOWER(long_title) LIKE '%hematemesis%'
      OR LOWER(long_title) LIKE '%melena%'
      OR LOWER(long_title) LIKE '%gastric ulcer with hemorrhage%'
      OR LOWER(long_title) LIKE '%duodenal ulcer with hemorrhage%'
      OR LOWER(long_title) LIKE '%gastrojejunal ulcer with hemorrhage%'
      OR LOWER(long_title) LIKE '%dieulafoy%'
      OR LOWER(long_title) LIKE '%hemorrhagic gastritis%'
    ))
)
,
primary_ugib_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR)/24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
    JOIN ugib_icd_codes ugib
      ON diag.icd_code = ugib.icd_code AND diag.icd_version = ugib.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 84 AND 94
    AND diag.seq_num = 1 -- primary diagnosis
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
SELECT
  APPROX_QUANTILES(los_days, 4)[1] AS los_25th_percentile,
  APPROX_QUANTILES(los_days, 4)[3] AS los_75th_percentile,
  APPROX_QUANTILES(los_days, 4)[3] - APPROX_QUANTILES(los_days, 4)[1] AS los_iqr
FROM
  primary_ugib_admissions
;