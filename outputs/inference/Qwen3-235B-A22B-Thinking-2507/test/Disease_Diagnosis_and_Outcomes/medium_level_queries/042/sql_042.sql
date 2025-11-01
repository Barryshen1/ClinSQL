WITH ami_cohort AS (
  SELECT 
    a.hadm_id,
    p.gender,
    p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime)) AS age_at_admission,
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los_days,
    a.hospital_expire_flag,
    a.discharge_location
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.hadm_id = a.hadm_id
      AND d.icd_version = 10
      AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')
  )
  AND NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.hadm_id = a.hadm_id
      AND d.icd_version = 10
      AND (d.icd_code LIKE 'R57%' OR d.icd_code LIKE 'J96%')
  )
  AND p.gender = 'M'
  AND p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime)) BETWEEN 69 AND 79
),
cohort_with_los_group AS (
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8 THEN '>=8'
      ELSE 'other'
    END AS los_group
  FROM ami_cohort
  WHERE los_days > 0
),
-- Precompute discharge statistics per LOS group
discharge_stats AS (
  SELECT
    los_group,
    discharge_location,
    COUNT(*) AS cnt,
    SUM(COUNT(*)) OVER (PARTITION BY los_group) AS total_in_group
  FROM cohort_with_los_group
  GROUP BY los_group, discharge_location
),
ranked_discharge AS (
  SELECT
    los_group,
    discharge_location,
    cnt,
    total_in_group,
    ROW_NUMBER() OVER (PARTITION BY los_group ORDER BY cnt DESC) AS rn
  FROM discharge_stats
),
top3_discharge AS (
  SELECT
    los_group,
    STRING_AGG(
      discharge_location || ': ' || CAST(ROUND(100 * cnt / total_in_group, 1) AS STRING) || '%', 
      '; ' 
      ORDER BY cnt DESC
    ) AS top_discharge_destinations
  FROM ranked_discharge
  WHERE rn <= 3
  GROUP BY los_group
),
-- Main statistics calculation
group_stats AS (
  SELECT
    los_group,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_pct,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los
  FROM cohort_with_los_group
  GROUP BY los_group
)
-- Final result with joined discharge stats
SELECT
  g.los_group,
  g.mortality_pct,
  g.median_los,
  t.top_discharge_destinations
FROM group_stats g
LEFT JOIN top3_discharge t 
  ON g.los_group = t.los_group
ORDER BY 
  CASE g.los_group
    WHEN '1-3' THEN 1
    WHEN '4-7' THEN 2
    WHEN '>=8' THEN 3
    ELSE 4
  END;