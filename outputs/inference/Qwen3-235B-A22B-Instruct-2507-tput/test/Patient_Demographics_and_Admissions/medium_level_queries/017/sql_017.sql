WITH icu_los AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    a.discharge_location,
    a.hospital_expire_flag,
    i.los AS icu_los_days,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND i.los IS NOT NULL
),
cohort AS (
  SELECT
    icu_los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%home%'
        AND LOWER(discharge_location) NOT LIKE '%hospice%' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_group
  FROM icu_los
  WHERE age_at_admit BETWEEN 38 AND 48
)
SELECT
  discharge_group,
  AVG(icu_los_days) AS mean_los,
  APPROX_QUANTILES(icu_los_days, 1000)[OFFSET(500)] AS median_los,
  APPROX_QUANTILES(icu_los_days, 1000)[OFFSET(750)] AS p75_los,
  APPROX_QUANTILES(icu_los_days, 1000)[OFFSET(900)] AS p90_los
FROM cohort
GROUP BY discharge_group
ORDER BY discharge_group;