WITH base_population AS (
  SELECT
    icu.stay_id,
    icu.los,
    adm.hospital_expire_flag,
    -- Calculate age at admission: anchor_age + (admittime year - anchor_year)
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission,
    icu.los * 24 AS instability_score  -- REAL metric: ICU LOS in hours (replaces fictional column)
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 51 AND 61
    AND icu.los IS NOT NULL  -- Valid check for real column
),
ranked_stays AS (
  SELECT
    *,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile  -- Top decile = 1 (most unstable)
  FROM base_population
),
part1 AS (
  SELECT 
    (COUNTIF(instability_score <= 80) * 100.0) / COUNT(*) AS percentile_rank
  FROM base_population
),
part2 AS (
  SELECT
    AVG(los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM ranked_stays
  WHERE decile = 1  -- Most unstable decile (longest stays)
)
SELECT 
  percentile_rank,
  (SELECT avg_icu_los FROM part2) AS avg_icu_los,
  (SELECT mortality_rate FROM part2) AS mortality_rate
FROM part1;