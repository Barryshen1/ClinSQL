WITH base AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
),
age_computed AS (
  SELECT *,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admission
  FROM base
  WHERE anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) BETWEEN 39 AND 49
),
emar_data AS (
  SELECT 
    ac.hadm_id,
    e.medication,
    e.charttime
  FROM age_computed ac
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON ac.hadm_id = e.hadm_id
    AND e.charttime BETWEEN ac.admittime AND DATETIME_ADD(ac.admittime, INTERVAL 24 HOUR)
),
medications AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT medication) AS medication_complexity,
    MAX(CASE WHEN medication IN (
        'amiodarone', 'disopyramide', 'dofetilide', 'ibutilide', 'procainamide', 'quinidine', 'sotalol', 
        'arsenic trioxide', 'chlorpromazine', 'clozapine', 'haloperidol', 'iloperidone', 'methadone', 'pimozide', 'thioridazine', 'ziprasidone', 
        'ciprofloxacin', 'clarithromycin', 'erythromycin', 'levofloxacin', 'moxifloxacin', 
        'domperidone', 'droperidol', 'ondansetron'
      ) THEN 1 ELSE 0 END) AS qt_flag,
    MAX(CASE WHEN medication IN (
        'warfarin', 'heparin', 'enoxaparin', 'dalteparin', 'tinzaparin', 'fondaparinux', 
        'aspirin', 'clopidogrel', 'prasugrel', 'ticagrelor', 'dipyridamole', 
        'apixaban', 'rivaroxaban', 'dabigatran', 'edoxaban'
      ) THEN 1 ELSE 0 END) AS bleed_flag
  FROM emar_data
  GROUP BY hadm_id
),
cohort AS (
  SELECT 
    ac.*,
    COALESCE(m.medication_complexity, 0) AS medication_complexity,
    COALESCE(m.qt_flag, 0) AS qt_flag,
    COALESCE(m.bleed_flag, 0) AS bleed_flag
  FROM age_computed ac
  LEFT JOIN medications m
    ON ac.hadm_id = m.hadm_id
),
cohort_with_percentile AS (
  SELECT *,
    PERCENT_RANK() OVER (ORDER BY medication_complexity) * 100 AS percentile_rank
  FROM cohort
),
p75 AS (
  SELECT 
    APPROX_QUANTILES(medication_complexity, 100)[OFFSET(75)] AS p75_value
  FROM cohort
),
part_a AS (
  SELECT 
    'QT' AS group_label,
    COUNT(*) AS num_patients,
    AVG(medication_complexity) AS avg_med_complexity,
    AVG(percentile_rank) AS avg_percentile_rank,
    AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
    AVG(hospital_expire_flag) * 100 AS mortality_rate
  FROM cohort_with_percentile
  WHERE qt_flag = 1
  UNION ALL
  SELECT 
    'Bleed' AS group_label,
    COUNT(*) AS num_patients,
    AVG(medication_complexity) AS avg_med_complexity,
    AVG(percentile_rank) AS avg_percentile_rank,
    AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
    AVG(hospital_expire_flag) * 100 AS mortality_rate
  FROM cohort_with_percentile
  WHERE bleed_flag = 1
  UNION ALL
  SELECT 
    'All' AS group_label,
    COUNT(*) AS num_patients,
    AVG(medication_complexity) AS avg_med_complexity,
    AVG(percentile_rank) AS avg_percentile_rank,
    AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
    AVG(hospital_expire_flag) * 100 AS mortality_rate
  FROM cohort_with_percentile
),
part_b AS (
  SELECT 
    'QT (top quartile)' AS group_label,
    COUNT(*) AS num_patients,
    AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
    AVG(hospital_expire_flag) * 100 AS mortality_rate
  FROM cohort_with_percentile, p75
  WHERE medication_complexity >= p75_value AND qt_flag = 1
  UNION ALL
  SELECT 
    'Bleed (top quartile)' AS group_label,
    COUNT(*) AS num_patients,
    AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
    AVG(hospital_expire_flag) * 100 AS mortality_rate
  FROM cohort_with_percentile, p75
  WHERE medication_complexity >= p75_value AND bleed_flag = 1
  UNION ALL
  SELECT 
    'All (top quartile)' AS group_label,
    COUNT(*) AS num_patients,
    AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
    AVG(hospital_expire_flag) * 100 AS mortality_rate
  FROM cohort_with_percentile, p75
  WHERE medication_complexity >= p75_value
)
SELECT 
  'A' AS part,
  group_label,
  num_patients,
  avg_med_complexity,
  avg_percentile_rank,
  avg_los_days,
  mortality_rate
FROM part_a
UNION ALL
SELECT 
  'B' AS part,
  group_label,
  num_patients,
  NULL AS avg_med_complexity,
  NULL AS avg_percentile_rank,
  avg_los_days,
  mortality_rate
FROM part_b
ORDER BY part, group_label;