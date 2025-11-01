WITH patient_los AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    -- Compute age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admit,
    -- Compute LOS in days (as fractional days)
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  -- Join with services to ensure medicine service
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.services s
    ON a.hadm_id = s.hadm_id
  WHERE p.gender = 'F'
    -- Age filter: 52 to 62 inclusive
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 52 AND 62
    -- Non-elective admission
    AND a.admission_type IN ('EMERGENCY', 'URGENT')
    -- Medicine service
    AND s.curr_service = 'MED'
    -- Valid admission and discharge times
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
),
cohort AS (
  SELECT
    subject_id,
    hadm_id,
    los_days,
    -- Define discharge group
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME WITH HOME IV PROVIDER') THEN 'Home'
      ELSE 'Facility'
    END AS discharge_group
  FROM patient_los
)
SELECT
  discharge_group,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS median_los, -- p50
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS p75_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(900)] AS p90_los,
  -- Percentile rank of 7 days: proportion with LOS <= 7
  SAFE_DIVIDE(COUNTIF(los_days <= 7), COUNT(*)) * 100 AS percentile_rank_of_7_days
FROM cohort
GROUP BY discharge_group
ORDER BY discharge_group;