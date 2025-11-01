WITH
-- 1) Cohort of admissions for female patients age 82-92 with a diagnosis of pneumonia
pneumonia_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    -- require that this admission has at least one pneumonia diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code
       AND di.icd_version = d.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(d.long_title) LIKE '%pneumonia%'
    )
),

-- 2) Study composite risk scores per admission (proxy)
-- NOTE: the original query referenced a table `study_composite_risk_scores` which is not present.
-- As a minimal, self-contained replacement we use a simple proxy score: the count of diagnosis codes
-- recorded for the admission. Replace this CTE with your real study table if available.
study_scores AS (
  SELECT
    hadm_id,
    COUNT(*) AS composite_risk_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

-- 3) Add score and compute admission-level flags & LOS
admissions_with_flags AS (
  SELECT
    pa.*,
    ss.composite_risk_score,
    -- assign quintile by composite risk score (1 = lowest)
    NTILE(5) OVER (ORDER BY ss.composite_risk_score) AS quintile,
    -- define death time (prefer admission-level deathtime, otherwise patient-level dod)
    COALESCE(pa.deathtime, TIMESTAMP(pa.dod)) AS death_time,
    -- death within 30 days of admittime
    IF(
      COALESCE(pa.deathtime, TIMESTAMP(pa.dod)) IS NOT NULL
      AND COALESCE(pa.deathtime, TIMESTAMP(pa.dod)) <= TIMESTAMP_ADD(pa.admittime, INTERVAL 30 DAY),
      1, 0
    ) AS death_within_30,
    -- hospital survivor flag (discharged alive)
    IF(pa.hospital_expire_flag = 0, 1, 0) AS hospital_survivor,
    -- hospital LOS in days (integer days)
    TIMESTAMP_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days,
    -- cardiovascular complication flag: presence of any cardiovascular-related diagnosis during the same admission
    IF(
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
          ON di.icd_code = d.icd_code
         AND di.icd_version = d.icd_version
        WHERE di.hadm_id = pa.hadm_id
          AND (
               LOWER(d.long_title) LIKE '%myocard%'
            OR LOWER(d.long_title) LIKE '%infarct%'
            OR LOWER(d.long_title) LIKE '%coronary%'
            OR LOWER(d.long_title) LIKE '%cardiac%'
            OR LOWER(d.long_title) LIKE '%arrhythm%'
            OR LOWER(d.long_title) LIKE '%heart failure%'
            OR LOWER(d.long_title) LIKE '%cardiogenic%'
          )
      ), 1, 0
    ) AS cv_complication,
    -- neurologic complication flag: presence of neurologic-related diagnosis during the same admission
    IF(
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
          ON di.icd_code = d.icd_code
         AND di.icd_version = d.icd_version
        WHERE di.hadm_id = pa.hadm_id
          AND (
               LOWER(d.long_title) LIKE '%stroke%'
            OR LOWER(d.long_title) LIKE '%cerebro%'
            OR LOWER(d.long_title) LIKE '%seizure%'
            OR LOWER(d.long_title) LIKE '%neurolog%'
            OR LOWER(d.long_title) LIKE '%encephal%'
            OR LOWER(d.long_title) LIKE '%paralys%'
            OR LOWER(d.long_title) LIKE '%hemipleg%'
            OR LOWER(d.long_title) LIKE '%intracerebral%'
          )
      ), 1, 0
    ) AS neuro_complication
  FROM pneumonia_admissions pa
  LEFT JOIN study_scores ss
    ON pa.hadm_id = ss.hadm_id
  -- keep admissions that have a proxy score (most admissions with diagnoses will)
  WHERE ss.composite_risk_score IS NOT NULL
    -- ensure admittime/dischtime exist for LOS and event timing calculations
    AND pa.admittime IS NOT NULL
    AND pa.dischtime IS NOT NULL
)

-- 4) Aggregate by quintile and report metrics
SELECT
  quintile,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * SUM(death_within_30) / COUNT(*), 1) AS pct_30d_mortality,
  ROUND(100.0 * SUM(cv_complication) / COUNT(*), 1) AS pct_cardiovascular_complication,
  ROUND(100.0 * SUM(neuro_complication) / COUNT(*), 1) AS pct_neurologic_complication,
  -- median LOS among hospital survivors in this quintile (approximate)
  APPROX_QUANTILES(IF(hospital_survivor=1, los_days, NULL), 2)[OFFSET(1)] AS median_los_days_survivors
FROM admissions_with_flags af
GROUP BY quintile
ORDER BY quintile;