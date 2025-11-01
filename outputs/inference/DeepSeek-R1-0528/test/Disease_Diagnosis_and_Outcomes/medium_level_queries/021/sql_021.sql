WITH charlson_map AS (
  -- Minimal Charlson mapping (expand with full ICD codes in practice)
  SELECT '410.00' AS icd_code, 9 AS icd_version, 'MyocardialInfarction' AS category, 1 AS weight UNION ALL
  SELECT '410.01' AS icd_code, 9 AS icd_version, 'MyocardialInfarction' AS category, 1 AS weight UNION ALL
  SELECT 'I21.3' AS icd_code, 10 AS icd_version, 'MyocardialInfarction' AS category, 1 AS weight UNION ALL
  SELECT 'I22.0' AS icd_code, 10 AS icd_version, 'MyocardialInfarction' AS category, 1 AS weight UNION ALL
  SELECT 'V42.7' AS icd_code, 9 AS icd_version, 'RenalDisease' AS category, 2 AS weight UNION ALL
  SELECT 'Z94.2' AS icd_code, 10 AS icd_version, 'RenalDisease' AS category, 2 AS weight
),
charlson_score_data AS (
  SELECT 
    di.hadm_id,
    cm.category,
    cm.weight
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN charlson_map cm
    ON di.icd_code = cm.icd_code
    AND di.icd_version = cm.icd_version
),
charlson_agg AS (
  SELECT 
    hadm_id,
    SUM(weight) AS charlson_score
  FROM (
    SELECT DISTINCT hadm_id, category, weight
    FROM charlson_score_data
  )
  GROUP BY hadm_id
),
cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days,
    IF(EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
      WHERE i.hadm_id = a.hadm_id
    ), 'ICU', 'non-ICU') AS icu_status,
    COALESCE(c.charlson_score, 0) AS charlson_score,
    CASE 
      WHEN a.hospital_expire_flag = 1 
      THEN DATE_DIFF(a.deathtime, a.admittime, DAY) 
    END AS time_to_death
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN charlson_agg c
    ON a.hadm_id = c.hadm_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 60 AND 70
    AND a.hadm_id IN (  -- Surgical admissions
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    )
    AND a.hadm_id IN (  -- Postoperative complications
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code LIKE '99[6-9]%') OR
        (icd_version = 10 AND icd_code LIKE 'T8[0-8]%')
    )
),
cohort_groups AS (  -- Renamed from 'groups' (reserved keyword)
  SELECT 
    hadm_id,
    icu_status,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8 THEN '>=8'
    END AS los_group,
    CASE 
      WHEN charlson_score <= 3 THEN '<=3'
      WHEN charlson_score BETWEEN 4 AND 5 THEN '4-5'
      WHEN charlson_score > 5 THEN '>5'
    END AS charlson_group,
    hospital_expire_flag,
    time_to_death
  FROM cohort
  WHERE 
    los_days IS NOT NULL
    AND los_days >= 1  -- Ensure valid LOS
),
mortality_data AS (
  SELECT 
    icu_status,
    los_group,
    charlson_group,
    COUNT(*) AS n_admissions,
    SUM(hospital_expire_flag) AS n_mortality
  FROM cohort_groups  -- Updated reference
  GROUP BY icu_status, los_group, charlson_group
),
time_to_death_data AS (
  SELECT 
    icu_status,
    los_group,
    charlson_group,
    PERCENTILE_CONT(time_to_death, 0.5) OVER (
      PARTITION BY icu_status, los_group, charlson_group
    ) AS median_time_to_death_days
  FROM cohort_groups  -- Updated reference
  WHERE hospital_expire_flag = 1
)
SELECT 
  m.icu_status,
  m.los_group,
  m.charlson_group,
  m.n_admissions,
  m.n_mortality,
  ROUND(m.n_mortality * 100.0 / m.n_admissions, 2) AS mortality_percentage,
  t.median_time_to_death_days
FROM mortality_data m
LEFT JOIN (
  SELECT DISTINCT 
    icu_status,
    los_group,
    charlson_group,
    median_time_to_death_days
  FROM time_to_death_data
) t 
  ON m.icu_status = t.icu_status 
  AND m.los_group = t.los_group 
  AND m.charlson_group = t.charlson_group
ORDER BY icu_status, los_group, charlson_group;