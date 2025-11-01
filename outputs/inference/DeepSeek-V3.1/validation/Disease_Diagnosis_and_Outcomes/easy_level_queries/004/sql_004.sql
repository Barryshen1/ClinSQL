WITH dka_hhs_admissions AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    pat.anchor_age,
    pat.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id AND adm.subject_id = diag.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 73 AND 83
    AND diag.seq_num = 1  -- primary diagnosis
    AND (
      -- DKA codes
      diag.icd_code IN ('E1010', 'E1011', 'E1110', 'E1111', 'E1310', 'E1311')
      OR
      -- HHS codes
      diag.icd_code IN ('E1100', 'E1101', 'E1300', 'E1301')
    )
    AND adm.dischtime IS NOT NULL  -- exclude ongoing admissions
)
SELECT 
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS los_25th_percentile
FROM dka_hhs_admissions;