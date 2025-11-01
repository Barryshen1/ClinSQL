WITH eligible_stays AS (
  -- Identify ICU stays: male, age 88-98 at ICU time, with dialysis within first 72 hours
  SELECT
    i.stay_id,
    i.hadm_id,
    i.subject_id,
    i.intime,
    i.outtime,
    i.los AS icu_los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  WHERE LOWER(p.gender) = 'male'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 88 AND 98
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
      JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ie.itemid = di.itemid
      WHERE ie.stay_id = i.stay_id
        AND ie.starttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
        AND LOWER(di.label) LIKE '%dialysis%'
    )
),

instability_scores AS (
  -- Derive an instability score per ICU stay from vitals in the first 72 hours
  SELECT
    i.stay_id,
    SUM(
      CASE
        WHEN LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.label) LIKE '%heartrate%' THEN
          CASE WHEN ce.valuenum < 60 OR ce.valuenum > 100 THEN 10 ELSE 0 END
        WHEN LOWER(di.label) LIKE '%systolic%' OR LOWER(di.label) LIKE '%mean arterial pressure%' THEN
          CASE WHEN ce.valuenum < 90 OR ce.valuenum > 180 THEN 6 ELSE 0 END
        WHEN LOWER(di.label) LIKE '%mean arterial pressure%' THEN
          CASE WHEN ce.valuenum < 65 OR ce.valuenum > 110 THEN 4 ELSE 0 END
        WHEN LOWER(di.label) LIKE '%respiratory rate%' THEN
          CASE WHEN ce.valuenum > 22 THEN 8 ELSE 0 END
        WHEN LOWER(di.label) LIKE '%temperature%' THEN
          CASE WHEN ce.valuenum < 36 OR ce.valuenum > 38.5 THEN 5 ELSE 0 END
        ELSE 0
      END
    ) AS instability_score
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
    AND (
      LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.label) LIKE '%heartrate%' OR
      LOWER(di.label) LIKE '%systolic%' OR LOWER(di.label) LIKE '%mean arterial pressure%' OR
      LOWER(di.label) LIKE '%blood pressure%' OR
      LOWER(di.label) LIKE '%respiratory rate%' OR LOWER(di.label) LIKE '%temperature%'
    )
  GROUP BY i.stay_id
),

base AS (
  -- Assemble per-stay records with instability_score, icu_los, and mortality flag
  SELECT
    i.stay_id,
    i.hadm_id,
    i.subject_id,
    i.intime,
    i.outtime,
    i.icu_los,
    CASE WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 1 ELSE 0 END AS mort_hosp,
    iscore.instability_score
  FROM eligible_stays AS i
  JOIN instability_scores AS iscore ON i.stay_id = iscore.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON i.hadm_id = a.hadm_id
  WHERE iscore.instability_score IS NOT NULL
),

quartiled AS (
  -- Assign quartiles by instability score; quartile 1 = most unstable
  SELECT b.*,
         NTILE(4) OVER (ORDER BY b.instability_score DESC) AS quartile
  FROM base AS b
  WHERE b.instability_score IS NOT NULL
),

topquart_stats AS (
  -- Metrics for the most unstable quartile (quartile = 1)
  SELECT
    AVG(icu_los) AS avg_icu_los_topquart,
    AVG(mort_hosp) AS hospital_mortality_topquart,
    COUNT(*) AS topquart_n_stays
  FROM quartiled
  WHERE quartile = 1
),

percentile_of_85 AS (
  -- Percentile of 85 within the distribution of instability_score
  SELECT 100.0 * SAFE_DIVIDE(COUNTIF(instability_score <= 85), COUNT(*)) AS percentile_of_85
  FROM base
  WHERE instability_score IS NOT NULL
)

SELECT
  p.percentile_of_85,
  t.avg_icu_los_topquart,
  t.hospital_mortality_topquart,
  t.topquart_n_stays
FROM percentile_of_85 p
CROSS JOIN topquart_stats t;