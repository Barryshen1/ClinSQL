WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admission_type,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    adm.discharge_location,
    -- Calculate LOS in days (fractional)
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR)/24.0 AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 67 AND 77
    AND adm.admission_type = 'SURGICAL'
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)

, labeled AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital mortality'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Discharged home'
      WHEN LOWER(discharge_location) LIKE '%snf%'
        OR LOWER(discharge_location) LIKE '%rehab%'
        OR LOWER(discharge_location) LIKE '%skilled nursing%'
        OR LOWER(discharge_location) LIKE '%nursing home%'
        OR LOWER(discharge_location) LIKE '%long term care%'
        OR LOWER(discharge_location) LIKE '%facility%'
        OR LOWER(discharge_location) LIKE '%icf%'
        OR LOWER(discharge_location) LIKE '%inpatient rehab%'
        THEN 'Discharged to facility'
      ELSE NULL
    END AS group_label
  FROM cohort
  WHERE los >= 0
)

SELECT
  group_label AS discharge_group,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los), 2) AS mean_los_days,
  ROUND(STDDEV(los), 2) AS sd_los_days,
  ROUND(100.0 * SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_los_le_7_days
FROM labeled
WHERE group_label IS NOT NULL
GROUP BY group_label
ORDER BY
  CASE
    WHEN group_label = 'Discharged home' THEN 1
    WHEN group_label = 'Discharged to facility' THEN 2
    WHEN group_label = 'In-hospital mortality' THEN 3
    ELSE 4
  END;