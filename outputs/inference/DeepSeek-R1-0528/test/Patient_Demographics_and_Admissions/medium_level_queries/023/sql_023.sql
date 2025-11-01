WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.discharge_location,
    adm.hospital_expire_flag,
    DATE_DIFF(CAST(adm.dischtime AS DATE), CAST(adm.admittime AS DATE), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 41 AND 51
)

SELECT
  discharge_category,
  COUNT(*) AS total_admissions,
  COUNTIF(los_days >= 7) AS count_los_ge_7,
  COUNTIF(los_days >= 7) / COUNT(*) AS proportion_los_ge_7,
  COUNTIF(los_days <= 10) AS count_los_le_10,
  COUNTIF(los_days <= 10) / COUNT(*) * 100 AS percentile_rank_10_day
FROM (
  SELECT *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Death'
      WHEN discharge_location LIKE 'HOME%' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_category
  FROM cohort
)
GROUP BY discharge_category
ORDER BY discharge_category;