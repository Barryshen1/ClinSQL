WITH aki_icd_codes AS (
  -- List all ICD codes for AKI (ICD-9 and ICD-10)
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-10: N17* (N17, N170, N171, N172, N178, N179)
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^N17'))
    OR
    -- ICD-9: 584* (584, 5845, 5846, 5847, 5848, 5849)
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^584'))
),
aki_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
      AND diag.seq_num = 1 -- primary diagnosis
    INNER JOIN aki_icd_codes icd
      ON diag.icd_code = icd.icd_code
      AND diag.icd_version = icd.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 81 AND 91
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) > 0
)
SELECT
  APPROX_QUANTILES(los, 4)[1] AS los_25th_percentile,
  APPROX_QUANTILES(los, 4)[3] AS los_75th_percentile,
  (APPROX_QUANTILES(los, 4)[3] - APPROX_QUANTILES(los, 4)[1]) AS los_iqr
FROM aki_admissions
;