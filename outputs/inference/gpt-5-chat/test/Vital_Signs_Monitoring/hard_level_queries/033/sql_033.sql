WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    p.gender,
    p.anchor_age,
    icu.intime,
    icu.outtime,
    icu.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
),
instability_scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    MAX(e.valuenum) AS max_score
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` e
    ON c.subject_id = e.subject_id
    AND c.stay_id = e.stay_id
    AND e.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON e.itemid = di.itemid
  WHERE di.label = 'Instability Score' -- placeholder for actual item(s)
    AND e.valuenum IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),
percentile_calc AS (
  SELECT
    100 * (SUM(CASE WHEN max_score < 80 THEN 1 ELSE 0 END) OVER () / COUNT(*) OVER ()) 
      AS percentile_for_80
  FROM instability_scores
  LIMIT 1
),
cutoff_table AS (
  SELECT DISTINCT
    PERCENTILE_CONT(max_score, 0.9) OVER() AS cutoff
  FROM instability_scores
),
decile_stats AS (
  SELECT
    MAX(ct.cutoff) AS cutoff,  -- aggregate to carry the constant cutoff
    AVG(icu.los) AS avg_icu_los,
    AVG(a.hospital_expire_flag) AS mortality_rate
  FROM instability_scores s
  CROSS JOIN cutoff_table ct
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON s.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
  WHERE s.max_score >= ct.cutoff
)
SELECT
  p.percentile_for_80,
  d.cutoff AS decile_cutoff_score,
  d.avg_icu_los,
  d.mortality_rate
FROM percentile_calc p
CROSS JOIN decile_stats d;