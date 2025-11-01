WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.subject_id = a.subject_id
   AND icu.hadm_id    = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 85 AND 95
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = icu.subject_id
        AND d.hadm_id    = icu.hadm_id
        AND d.icd_code IN ('51881', '51882', '51884')
    )
),
vitals AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    -- Example instability score: sum of weighted deviations
    SUM(
      CASE
        WHEN ce.itemid IN (223761) THEN ABS(ce.valuenum - 120)      -- systolic BP dev.
        WHEN ce.itemid IN (220045) THEN ABS(ce.valuenum - 37)       -- temp dev.
        WHEN ce.itemid IN (220210) THEN ABS(ce.valuenum - 70)       -- heart rate dev.
        WHEN ce.itemid IN (618)    THEN ABS(ce.valuenum - 16)       -- resp rate dev.
        ELSE 0
      END
    ) AS score
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN cohort c
    ON ce.subject_id = c.subject_id
   AND ce.hadm_id    = c.hadm_id
   AND ce.stay_id    = c.stay_id
  WHERE ce.charttime BETWEEN c.intime
                         AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.subject_id, ce.hadm_id, ce.stay_id
),
combined AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    v.score,
    icu.los,
    a.hospital_expire_flag AS mortality
  FROM cohort c
  JOIN vitals v
    ON c.subject_id = v.subject_id
   AND c.hadm_id    = v.hadm_id
   AND c.stay_id    = v.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON c.subject_id = icu.subject_id
   AND c.hadm_id    = icu.hadm_id
   AND c.stay_id    = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.subject_id = a.subject_id
   AND c.hadm_id    = a.hadm_id
),
analysis AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY score DESC)       AS quartile,
    PERCENT_RANK() OVER (ORDER BY score)      AS percentile_rank
  FROM combined
)
SELECT
  -- Percentile rank of a score = 85
  (SELECT percentile_rank
   FROM analysis
   WHERE score = 85
   LIMIT 1
  )                                    AS percentile_rank_score_85,
  -- Average ICU length of stay in the most unstable quartile (NTILE=1)
  (SELECT AVG(los)
   FROM analysis
   WHERE quartile = 1
  )                                    AS avg_icu_los_top_quartile,
  -- In‐hospital mortality rate in the most unstable quartile
  (SELECT AVG(mortality)
   FROM analysis
   WHERE quartile = 1
  )                                    AS in_hospital_mortality_top_quartile;