WITH dka_hhs_admissions AS (
  -- Get admissions with primary DKA/HHS diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    -- Males aged 73-83
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    -- Primary DKA/HHS diagnosis (seq_num = 1)
    AND d.seq_num = 1
    AND d.icd_code IN (
      'E13.10', 'E13.11', 'E11.10', 'E11.11',  -- DKA
      'E13.00', 'E11.00'                         -- HHS
    )
    -- Ensure valid discharge time
    AND a.dischtime IS NOT NULL
)

SELECT
  PERCENTILE_CONT(los_days, 0.25) OVER() AS percentile_25_los_days
FROM
  dka_hhs_admissions
LIMIT 1;