WITH copd_primary_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  -- Only primary diagnosis
  WHERE
    d.seq_num = 1
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- COPD exacerbation ICD codes
    AND (
      (d.icd_version = 10 AND d.icd_code = 'J44.1')
      OR (d.icd_version = 9 AND d.icd_code = '49121')
    )
)

SELECT
  PERCENTILE_CONT(los_days, 0.25) OVER () AS los_25th_percentile_days
FROM
  copd_primary_admissions
;