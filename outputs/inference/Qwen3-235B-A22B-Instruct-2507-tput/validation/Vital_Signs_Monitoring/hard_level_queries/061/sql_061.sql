WITH cohort AS (
  SELECT
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los AS icu_los,
    a.hospital_expire_flag,
    -- Placeholder score: in practice, this would be computed from first 24h vitals
    -- For demonstration, we use a mock score. Replace with real computation.
    MOD(CAST(p.subject_id AS INT64), 100) AS score -- Simulated score 0–99
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
  ON
    p.subject_id = i.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
  ON
    i.hadm_id = a.hadm_id
  WHERE
    p.gender = 'F'
    AND EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age >= 49
    AND EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age <= 59
),
cohort_with_percentile AS (
  SELECT
    *,
    PERCENT_RANK() OVER (ORDER BY score) AS percentile_rank
  FROM
    cohort
),
percentile_of_70 AS (
  SELECT
    MAX(CASE WHEN score <= 70 THEN percentile_rank ELSE NULL END) AS percentile
  FROM
    cohort_with_percentile
),
top_decile_stats AS (
  SELECT
    AVG(icu_los) AS mean_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS hospital_mortality_percent
  FROM
    cohort_with_percentile
  WHERE
    percentile_rank >= 0.9
)
SELECT
  p.percentile,
  t.mean_icu_los,
  t.hospital_mortality_percent
FROM
  percentile_of_70 p
CROSS JOIN
  top_decile_stats t;