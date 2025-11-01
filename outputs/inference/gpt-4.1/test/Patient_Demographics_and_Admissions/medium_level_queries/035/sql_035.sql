WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    adm.discharge_location,
    pat.gender,
    pat.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 43 AND 53
    AND LOWER(adm.admission_location) LIKE '%ed%'
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
),
los_calc AS (
  SELECT
    *,
    CAST(TIMESTAMP_DIFF(dischtime, admittime, DAY) AS FLOAT64) AS los_days
  FROM cohort
),
outcome_class AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(discharge_location) LIKE '%snf%'
        OR LOWER(discharge_location) LIKE '%rehab%'
        OR LOWER(discharge_location) LIKE '%nursing%'
        OR LOWER(discharge_location) LIKE '%skilled%'
        OR LOWER(discharge_location) LIKE '%facility%'
        OR LOWER(discharge_location) LIKE '%hospice%'
        THEN 'Facility'
      ELSE 'Other'
    END AS discharge_outcome
  FROM los_calc
)
SELECT
  discharge_outcome,
  APPROX_QUANTILES(los_days, 100)[50] AS median_los,
  APPROX_QUANTILES(los_days, 100)[25] AS los_iqr_25,
  APPROX_QUANTILES(los_days, 100)[75] AS los_iqr_75,
  ROUND(100 * SUM(CASE WHEN los_days <= 14 THEN 1 ELSE 0 END) / COUNT(*), 1) AS percentile_14d
FROM outcome_class
WHERE discharge_outcome IN ('Home', 'Facility', 'Death')
GROUP BY discharge_outcome
ORDER BY discharge_outcome;