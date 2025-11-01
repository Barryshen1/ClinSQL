WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.discharge_location,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.admission_type
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  WHERE p.anchor_age BETWEEN 88 AND 98
    AND a.admission_type = 'ELECTIVE'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

categorized_outcomes AS (
  SELECT
    subject_id,
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location IN ('SKILLED NURSING FACILITY', 'REHAB', 'REHAB - INPATIENT', 'LONG TERM CARE HOSPITAL') THEN 'SNF/rehab/LTACH'
      WHEN discharge_location LIKE '%HOME%' THEN 'Home'
      ELSE NULL
    END AS discharge_group
  FROM patient_admissions
  WHERE discharge_location IS NOT NULL
),

final_cohort AS (
  SELECT *
  FROM categorized_outcomes
  WHERE discharge_group IS NOT NULL
    AND los_days IS NOT NULL
)

SELECT
  discharge_group,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(APPROX_QUANTILES(los_days, 1000)[OFFSET(500)], 2) AS median_los,
  ROUND(APPROX_QUANTILES(los_days, 1000)[OFFSET(750)], 2) AS p75_los,
  ROUND(APPROX_QUANTILES(los_days, 1000)[OFFSET(900)], 2) AS p90_los,
  ROUND(SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS percent_los_le7
FROM final_cohort
GROUP BY discharge_group
ORDER BY discharge_group;