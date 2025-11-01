WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    a.deathtime,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
      WHEN LOWER(a.discharge_location) LIKE '%hospice%' THEN 'Discharged to Hospice'
      WHEN LOWER(a.discharge_location) LIKE 'home%' THEN 'Discharged Home'
      ELSE NULL
    END AS discharge_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON a.subject_id = icu.subject_id AND a.hadm_id = icu.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND icu.stay_id IS NULL
)
SELECT
  discharge_group,
  AVG(los_days) AS mean_los_days,
  STDDEV_POP(los_days) AS sd_los_days
FROM base
WHERE discharge_group IS NOT NULL
GROUP BY discharge_group
ORDER BY discharge_group;