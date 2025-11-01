WITH cohort AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    p.gender,
    p.anchor_age,
    a.discharge_location,
    a.hospital_expire_flag,
    ie.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ie.hadm_id = a.hadm_id
    AND ie.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
)
, categorized AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    los,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN UPPER(discharge_location) LIKE 'HOME%' THEN 'Home'
      ELSE 'Facility'
    END AS disposition
  FROM cohort
)
SELECT
  disposition,
  COUNT(*) AS n,
  ROUND(AVG(los), 2) AS mean_los_days,
  ROUND(STDDEV_SAMP(los), 2) AS sd_los_days,
  ROUND(100 * COUNTIF(los < 10) / COUNT(*), 1) AS pct_los_lt_10d
FROM categorized
GROUP BY disposition
ORDER BY disposition;