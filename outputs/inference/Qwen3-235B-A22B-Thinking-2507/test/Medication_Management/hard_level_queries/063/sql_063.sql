WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      (icd_version = 9 AND (icd_code LIKE '480%' OR icd_code LIKE '481%' OR icd_code LIKE '482%' 
                            OR icd_code LIKE '483%' OR icd_code LIKE '484%' OR icd_code LIKE '485%' 
                            OR icd_code LIKE '486%'))
      OR 
      (icd_version = 10 AND (icd_code LIKE 'J12%' OR icd_code LIKE 'J13%' OR icd_code LIKE 'J14%' 
                             OR icd_code LIKE 'J15%' OR icd_code LIKE 'J16%' OR icd_code LIKE 'J17%' 
                             OR icd_code LIKE 'J18%'))
    GROUP BY hadm_id
  ) d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 48 AND 58
),
med_first24 AS (
  SELECT 
    p.hadm_id,
    p.drug,
    CASE 
      WHEN LOWER(p.drug) IN (
        'citalopram', 'escitalopram', 'fluoxetine', 'fluvoxamine', 'paroxetine', 'sertraline',
        'duloxetine', 'venlafaxine', 'desvenlafaxine',
        'trazodone', 'mirtazapine', 'buspirone', 'lithium', 'sumatriptan', 'tramadol'
      ) THEN 1
      ELSE 0
    END AS is_serotonergic
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN cohort c 
    ON p.hadm_id = c.hadm_id
  WHERE p.starttime <= c.admittime + INTERVAL '24' HOUR
),
patient_level AS (
  SELECT 
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS hospital_los,
    COUNT(DISTINCT m.drug) AS med_complexity,
    COUNT(DISTINCT CASE WHEN m.is_serotonergic = 1 THEN m.drug END) AS num_serotonergic,
    MAX(CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS icu_flag
  FROM cohort c
  LEFT JOIN med_first24 m 
    ON c.hadm_id = m.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.hadm_id = i.hadm_id
  WHERE m.hadm_id IS NOT NULL  -- Ensure at least one med in first 24h
  GROUP BY c.hadm_id, c.subject_id, c.admittime, c.dischtime, c.hospital_expire_flag
),
patient_groups AS (
  SELECT 
    *,
    CASE WHEN num_serotonergic >= 2 THEN 1 ELSE 0 END AS serotonergic_risk
  FROM patient_level
),
med_complexity_stats AS (
  SELECT 
    'med_complexity' AS analysis_part,
    'overall' AS group_name,
    metric,
    value
  FROM (
    SELECT 
      APPROX_QUANTILES(med_complexity, 100) AS quants,
      AVG(med_complexity) AS avg_med  -- Compute avg here for scope
    FROM patient_groups
  )
  CROSS JOIN UNNEST([
    STRUCT('mean' AS metric, avg_med AS value),  -- Use precomputed avg
    STRUCT('p25', quants[OFFSET(25)]),
    STRUCT('p50', quants[OFFSET(50)]),
    STRUCT('p75', quants[OFFSET(75)])
  ])
),
group_comparison AS (
  SELECT 
    'group_comparison' AS analysis_part,
    'serotonergic' AS group_name,
    metric,
    value
  FROM (
    SELECT 
      APPROX_QUANTILES(hospital_los, 100)[OFFSET(75)] AS los_75th,
      AVG(hospital_expire_flag) AS mortality_rate
    FROM patient_groups
    WHERE serotonergic_risk = 1
  )
  CROSS JOIN UNNEST([
    STRUCT('los_75th' AS metric, los_75th AS value),
    STRUCT('mortality_rate', mortality_rate)
  ])
  UNION ALL
  SELECT 
    'group_comparison' AS analysis_part,
    'icu' AS group_name,
    metric,
    value
  FROM (
    SELECT 
      APPROX_QUANTILES(hospital_los, 100)[OFFSET(75)] AS los_75th,
      AVG(hospital_expire_flag) AS mortality_rate
    FROM patient_groups
    WHERE icu_flag = 1
  )
  CROSS JOIN UNNEST([
    STRUCT('los_75th' AS metric, los_75th AS value),
    STRUCT('mortality_rate', mortality_rate)
  ])
)
SELECT * FROM med_complexity_stats
UNION ALL
SELECT * FROM group_comparison;