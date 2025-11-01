WITH cohort AS (
  SELECT s.subject_id,
         s.hadm_id,
         s.stay_id,
         s.intime,
         s.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age >= 49
    AND p.anchor_age <= 59
),

-- 2) Vital readings within the first 24 hours of ICU stay
vitals AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    ic.intime,
    ic.los,
    ce.charttime,
    di.label AS item_label,
    ce.valuenum AS valuenum
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON ic.subject_id = c.subject_id
   AND ic.hadm_id = c.hadm_id
   AND ic.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = ic.subject_id
   AND ce.hadm_id = ic.hadm_id
   AND ce.stay_id = ic.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE ce.charttime >= ic.intime
    AND ce.charttime < TIMESTAMP_ADD(ic.intime, INTERVAL 24 HOUR)
    AND (
      LOWER(di.label) LIKE '%heart rate%'
      OR LOWER(di.label) LIKE '%systolic%'
      OR LOWER(di.label) LIKE '%blood pressure%'
      OR LOWER(di.label) LIKE '%respiratory rate%'
      OR LOWER(di.label) LIKE '%temperature%'
      OR LOWER(di.label) LIKE '%oxygen saturation%' OR LOWER(di.label) LIKE '%spo2%'
    )
),

-- 3) Compute per-stay instability score (sum of abnormal readings)
instability AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    v.los,
    SUM(
      CASE
        WHEN LOWER(v.item_label) LIKE '%heart rate%' THEN CASE WHEN v.valuenum < 40 OR v.valuenum > 100 THEN 1 ELSE 0 END
        WHEN LOWER(v.item_label) LIKE '%systolic%' OR LOWER(v.item_label) LIKE '%blood pressure%' THEN CASE WHEN v.valuenum < 90 OR v.valuenum > 180 THEN 1 ELSE 0 END
        WHEN LOWER(v.item_label) LIKE '%respiratory rate%' THEN CASE WHEN v.valuenum < 12 OR v.valuenum > 30 THEN 1 ELSE 0 END
        WHEN LOWER(v.item_label) LIKE '%temperature%' THEN CASE WHEN v.valuenum < 36.0 OR v.valuenum > 38.3 THEN 1 ELSE 0 END
        WHEN LOWER(v.item_label) LIKE '%oxygen saturation%' OR LOWER(v.item_label) LIKE '%spo2%' THEN CASE WHEN v.valuenum < 92 THEN 1 ELSE 0 END
        ELSE 0
      END
    ) AS instability_score
  FROM vitals AS v
  GROUP BY v.subject_id, v.hadm_id, v.stay_id, v.los
),

-- 4) Combine with LOS and mortality information
final AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.instability_score,
    i.los,
    adm.hospital_expire_flag,
    adm.deathtime,
    CASE WHEN (adm.hospital_expire_flag = 1 OR adm.deathtime IS NOT NULL) THEN 1.0 ELSE 0.0 END AS death_flag
  FROM instability AS i
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON i.subject_id = ic.subject_id
   AND i.hadm_id = ic.hadm_id
   AND i.stay_id = ic.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON ic.hadm_id = adm.hadm_id
),

-- 5) Percentile of 70 for the instability score
percentile70 AS (
  SELECT CAST(SUM(CASE WHEN instability_score <= 70 THEN 1 ELSE 0 END) AS FLOAT64) / CAST(COUNT(*) AS FLOAT64) AS percentile_of_70
  FROM final
),

-- 6) Rank stays by instability score to identify top decile
ranked AS (
  SELECT f.*,
         ROW_NUMBER() OVER (ORDER BY instability_score DESC) AS rn,
         COUNT(*) OVER () AS total
  FROM final AS f
),

top_decile AS (
  SELECT *
  FROM ranked
  WHERE rn <= CEILING(0.1 * total)
)

-- 7) Output: percentile_of_70, mean LOS for top decile, and mortality in top decile
SELECT
  p.percentile_of_70 AS percentile_of_70,
  AVG(td.los) AS mean_los_days_top_decile,
  AVG(td.death_flag) * 100 AS top_decile_mortality_pct
FROM percentile70 AS p
CROSS JOIN top_decile AS td
GROUP BY percentile_of_70;