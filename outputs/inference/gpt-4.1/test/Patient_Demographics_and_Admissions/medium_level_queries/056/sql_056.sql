WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pat.gender,
    pat.anchor_age,
    adm.admission_location,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 67 AND 77
    AND LOWER(adm.admission_location) LIKE '%emergency department%'
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
, stats AS (
  SELECT
    hospital_expire_flag,
    COUNT(*) AS n_admissions,
    COUNTIF(los_days >= 7) / COUNT(*) AS prop_LOS_7plus,
    COUNTIF(los_days >= 14) / COUNT(*) AS prop_LOS_14plus,
    -- Percentile rank for 10-day LOS: proportion of admissions with LOS <= 10
    COUNTIF(los_days <= 10) / COUNT(*) AS percentile_10day_LOS
  FROM
    cohort
  GROUP BY
    hospital_expire_flag
)
SELECT
  CASE hospital_expire_flag
    WHEN 0 THEN 'Alive'
    WHEN 1 THEN 'Died'
    ELSE 'Unknown'
  END AS discharge_status,
  n_admissions,
  prop_LOS_7plus,
  prop_LOS_14plus,
  percentile_10day_LOS
FROM
  stats
ORDER BY
  hospital_expire_flag;