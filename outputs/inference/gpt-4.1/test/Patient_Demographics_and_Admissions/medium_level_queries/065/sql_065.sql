WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
),
non_icu AS (
  SELECT
    c.*
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON c.hadm_id = i.hadm_id
  WHERE
    i.hadm_id IS NULL
),
disposition_map AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
      WHEN UPPER(discharge_location) LIKE '%HOSPICE%' THEN 'Discharged to Hospice'
      WHEN UPPER(discharge_location) LIKE '%HOME%' THEN 'Discharged Home'
      ELSE NULL
    END AS disposition,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days
  FROM
    non_icu
)
SELECT
  disposition,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV_SAMP(los_days), 2) AS sd_los_days
FROM
  disposition_map
WHERE
  disposition IS NOT NULL
GROUP BY
  disposition
ORDER BY
  disposition;