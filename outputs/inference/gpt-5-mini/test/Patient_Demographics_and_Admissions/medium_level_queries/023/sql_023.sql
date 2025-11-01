WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    -- admitted from the ED: there was an ED registration time
    AND a.edregtime IS NOT NULL
    -- need valid times to compute LOS
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) >= 0
),

categorized AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in_hospital_death'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%home%' THEN 'home'
      ELSE 'facility'
    END AS discharge_category
  FROM cohort
)

SELECT
  discharge_category,
  COUNT(*) AS n_admissions,
  COUNTIF(los_days >= 7) AS n_los_ge_7,
  ROUND(SAFE_DIVIDE(COUNTIF(los_days >= 7), COUNT(*)), 4) AS prop_los_ge_7,
  -- percentile rank of a 10-day LOS defined as percent of patients with LOS <= 10 days
  ROUND(100.0 * SAFE_DIVIDE(COUNTIF(los_days <= 10), COUNT(*)), 2) AS percentile_rank_10day_pct
FROM categorized
GROUP BY discharge_category
ORDER BY discharge_category;