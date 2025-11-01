WITH pneumonia_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%pneumonia%'
),

-- Cardiovascular-related codes (broad set)
cardio_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%myocardial infarction%'
     OR LOWER(long_title) LIKE '%heart failure%'
     OR LOWER(long_title) LIKE '%atrial fibrillation%'
     OR LOWER(long_title) LIKE '%cardiac arrest%'
     OR LOWER(long_title) LIKE '%ischemic%'
     OR LOWER(long_title) LIKE '%angina%'
),

-- Neurologic-related codes (broad set)
neuro_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%stroke%'
     OR LOWER(long_title) LIKE '%cerebrovascular%'
     OR LOWER(long_title) LIKE '%intracranial hemorrhage%'
     OR LOWER(long_title) LIKE '%seizure%'
),

-- Step 1: identify eligible pneumonia inpatients (female, age 82-92)
pna_cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime,
         p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN pneumonia_codes AS pc
    ON di.icd_code = pc.icd_code AND di.icd_version = pc.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
),

-- Step 2: derive cardiovascular/neurological flags per admission
cohort_flags AS (
  SELECT pna.subject_id,
         pna.hadm_id,
         pna.admittime,
         pna.dischtime,
         pna.deathtime,
         pna.anchor_age,
         pna.gender,
         COALESCE(MAX(CASE WHEN cc.icd_code IS NOT NULL THEN 1 ELSE 0 END), 0) AS cardio_flag,
         COALESCE(MAX(CASE WHEN nc.icd_code IS NOT NULL THEN 1 ELSE 0 END), 0) AS neuro_flag
  FROM pna_cohort AS pna
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON pna.subject_id = di.subject_id AND pna.hadm_id = di.hadm_id
  LEFT JOIN cardio_codes AS cc
    ON di.icd_code = cc.icd_code AND di.icd_version = cc.icd_version
  LEFT JOIN neuro_codes AS nc
    ON di.icd_code = nc.icd_code AND di.icd_version = nc.icd_version
  GROUP BY pna.subject_id, pna.hadm_id, pna.admittime, pna.dischtime, pna.deathtime, pna.anchor_age, pna.gender
),

-- Step 3: compute risk score components
risk_score AS (
  SELECT cf.*,
         -- age_factor assumes the 82-92 range; scale to ~0-2.5 across the range
         ((anchor_age - 82) * 0.25) AS age_factor,
         (2.0 * cardio_flag) AS cardio_contrib,
         (1.5 * neuro_flag) AS neuro_contrib,
         -- composite risk score (interpretable surrogate for the study's score)
         ((anchor_age - 82) * 0.25) + (2.0 * cardio_flag) + (1.5 * neuro_flag) AS risk_score
  FROM cohort_flags AS cf
),

-- Step 4: assemble final rows with 30-day mortality and LOS (among survivors)
final_rows AS (
  SELECT *,
         -- 30-day mortality indicator
         CASE
           WHEN deathtime IS NOT NULL AND deathtime <= TIMESTAMP_ADD(admittime, INTERVAL 30 DAY)
           THEN 1
           ELSE 0
         END AS death_within_30,
         -- LOS in days
         TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days
  FROM risk_score
  WHERE dischtime IS NOT NULL  -- exclude ongoing stays for LOS
),

-- Step 5: assign quintiles and prepare for per-quintile summaries
Quintiled AS (
   SELECT *,
          NTILE(5) OVER (ORDER BY risk_score) AS quintile,
          CASE WHEN death_within_30 = 0 THEN los_days ELSE NULL END AS los_days_survivor
   FROM final_rows
),

-- Step 6: per-quintile metrics (mortality, cardiovascular, neurologic)
metrics AS (
  SELECT quintile,
         AVG(death_within_30) AS mortality_30d_rate,
         AVG(cardio_flag) AS cardiovascular_complication_rate,
         AVG(neuro_flag) AS neurologic_complication_rate
  FROM Quintiled
  GROUP BY quintile
),

-- Median LOS among survivors per quintile
median_calc AS (
  SELECT quintile,
         AVG(los_days_survivor) AS median_los_survivors_days
  FROM (
     SELECT quintile, los_days_survivor,
            ROW_NUMBER() OVER (PARTITION BY quintile ORDER BY los_days_survivor) AS rn,
            COUNT(*) OVER (PARTITION BY quintile) AS total_cnt
     FROM Quintiled
     WHERE los_days_survivor IS NOT NULL
  )
  WHERE rn IN (CAST(FLOOR((total_cnt + 1) / 2) AS INT64),
               CAST(CEIL((total_cnt + 1) / 2) AS INT64))
  GROUP BY quintile
)

SELECT
  m.quintile,
  m mortality_30d_rate,
  m.cardiovascular_complication_rate,
  m.neurologic_complication_rate,
  med.median_los_survivors_days
FROM metrics AS m
JOIN median_calc AS med USING (quintile)
ORDER BY quintile;