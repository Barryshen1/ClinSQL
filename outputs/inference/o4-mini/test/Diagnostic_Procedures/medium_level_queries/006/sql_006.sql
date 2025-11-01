WITH sepsis_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
     AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND LOWER(dd.long_title) LIKE '%sepsis%'
    AND LOWER(dd.long_title) NOT LIKE '%shock%'
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
),
icu_flag AS (
  SELECT
    hadm_id,
    'ICU' AS icu_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
ultrasound_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS us_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE
    LOWER(short_description) LIKE '%ultrasound%'
  GROUP BY hadm_id
),
admission_metrics AS (
  SELECT
    sa.subject_id,
    sa.hadm_id,
    -- LOS in days
    TIMESTAMP_DIFF(sa.dischtime, sa.admittime, DAY) AS los_days,
    -- LOS bin
    CASE
      WHEN TIMESTAMP_DIFF(sa.dischtime, sa.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN TIMESTAMP_DIFF(sa.dischtime, sa.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8'
      ELSE NULL
    END AS los_bin,
    -- ICU vs No ICU
    COALESCE(ic.icu_flag, 'No ICU') AS icu_flag,
    -- Ultrasound count (0 if none)
    COALESCE(us.us_count, 0) AS us_count
  FROM
    sepsis_admissions sa
    LEFT JOIN icu_flag ic
      ON sa.hadm_id = ic.hadm_id
    LEFT JOIN ultrasound_counts us
      ON sa.hadm_id = us.hadm_id
)
SELECT
  icu_flag,
  los_bin,
  COUNT(*) AS num_admissions,
  ROUND(AVG(us_count), 3) AS mean_ultrasounds_per_admission
FROM
  admission_metrics
WHERE
  los_bin IS NOT NULL
GROUP BY
  icu_flag,
  los_bin
ORDER BY
  icu_flag,
  los_bin;