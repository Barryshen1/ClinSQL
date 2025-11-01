WITH ami_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    -- Female
    p.gender = 'F'
    -- Age 66–76
    AND p.anchor_age BETWEEN 66 AND 76
    -- AMI diagnosis (ICD-9 and ICD-10)
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
    )
    -- Exclude initial shock or respiratory failure
    AND a.hadm_id NOT IN (
      SELECT hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d2
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd2
        ON d2.icd_code = dd2.icd_code AND d2.icd_version = dd2.icd_version
      WHERE
        (
          -- Shock
          (d2.icd_version = 9 AND d2.icd_code IN ('785.51', '785.59', '995.92'))
          OR
          (d2.icd_version = 10 AND d2.icd_code IN ('R57.0', 'R57.8', 'R57.9', 'T81.12'))
        )
        OR
        (
          -- Respiratory failure
          (d2.icd_version = 9 AND d2.icd_code IN ('518.81', '518.82'))
          OR
          (d2.icd_version = 10 AND d2.icd_code IN ('J96.00', 'J96.01', 'J96.02', 'J96.90', 'J96.91', 'J96.92'))
        )
    )
),

grouped_data AS (
  SELECT
    hadm_id,
    hospital_expire_flag,
    deathtime,
    admittime,
    los_days,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8 THEN '>=8'
      ELSE 'Other'
    END AS los_category,
    CASE
      WHEN admission_type = 'EMERGENCY' THEN 'Emergent'
      ELSE 'Non-Emergent'
    END AS admission_category
  FROM
    ami_cohort
),

mortality_stats AS (
  SELECT
    los_category,
    admission_category,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN DATE_DIFF(deathtime, admittime, DAY) ELSE NULL END) AS mean_time_to_death,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 1 THEN DATE_DIFF(deathtime, admittime, DAY) ELSE NULL END, 2)[OFFSET(1)] AS median_time_to_death
  FROM
    grouped_data
  GROUP BY
    los_category,
    admission_category
)

SELECT
  los_category,
  admission_category,
  total_patients,
  deaths,
  ROUND(SAFE_DIVIDE(deaths, total_patients) * 100, 2) AS mortality_percent,
  median_time_to_death
FROM
  mortality_stats
ORDER BY
  los_category,
  admission_category;