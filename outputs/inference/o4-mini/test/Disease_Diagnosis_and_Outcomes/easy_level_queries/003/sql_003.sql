WITH cohort AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    -- Compute fractional hospital LOS in days
    SAFE_DIVIDE(
      TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR),
      24.0
    ) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND d.seq_num = 1
    AND d.icd_version = 9
    AND SUBSTR(d.icd_code, 1, 3) IN ('410', '411', '412', '413', '414')
    -- Exclude any missing or zero-length stays
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) > 0
)
SELECT
  -- Approximate 25th percentile of LOS
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS los_25th_percentile_days
FROM
  cohort;