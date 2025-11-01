WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    adm.admission_location,
    adm.discharge_location,
    -- Calculate LOS in days
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 43 AND 53
    AND (
      LOWER(adm.admission_location) LIKE '%hosp%'
      OR LOWER(adm.admission_location) LIKE '%hospital%'
      OR LOWER(adm.admission_location) LIKE '%facility%'
    )
    -- Exclude missing/invalid LOS
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) >= 0
)

, discharge_groups AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(discharge_location) LIKE '%facility%'
        OR LOWER(discharge_location) LIKE '%snf%'
        OR LOWER(discharge_location) LIKE '%rehab%'
        OR LOWER(discharge_location) LIKE '%nursing%' THEN 'Facility'
      ELSE 'Other'
    END AS discharge_group
  FROM cohort
)

SELECT
  discharge_group,
  COUNT(*) AS n_admissions,
  APPROX_QUANTILES(los, 100)[50] AS median_los,
  APPROX_QUANTILES(los, 100)[25] AS los_25th,
  APPROX_QUANTILES(los, 100)[75] AS los_75th,
  ROUND(100 * SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) / COUNT(*), 1) AS percent_los_le_10
FROM
  discharge_groups
WHERE
  discharge_group IN ('Home', 'Facility', 'Death')
GROUP BY
  discharge_group
ORDER BY
  discharge_group;