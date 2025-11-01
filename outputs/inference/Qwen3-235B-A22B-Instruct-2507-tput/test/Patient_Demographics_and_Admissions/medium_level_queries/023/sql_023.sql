WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    a.admission_location,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission,
    -- Compute LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.admittime < a.dischtime
    AND UPPER(a.admission_location) LIKE '%EMERG%'
),
cohort AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN UPPER(discharge_location) LIKE '%HOME%' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_category
  FROM patient_admissions
  WHERE age_at_admission BETWEEN 41 AND 51
),
summary AS (
  SELECT
    discharge_category,
    COUNT(*) AS total,
    AVG(CASE WHEN los_days >= 7 THEN 1.0 ELSE 0.0 END) AS prop_los_ge7,
    AVG(CASE WHEN los_days <= 10 THEN 1.0 ELSE 0.0 END) AS percentile_rank_10day_los
  FROM cohort
  GROUP BY discharge_category
)
SELECT
  discharge_category,
  ROUND(prop_los_ge7, 3) AS proportion_with_los_ge7_days,
  ROUND(percentile_rank_10day_los, 3) AS percentile_rank_of_10day_los
FROM summary
ORDER BY discharge_category;