WITH cohort AS (
  SELECT
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients pat
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions adm
  ON
    pat.subject_id = adm.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 75 AND 85
    AND LOWER(adm.admission_type) LIKE '%transfer%'
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
    AND adm.admittime <= adm.dischtime
    AND (
      LOWER(adm.discharge_location) IN (
        'home', 'home with home health', 'home health care'
      )
      OR LOWER(adm.discharge_location) LIKE '%hospice%'
      OR adm.hospital_expire_flag = 1
    )
),
summary AS (
  SELECT
    COUNT(*) AS total_count,
    COUNTIF(los_days >= 7) AS count_los_ge_7,
    APPROX_QUANTILES(los_days, 100)[OFFSET(7)] AS los_7th_percentile_days
  FROM cohort
)
SELECT
  SAFE_DIVIDE(count_los_ge_7, total_count) AS proportion_los_ge_7_days,
  los_7th_percentile_days
FROM summary
LIMIT 1;