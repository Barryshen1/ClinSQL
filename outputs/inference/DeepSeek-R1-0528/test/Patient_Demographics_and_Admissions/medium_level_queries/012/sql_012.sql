WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.discharge_location,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Define discharge categories
    CASE
      WHEN adm.hospital_expire_flag = 1 THEN 'Death'
      WHEN adm.discharge_location = 'HOME' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 75 AND 85
)

SELECT
  discharge_category,
  COUNT(*) AS total_admissions,
  -- Proportion with LOS >=7 days (rounded to 4 decimals)
  ROUND(COUNTIF(los_days >= 7) / COUNT(*), 4) AS proportion_los_ge_7,
  -- Percentile rank of 7-day LOS (rounded to 2 decimals)
  ROUND(COUNTIF(los_days <= 7) * 100.0 / COUNT(*), 2) AS percentile_rank_7
FROM cohort
GROUP BY discharge_category
ORDER BY discharge_category;