WITH non_icu_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE i.hadm_id IS NULL -- exclude ICU admissions
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
eligible_patients AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
)
SELECT
  CASE
    WHEN LOWER(na.discharge_location) LIKE '%home%' THEN 'Discharged Home'
    WHEN LOWER(na.discharge_location) LIKE '%hospice%' THEN 'Discharged to Hospice'
    WHEN na.hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
    ELSE 'Other'
  END AS outcome_group,
  ROUND(AVG(TIMESTAMP_DIFF(na.dischtime, na.admittime, MINUTE) / 1440), 2) AS mean_los_days,
  ROUND(STDDEV(TIMESTAMP_DIFF(na.dischtime, na.admittime, MINUTE) / 1440), 2) AS sd_los_days
FROM non_icu_admissions na
JOIN eligible_patients ep
  ON na.subject_id = ep.subject_id
WHERE LOWER(na.discharge_location) LIKE '%home%'
   OR LOWER(na.discharge_location) LIKE '%hospice%'
   OR na.hospital_expire_flag = 1
GROUP BY outcome_group
ORDER BY outcome_group;