WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit,
    -- Compute LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND a.admission_location = 'TRANSFER FROM HOSPITAL'
    AND a.dischtime IS NOT NULL
),
filtered_cohort AS (
  SELECT *
  FROM patient_admissions
  WHERE
    age_at_admit >= 52 AND age_at_admit <= 62
    AND (
      discharge_location IN (
        'HOME', 'HOME WITH HOME IV SERVICE',
        'SHORT TERM HOSPITAL', 'SNF', 'REHAB/DISTINCT PART HOSP',
        'HC', 'PSYCH', 'NH'
      )
      OR hospital_expire_flag = 1
    )
)
SELECT
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV(los_days), 2) AS sd_los_days,
  ROUND(
    (COUNT(CASE WHEN los_days <= 5 THEN 1 END) * 100.0) / COUNT(*),
    2
  ) AS percentile_rank_of_5day_los
FROM filtered_cohort;