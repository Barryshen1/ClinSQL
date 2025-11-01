WITH upper_gi_bleed_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Calculate LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    -- Males aged 74-84
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    -- Primary diagnosis (seq_num = 1) of upper GI bleed
    AND d.seq_num = 1
    AND d.icd_code IN (
      'K25', 'K26', 'K27', 'K28',  -- Gastric/duodenal ulcers
      'K920', 'K921', 'K922'       -- GI hemorrhage
    )
    -- Ensure valid discharge time
    AND a.dischtime IS NOT NULL
)

SELECT
  PERCENTILE_CONT(los_days, 0.25) OVER() AS percentile_25_los
FROM
  upper_gi_bleed_admissions
LIMIT 1;