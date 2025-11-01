WITH target_base AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = icu.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
    -- COPD exacerbation: COPD-related ICD codes in the admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.hadm_id = icu.hadm_id
        AND (
             (di.icd_version = 10 AND di.icd_code LIKE 'J44%')
             OR (di.icd_version = 9 AND (di.icd_code LIKE '491%' OR di.icd_code LIKE '492%' OR di.icd_code LIKE '493%'))
        )
    )
),
proc_counts AS (
  SELECT
    t.hadm_id,
    COUNT(DISTINCT pe.itemid) AS distinct_procedures_first72
  FROM target_base t
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.hadm_id = t.hadm_id
   AND pe.stay_id = t.stay_id
   AND pe.starttime >= t.intime
   AND pe.starttime < TIMESTAMP_ADD(t.intime, INTERVAL 72 HOUR)
  GROUP BY t.hadm_id
),
p75 AS (
  SELECT quantiles[OFFSET(75)] AS p75_distinct_procedures
  FROM (
    SELECT APPROX_QUANTILES(distinct_procedures_first72, 100) AS quantiles
    FROM proc_counts
  )
),
target_stats AS (
  SELECT
    AVG(i.los) AS mean_los_target,
    AVG(CASE
          WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 1.0
          ELSE 0.0
        END) AS mortality_rate_target
  FROM target_base t
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON i.hadm_id = t.hadm_id AND i.stay_id = t.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = t.hadm_id
),
age_match_base AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = icu.subject_id
  WHERE p.anchor_age BETWEEN 88 AND 98
),
age_match_stats AS (
  SELECT
    AVG(i.los) AS mean_los_age_match,
    AVG(CASE
          WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 1.0
          ELSE 0.0
        END) AS mortality_rate_age_match
  FROM age_match_base am
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON i.hadm_id = am.hadm_id AND i.stay_id = am.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = am.hadm_id
)
SELECT
  p75_distinct_procedures,
  mean_los_target,
  mortality_rate_target,
  mean_los_age_match,
  mortality_rate_age_match
FROM p75
CROSS JOIN target_stats
CROSS JOIN age_match_stats;