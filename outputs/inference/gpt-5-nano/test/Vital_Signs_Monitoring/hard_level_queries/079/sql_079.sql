WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los_hours
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'Male'
    AND pat.anchor_age BETWEEN 81 AND 91
),

-- HFNC exposure within first 48h
hfnc_stays AS (
  SELECT DISTINCT c.subject_id, c.hadm_id, c.stay_id
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_icu.inputevents` AS ie
    ON ie.subject_id = c.subject_id
   AND ie.hadm_id = c.hadm_id
   AND ie.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = ie.itemid
  WHERE ie.starttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
    AND (LOWER(di.label) LIKE '%high flow%' OR LOWER(di.label) LIKE '%hfnc%')
),

-- Composite instability score (max valuenum for instability-labeled items)
instability AS (
  SELECT f.subject_id, f.hadm_id, f.stay_id,
         MAX(ie.valuenum) AS instability_score
  FROM hfnc_stays AS f
  JOIN `physionet-data.mimiciv_3_1_icu.inputevents` AS ie
    ON ie.subject_id = f.subject_id
   AND ie.hadm_id = f.hadm_id
   AND ie.stay_id = f.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = ie.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON icu.subject_id = f.subject_id
   AND icu.hadm_id = f.hadm_id
   AND icu.stay_id = f.stay_id
  WHERE ie.starttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
    AND LOWER(di.label) LIKE '%instability%'
  GROUP BY f.subject_id, f.hadm_id, f.stay_id
),

cohort_with_score AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id,
         i.intime, i.outtime, i.icu_los_hours,
         s.instability_score
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN instability AS s
    ON i.subject_id = s.subject_id
   AND i.hadm_id = s.hadm_id
   AND i.stay_id = s.stay_id
),

mortality AS (
  -- Hospital mortality flag for each stay
  SELECT ci.subject_id, ci.hadm_id, ci.stay_id,
         ci.intime, ci.outtime, ci.icu_los_hours, ci.instability_score,
         CASE
           WHEN adm.hospital_expire_flag = 1 OR adm.deathtime IS NOT NULL THEN 1
           ELSE 0
         END AS mortality
  FROM cohort_with_score AS ci
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON ci.hadm_id = adm.hadm_id
),

-- 90th percentile of instability_score across the mortality cohort
p90 AS (
  SELECT PERCENTILE_CONT(instability_score, 0.9) OVER() AS p90
  FROM mortality
  LIMIT 1
)

SELECT
  -- Percentile of 85 within HFNC-first-48h cohort
  (SELECT COUNT(*) * 1.0 / NULLIF((SELECT COUNT(*) FROM mortality), 0)
     FROM mortality
     WHERE instability_score <= 85) * 100 AS percentile_of_85,

  -- Top-decile metrics: average ICU LOS (days) and hospital mortality (%)
  AVG(mortality.icu_los_hours / 24.0) FILTER (WHERE mortality.instability_score >= p90.p90) AS avg_icu_los_days_top_decile,

  AVG(mortality.mortality) FILTER (WHERE mortality.instability_score >= p90.p90) * 100 AS hospital_mortality_percent_top_decile

FROM mortality
CROSS JOIN p90;