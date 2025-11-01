WITH base_cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag AS mortality,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 68 AND 78
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_version = 10
        AND (icd_code LIKE 'S%' OR icd_code LIKE 'T%')
      GROUP BY hadm_id
      HAVING COUNT(DISTINCT icd_code) >= 2 
         OR MAX(CASE WHEN icd_code LIKE 'T07%' THEN 1 ELSE 0 END) = 1
    )
),

med_admin AS (
  SELECT 
    e.hadm_id,
    e.medication AS drug_name
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  INNER JOIN base_cohort bc
    ON e.hadm_id = bc.hadm_id
  WHERE e.charttime >= bc.admittime
    AND e.charttime < DATETIME_ADD(bc.admittime, INTERVAL 24 HOUR)
  
  UNION ALL
  
  SELECT 
    i.hadm_id,
    d.label AS drug_name
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON i.itemid = d.itemid
  INNER JOIN base_cohort bc
    ON i.hadm_id = bc.hadm_id
  WHERE i.starttime >= bc.admittime
    AND i.starttime < DATETIME_ADD(bc.admittime, INTERVAL 24 HOUR)
),

patient_med AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT drug_name) AS complexity,
    MAX(CASE WHEN LOWER(drug_name) IN (
      'fluoxetine', 'sertraline', 'paroxetine', 'citalopram', 'escitalopram',
      'venlafaxine', 'duloxetine', 'milnacipran', 'desvenlafaxine',
      'trazodone', 'amitriptyline', 'nortriptyline', 'imipramine', 'clomipramine',
      'phenelzine', 'tranylcypromine', 'selegiline', 'moclobemide',
      'tramadol', 'fentanyl', 'lithium', 'buspirone', 'dextromethorphan'
    ) THEN 1 ELSE 0 END) AS has_serotonergic_flag
  FROM med_admin
  GROUP BY hadm_id
),

patient_data AS (
  SELECT 
    bc.hadm_id,
    bc.los_days,
    bc.mortality,
    COALESCE(pm.complexity, 0) AS complexity,
    COALESCE(pm.has_serotonergic_flag, 0) AS has_serotonergic_flag
  FROM base_cohort bc
  LEFT JOIN patient_med pm
    ON bc.hadm_id = pm.hadm_id
),

entire_cohort_stats AS (
  SELECT 
    APPROX_QUANTILES(complexity, 100)[OFFSET(75)] AS q75
  FROM patient_data
),

patient_data_with_percentile AS (
  SELECT 
    *,
    PERCENT_RANK() OVER (ORDER BY complexity) AS pr
  FROM patient_data
)

SELECT 
  'serotonergic' AS group_name,
  APPROX_QUANTILES(complexity, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(complexity, 4)[OFFSET(2)] AS q2,
  APPROX_QUANTILES(complexity, 4)[OFFSET(3)] AS q3,
  AVG(pr * 100) AS avg_percentile,
  AVG(los_days) AS avg_los,
  AVG(mortality) AS mortality_rate
FROM patient_data_with_percentile
WHERE has_serotonergic_flag = 1

UNION ALL

SELECT 
  'non_serotonergic',
  APPROX_QUANTILES(complexity, 4)[OFFSET(1)],
  APPROX_QUANTILES(complexity, 4)[OFFSET(2)],
  APPROX_QUANTILES(complexity, 4)[OFFSET(3)],
  AVG(pr * 100),
  AVG(los_days),
  AVG(mortality)
FROM patient_data_with_percentile
WHERE has_serotonergic_flag = 0

UNION ALL

SELECT 
  'top_quartile',
  NULL,
  NULL,
  NULL,
  NULL,
  AVG(los_days),
  AVG(mortality)
FROM patient_data_with_percentile
WHERE complexity >= (SELECT q75 FROM entire_cohort_stats);