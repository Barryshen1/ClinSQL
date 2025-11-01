WITH cohort AS (
  SELECT DISTINCT
    i.subject_id,
    i.stay_id,
    i.intime,
    p.anchor_age,
    p.gender
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_icu.procedureevents pe
      JOIN physionet-data.mimiciv_3_1_icu.d_items di
        ON pe.itemid = di.itemid
      WHERE pe.stay_id = i.stay_id
        AND (
          LOWER(di.label) LIKE '%dialysis%'
          OR LOWER(di.label) LIKE '%crrt%'
          OR LOWER(di.label) LIKE '%rrt%'
          OR LOWER(di.label) LIKE '%renal replacement%'
        )
    )
),

vitals_72h AS (
  SELECT
    c.stay_id,
    ce.itemid,
    ce.valuenum
  FROM cohort c
  JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON c.stay_id = ce.stay_id
  WHERE ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    AND ce.itemid IN (
      211,      -- Heart Rate
      220050,   -- Systolic BP
      220210,   -- Respiratory Rate
      220277,   -- SpO2
      223761    -- Temperature
    )
    AND ce.valuenum IS NOT NULL
),

instability_score AS (
  SELECT
    stay_id,
    COALESCE(
      CASE WHEN COUNT(CASE WHEN itemid = 211 THEN 1 END) >= 2 
        THEN STDDEV(CASE WHEN itemid = 211 THEN valuenum END) 
        ELSE 0 END, 0
    ) +
    COALESCE(
      CASE WHEN COUNT(CASE WHEN itemid = 220050 THEN 1 END) >= 2 
        THEN STDDEV(CASE WHEN itemid = 220050 THEN valuenum END) 
        ELSE 0 END, 0
    ) +
    COALESCE(
      CASE WHEN COUNT(CASE WHEN itemid = 220210 THEN 1 END) >= 2 
        THEN STDDEV(CASE WHEN itemid = 220210 THEN valuenum END) 
        ELSE 0 END, 0
    ) +
    COALESCE(
      CASE WHEN COUNT(CASE WHEN itemid = 220277 THEN 1 END) >= 2 
        THEN STDDEV(CASE WHEN itemid = 220277 THEN valuenum END) 
        ELSE 0 END, 0
    ) +
    COALESCE(
      CASE WHEN COUNT(CASE WHEN itemid = 223761 THEN 1 END) >= 2 
        THEN STDDEV(CASE WHEN itemid = 223761 THEN valuenum END) 
        ELSE 0 END, 0
    ) AS cvsis
  FROM vitals_72h
  GROUP BY stay_id
),

final_cohort AS (
  SELECT
    c.stay_id,
    i.cvsis,
    ic.los,
    a.hospital_expire_flag
  FROM cohort c
  JOIN instability_score i ON c.stay_id = i.stay_id
  JOIN physionet-data.mimiciv_3_1_icu.icustays ic ON c.stay_id = ic.stay_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON c.subject_id = a.subject_id AND c.stay_id = ic.stay_id
  WHERE i.cvsis IS NOT NULL
),

percentile_65 AS (
  SELECT
    PERCENTILE_CONT(cvsis, 0.5) OVER() AS median_cvsis,
    PERCENTILE_CONT(cvsis, 0.9) OVER() AS p90_cvsis,
    PERCENT_RANK() OVER (ORDER BY cvsis) AS percentile_of_65
  FROM final_cohort
  WHERE cvsis = 65
  LIMIT 1
),

top_decile_stats AS (
  SELECT
    AVG(los) AS mean_los_top_decile,
    AVG(hospital_expire_flag) AS mortality_rate_top_decile
  FROM final_cohort
  WHERE cvsis >= (SELECT p90_cvsis FROM percentile_65)
)

SELECT
  (SELECT percentile_of_65 FROM percentile_65) AS percentile_of_65,
  (SELECT mean_los_top_decile FROM top_decile_stats) AS mean_los_top_decile,
  (SELECT mortality_rate_top_decile FROM top_decile_stats) AS mortality_rate_top_decile;