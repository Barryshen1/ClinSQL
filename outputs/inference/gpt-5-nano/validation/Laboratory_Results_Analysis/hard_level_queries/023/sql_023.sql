WITH ami_set AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE (
          (di.icd_version = 9 AND di.icd_code LIKE '410%')     -- AMI ICD-9
          OR
          (di.icd_version = 10 AND di.icd_code LIKE 'I21%')    -- AMI ICD-10
        )
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 90 AND 100
),
lab_data AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS LOS_days,
    COUNT(*) AS total_labs_48h,
    SUM(CASE
          WHEN le.valuenum IS NOT NULL
               AND (
                   (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
                   OR
                   (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
               )
          THEN 1 ELSE 0
        END) AS lab_instability_score
  FROM ami_set AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.hadm_id = a.hadm_id
   AND le.charttime >= a.admittime
   AND le.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.deathtime
),
p75 AS (
  -- Compute the 75th percentile threshold without PERCENTILE_CONT
  SELECT lab_instability_score AS p75_threshold
  FROM (
    SELECT lab_instability_score,
           ROW_NUMBER() OVER (ORDER BY lab_instability_score) AS rn,
           COUNT(*) OVER () AS total
    FROM lab_data
  )
  WHERE rn = CEILING(0.75 * total)
  LIMIT 1
),
final AS (
  SELECT
     p75_threshold,
     AVG(CASE WHEN ld.lab_instability_score >= p75_threshold THEN CASE WHEN ld.deathtime IS NOT NULL THEN 1 ELSE 0 END END) AS p75_inhospital_mortality_rate,
     AVG(CASE WHEN ld.lab_instability_score >= p75_threshold THEN ld.LOS_days END) AS p75_mean_los,
     AVG(CASE WHEN ld.lab_instability_score >= p75_threshold THEN SAFE_DIVIDE(ld.lab_instability_score, NULLIF(ld.total_labs_48h, 0)) END) AS p75_mean_critical_lab_rate,
     AVG(CASE WHEN ld.deathtime IS NOT NULL THEN 1 ELSE 0 END) AS all_inhospital_mortality_rate,
     AVG(ld.LOS_days) AS all_mean_los,
     AVG(SAFE_DIVIDE(ld.lab_instability_score, NULLIF(ld.total_labs_48h, 0))) AS all_mean_critical_lab_rate
  FROM lab_data ld
  CROSS JOIN p75
  GROUP BY p75_threshold
)
SELECT *
FROM final;