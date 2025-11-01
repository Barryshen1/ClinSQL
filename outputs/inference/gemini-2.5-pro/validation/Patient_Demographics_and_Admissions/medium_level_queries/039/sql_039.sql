WITH
  admissions_filtered AS (
    SELECT
      adm.hadm_id,
      (
        EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year
      ) + pat.anchor_age AS age_at_admission,
      DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
      CASE
        WHEN adm.hospital_expire_flag = 1
        THEN 'In-hospital Death'
        WHEN adm.discharge_location LIKE 'HOME%'
        THEN 'Home'
        WHEN adm.discharge_location IS NOT NULL
        THEN 'Facility'
        ELSE 'Other/Unknown'
      END AS discharge_group
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    WHERE
      pat.gender = 'F'
      AND adm.admission_type IN ('EMERGENCY', 'URGENT')
      AND adm.dischtime IS NOT NULL
  ),
  cohort AS (
    SELECT
      los_days,
      discharge_group
    FROM admissions_filtered
    WHERE
      age_at_admission BETWEEN 37 AND 47
      AND discharge_group IN ('Home', 'Facility', 'In-hospital Death')
  )
SELECT
  discharge_group,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS los_p25,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS los_p50,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_p75,
  -- Calculate the proportion of stays <= 7 days for the percentile rank
  COUNTIF(los_days <= 7) / COUNT(los_days) AS percentile_rank_of_7_day_stay
FROM cohort
GROUP BY
  discharge_group
ORDER BY
  -- Order for consistent presentation
  CASE
    WHEN discharge_group = 'Home'
    THEN 1
    WHEN discharge_group = 'Facility'
    THEN 2
    WHEN discharge_group = 'In-hospital Death'
    THEN 3
  END;