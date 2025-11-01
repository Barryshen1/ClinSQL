WITH dka_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON di.icd_code = dic.icd_code
    AND di.icd_version = dic.icd_version
  WHERE
    LOWER(dic.long_title) LIKE '%ketoacidosis%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
),

-- Prescriptions in first 48 hours of admission (distinct drug names)
presc_first48 AS (
  SELECT
    da.subject_id,
    da.hadm_id,
    LOWER(TRIM(prescriptions.drug)) AS drug,
    da.admittime,
    da.dischtime,
    da.hospital_expire_flag,
    da.anchor_age
  FROM
    dka_admissions da
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` prescriptions
    ON da.hadm_id = prescriptions.hadm_id
  WHERE
    prescriptions.starttime IS NOT NULL
    AND prescriptions.starttime >= da.admittime
    AND prescriptions.starttime < TIMESTAMP_ADD(da.admittime, INTERVAL 48 HOUR)
),

-- Per-admission medication features: complexity (# distinct drugs), RAAS exposure, potassium-raiser exposure
medication_summary AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    anchor_age,
    COUNT(DISTINCT drug) AS complexity,
    -- RAAS inhibitors (ACEi / ARB) detection by common name substrings
    MAX(CASE
      WHEN (
        drug LIKE '%lisinopril%' OR drug LIKE '%enalapril%' OR drug LIKE '%ramipril%' OR drug LIKE '%captopril%' OR
        drug LIKE '%benazepril%' OR drug LIKE '%fosinopril%' OR drug LIKE '%perindopril%' OR drug LIKE '%quinapril%' OR
        drug LIKE '%trandolapril%' OR drug LIKE '%losartan%' OR drug LIKE '%valsartan%' OR drug LIKE '%irbesartan%' OR
        drug LIKE '%candesartan%' OR drug LIKE '%olmesartan%' OR drug LIKE '%telmisartan%'
      ) THEN 1 ELSE 0 END) AS raas_exposure,
    -- Potassium-raising agents: potassium supplements, potassium-sparing diuretics, trimethoprim-containing drugs
    MAX(CASE
      WHEN (
        drug LIKE '%potassium%' OR drug LIKE '%potassium chloride%' OR
        drug LIKE '%spironolactone%' OR drug LIKE '%eplerenone%' OR drug LIKE '%amiloride%' OR drug LIKE '%triamterene%' OR
        drug LIKE '%trimethoprim%' OR drug LIKE '%bactrim%' OR drug LIKE '%sulfamethoxazole-trimethoprim%' OR
        drug LIKE '%potassium citrate%' OR drug LIKE '%potassium phosphate%'
      ) THEN 1 ELSE 0 END) AS potassium_raiser_exposure
  FROM
    presc_first48
  GROUP BY
    subject_id, hadm_id, admittime, dischtime, hospital_expire_flag, anchor_age
),

-- Define interaction flag and compute per-admission percentile rank among cohort
with_interaction_and_percentile AS (
  SELECT
    ms.*,
    CASE WHEN ms.raas_exposure = 1 AND ms.potassium_raiser_exposure = 1 THEN 1 ELSE 0 END AS hyperkalemia_interaction,
    PERCENT_RANK() OVER (ORDER BY ms.complexity) AS complexity_percentile
  FROM
    medication_summary ms
),

-- Determine 75th percentile cutoff for complexity (approximate)
quartile_cutoff AS (
  SELECT
    (APPROX_QUANTILES(complexity, 4))[OFFSET(3)] AS cutoff_75
  FROM
    with_interaction_and_percentile
),

-- Label top quartile patients (complexity >= cutoff)
labeled AS (
  SELECT
    w.*,
    q.cutoff_75,
    CASE WHEN w.complexity >= q.cutoff_75 THEN 1 ELSE 0 END AS top_quartile
  FROM
    with_interaction_and_percentile w
  CROSS JOIN
    quartile_cutoff q
)

-- Final aggregations: overall comparison and top-quartile comparison
SELECT
  'overall' AS subset,
  CASE WHEN hyperkalemia_interaction = 1 THEN 'with_interaction' ELSE 'without_interaction' END AS interaction_group,
  COUNT(1) AS n_patients,
  ROUND(AVG(complexity), 2) AS mean_complexity,
  ROUND(AVG(complexity_percentile), 3) AS mean_complexity_percentile,
  ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, MINUTE) / 1440.0), 3) AS mean_los_days,
  ROUND(100.0 * SUM(CAST(hospital_expire_flag AS INT64)) / COUNT(1), 2) AS mortality_percent
FROM
  labeled
GROUP BY
  hyperkalemia_interaction

UNION ALL

SELECT
  'top_quartile' AS subset,
  CASE WHEN hyperkalemia_interaction = 1 THEN 'with_interaction' ELSE 'without_interaction' END AS interaction_group,
  COUNT(1) AS n_patients,
  ROUND(AVG(complexity), 2) AS mean_complexity,
  ROUND(AVG(complexity_percentile), 3) AS mean_complexity_percentile,
  ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, MINUTE) / 1440.0), 3) AS mean_los_days,
  ROUND(100.0 * SUM(CAST(hospital_expire_flag AS INT64)) / COUNT(1), 2) AS mortality_percent
FROM
  labeled
WHERE
  top_quartile = 1
GROUP BY
  hyperkalemia_interaction
ORDER BY
  subset, interaction_group;