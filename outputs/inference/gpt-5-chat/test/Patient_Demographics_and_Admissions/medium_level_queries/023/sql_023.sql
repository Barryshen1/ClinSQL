WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admission_location,
    adm.discharge_location,
    adm.hospital_expire_flag,
    adm.admittime,
    adm.dischtime,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 41 AND 51
    AND adm.admission_location LIKE 'EMERGENCY%'
    AND adm.dischtime IS NOT NULL
),
categorized AS (
  SELECT
    subject_id,
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Death'
      WHEN discharge_location LIKE 'HOME%' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_category
  FROM cohort
)
SELECT
  discharge_category,
  COUNT(*) AS total_admissions,
  COUNTIF(los_days >= 7) / COUNT(*) AS proportion_los_ge_7,
  COUNTIF(los_days <= 10) / COUNT(*) AS percentile_rank_10day
FROM categorized
GROUP BY discharge_category
ORDER BY discharge_category;