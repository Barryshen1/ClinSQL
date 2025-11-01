WITH patient_admissions AS (
  -- Get most recent admission for each patient meeting criteria
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    s.curr_service,
    TIMESTAMP_DIFF(TIMESTAMP(a.dischtime), TIMESTAMP(a.admittime), DAY) + 1 AS los_days,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN (
    -- Get most recent service for each admission
    SELECT
      subject_id,
      hadm_id,
      curr_service,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY transfertime DESC) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.services`
  ) s ON a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id AND s.rn = 1
  WHERE
    p.gender = 'M'
    AND s.curr_service = 'MED'
    AND a.dischtime IS NOT NULL
    AND p.anchor_age BETWEEN 49 AND 59
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 49 AND 59
),

-- Categorize discharge locations
discharge_categories AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
      WHEN discharge_location = 'HOME' THEN 'Home'
      ELSE 'Other'
    END AS discharge_category
  FROM
    patient_admissions
),

-- Calculate proportions for LOS thresholds
los_proportions AS (
  SELECT
    discharge_category,
    COUNT(*) AS total_patients,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS los_ge7,
    SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) AS los_ge14,
    ROUND(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) / COUNT(*), 4) AS prop_ge7,
    ROUND(SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) / COUNT(*), 4) AS prop_ge14
  FROM
    discharge_categories
  GROUP BY
    discharge_category
),

-- Calculate 7-day LOS percentiles
los_percentiles AS (
  SELECT
    discharge_category,
    PERCENT_RANK() OVER (PARTITION BY discharge_category ORDER BY los_days) AS percentile_rank,
    los_days
  FROM
    discharge_categories
)

-- Final output
SELECT
  lp.discharge_category,
  lp.total_patients,
  lp.prop_ge7 AS proportion_los_ge7,
  lp.prop_ge14 AS proportion_los_ge14,
  ROUND(AVG(CASE WHEN lpr.los_days = 7 THEN lpr.percentile_rank ELSE NULL END), 4) AS percentile_rank_for_7day_los
FROM
  los_proportions lp
LEFT JOIN
  los_percentiles lpr ON lp.discharge_category = lpr.discharge_category
GROUP BY
  lp.discharge_category, lp.total_patients, lp.prop_ge7, lp.prop_ge14
ORDER BY
  lp.discharge_category;