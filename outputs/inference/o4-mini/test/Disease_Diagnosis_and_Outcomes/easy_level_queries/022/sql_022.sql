WITH female_stroke_admissions AS (
  SELECT
    a.hadm_id,
    -- Compute LOS in days (including fractional) by taking seconds difference and dividing by 86400
    TIMESTAMP_DIFF(
      CAST(a.dischtime AS TIMESTAMP),
      CAST(a.admittime AS TIMESTAMP),
      SECOND
    ) / 86400.0 AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
     AND a.hadm_id   = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND d.seq_num = 1
    -- ICD‐10 codes for cerebral infarction (ischemic stroke)
    AND d.icd_version = 10
    AND d.icd_code LIKE 'I63%'
)

SELECT
  -- 25th percentile at OFFSET(1), 75th percentile at OFFSET(3)
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS los_iqr_days
FROM (
  SELECT
    APPROX_QUANTILES(los, 4) AS quantiles
  FROM
    female_stroke_admissions
);