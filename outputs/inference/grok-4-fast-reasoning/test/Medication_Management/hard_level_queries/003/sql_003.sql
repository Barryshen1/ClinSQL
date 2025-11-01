WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
),
first24_complexity AS (
  SELECT
    pr.hadm_id,
    COUNT(DISTINCT pr.drug) AS complexity
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN cohort c
    ON pr.hadm_id = c.hadm_id
  WHERE pr.starttime >= c.admittime
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY pr.hadm_id
),
percentiles AS (
  SELECT
    hadm_id,
    complexity,
    PERCENT_RANK() OVER (ORDER BY complexity DESC) AS percentile_rank
  FROM first24_complexity
),
patient_metrics AS (
  SELECT
    c.hadm_id,
    COALESCE(f.complexity, 0) AS complexity,
    COALESCE(per.percentile_rank, 0) AS percentile_rank,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days,
    c.hospital_expire_flag AS mortality_flag
  FROM cohort c
  LEFT JOIN first24_complexity f
    ON c.hadm_id = f.hadm_id
  LEFT JOIN percentiles per
    ON c.hadm_id = per.hadm_id
),
qt_patients AS (
  SELECT DISTINCT pr.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN cohort c
    ON pr.hadm_id = c.hadm_id
  WHERE pr.starttime >= c.admittime
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
    AND (LOWER(pr.drug) LIKE '%amiodarone%'
      OR LOWER(pr.drug) LIKE '%haloperidol%'
      OR LOWER(pr.drug) LIKE '%ondansetron%'
      OR LOWER(pr.drug) LIKE '%methadone%'
      OR LOWER(pr.drug) LIKE '%sotalol%'
      OR LOWER(pr.drug) LIKE '%levofloxacin%'
      OR LOWER(pr.drug) LIKE '%moxifloxacin%'
      OR LOWER(pr.drug) LIKE '%ziprasidone%')
),
bleeding_patients AS (
  SELECT DISTINCT pr.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN cohort c
    ON pr.hadm_id = c.hadm_id
  WHERE pr.starttime >= c.admittime
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
    AND (LOWER(pr.drug) LIKE '%warfarin%'
      OR LOWER(pr.drug) LIKE '%heparin%'
      OR LOWER(pr.drug) LIKE '%enoxaparin%'
      OR LOWER(pr.drug) LIKE '%dalteparin%'
      OR LOWER(pr.drug) LIKE '%rivaroxaban%'
      OR LOWER(pr.drug) LIKE '%apixaban%'
      OR LOWER(pr.drug) LIKE '%dabigatran%'
      OR LOWER(pr.drug) LIKE '%clopidogrel%'
      OR LOWER(pr.drug) LIKE '%prasugrel%')
),
group_stats AS (
  SELECT
    'QT-prolonging' AS group_type,
    AVG(complexity) AS avg_complexity,
    AVG(percentile_rank) AS avg_percentile_rank,
    AVG(los_days) AS avg_los,
    AVG(mortality_flag) AS mortality_rate
  FROM patient_metrics pm
  WHERE pm.hadm_id IN (SELECT hadm_id FROM qt_patients)

  UNION ALL

  SELECT
    'Bleeding-risk' AS group_type,
    AVG(complexity) AS avg_complexity,
    AVG(percentile_rank) AS avg_percentile_rank,
    AVG(los_days) AS avg_los,
    AVG(mortality_flag) AS mortality_rate
  FROM patient_metrics pm
  WHERE pm.hadm_id IN (SELECT hadm_id FROM bleeding_patients)

  UNION ALL

  SELECT
    'General' AS group_type,
    AVG(complexity) AS avg_complexity,
    AVG(percentile_rank) AS avg_percentile_rank,
    AVG(los_days) AS avg_los,
    AVG(mortality_flag) AS mortality_rate
  FROM patient_metrics pm
),
top_quartile_stats AS (
  SELECT
    'Top Quartile' AS group_type,
    NULL AS avg_complexity,
    NULL AS avg_percentile_rank,
    AVG(los_days) AS avg_los,
    AVG(mortality_flag) AS mortality_rate
  FROM patient_metrics pm
  WHERE pm.percentile_rank >= 0.75
)
SELECT * FROM group_stats
UNION ALL
SELECT * FROM top_quartile_stats
ORDER BY CASE group_type
  WHEN 'General' THEN 1
  WHEN 'QT-prolonging' THEN 2
  WHEN 'Bleeding-risk' THEN 3
  WHEN 'Top Quartile' THEN 4
END;