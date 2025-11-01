WITH patient_los AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.anchor_age BETWEEN 86 AND 96
    AND p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND a.admission_type != 'ELECTIVE'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
),
discharge_groups AS (
  SELECT
    subject_id,
    hadm_id,
    los_days,
    hospital_expire_flag,
    CASE
      WHEN discharge_location IN ('HOME', 'HOME WITH HOME IV PROVIDER') THEN 'Home'
      WHEN discharge_location IN (
        'SKILLED NURSING FACILITY', 'SNF', 
        'INPATIENT REHAB', 'REHAB', 'INTERMEDIATE CARE', 
        'ASSISTED LIVING', 'NURSING HOME', 'LONG TERM CARE',
        'PSYCH HOSPITAL', 'ACUTE HOSPITAL', 'FEDERAL HEALTH CARE'
      ) THEN 'Facility'
      ELSE 'Other'
    END AS discharge_group
  FROM patient_los
),
final_groups AS (
  SELECT
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      ELSE discharge_group
    END AS outcome_group,
    los_days
  FROM discharge_groups
  WHERE discharge_group != 'Other' OR hospital_expire_flag = 1
)
SELECT
  outcome_group,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS median_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS p75_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(900)] AS p90_los,
  SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*) AS pct_10day
FROM final_groups
GROUP BY outcome_group
ORDER BY outcome_group;