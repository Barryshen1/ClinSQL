WITH
-- 1) ICU stays of male patients age 88–98
male_elderly AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
),

-- 2) Identify stays with RRT (e.g., hemodialysis) in first 72h
rrt_stays AS (
  SELECT DISTINCT
    m.subject_id,
    m.hadm_id,
    m.stay_id
  FROM male_elderly m
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON m.subject_id = pe.subject_id
   AND m.hadm_id    = pe.hadm_id
   AND m.stay_id    = pe.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%dialysis%'
    AND pe.starttime <= TIMESTAMP_ADD(m.intime, INTERVAL 72 HOUR)
),

-- 3) Extract maximum instability score in first 72h per stay
instability_scores AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.stay_id,
    MAX(ce.valuenum) AS max_score
  FROM rrt_stays m
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON m.subject_id = ce.subject_id
   AND m.hadm_id    = ce.hadm_id
   AND m.stay_id    = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di_scores
    ON ce.itemid = di_scores.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON m.stay_id = icu.stay_id
  WHERE LOWER(di_scores.label) LIKE '%instability score%'
    AND ce.charttime <= TIMESTAMP_ADD(icu.intime, INTERVAL 72 HOUR)
  GROUP BY m.subject_id, m.hadm_id, m.stay_id
),

-- 4) Compute overall percentile of score = 85, using SAFE_DIVIDE
percentile_85 AS (
  SELECT
    SAFE_DIVIDE(
      COUNTIF(max_score <= 85),
      COUNT(*)
    ) AS pctile_of_85
  FROM instability_scores
),

-- 5) Compute 75th‐percentile cutoff (i.e. top quartile threshold)
quartile_cutoff AS (
  SELECT
    APPROX_QUANTILES(max_score, 4)[OFFSET(3)] AS q3_cutoff
  FROM instability_scores
),

-- 6) Top quartile stays: max_score > 75th percentile
top_quartile AS (
  SELECT s.subject_id, s.hadm_id, s.stay_id
  FROM instability_scores s
  CROSS JOIN quartile_cutoff q
  WHERE s.max_score > q.q3_cutoff
),

-- 7) ICU LOS and hospital mortality for top quartile
icu_los_mort AS (
  SELECT
    tq.subject_id,
    tq.hadm_id,
    tq.stay_id,
    icu.los AS icu_los,
    adm.hospital_expire_flag
  FROM top_quartile tq
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON tq.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON tq.hadm_id = adm.hadm_id
   AND tq.subject_id = adm.subject_id
)

-- Final output: percentile of 85, average ICU LOS & mortality in top quartile
SELECT
  p.pctile_of_85                                     AS percentile_of_85,
  metrics.avg_icu_los                                AS avg_icu_los_top_quartile,
  metrics.hospital_mortality_rate                    AS hospital_mortality_rate_top_quartile
FROM percentile_85 p
CROSS JOIN (
  SELECT
    AVG(icu_los)                   AS avg_icu_los,
    AVG(hospital_expire_flag)      AS hospital_mortality_rate
  FROM icu_los_mort
) AS metrics;