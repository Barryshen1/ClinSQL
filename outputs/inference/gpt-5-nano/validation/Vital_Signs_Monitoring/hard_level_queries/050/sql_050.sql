WITH rrt AS (
  -- Identify ICU stays with renal replacement therapy (dialysis-related procedures)
  SELECT DISTINCT pe.subject_id, pe.hadm_id, pe.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = pe.itemid
  WHERE LOWER(di.label) LIKE '%dialysis%'
     OR LOWER(di.label) LIKE '%renal replacement%'
),
cohort AS (
  SELECT s.subject_id,
         s.hadm_id,
         s.stay_id,
         p.gender,
         p.anchor_age,
         s.los AS icu_los_hours,
         a.hospital_expire_flag AS death_flag,
         COALESCE(instab.instability72h_score, 0) AS instability72h_score
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = s.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = s.hadm_id
  JOIN rrt
    ON rrt.subject_id = s.subject_id
   AND rrt.hadm_id = s.hadm_id
   AND rrt.stay_id = s.stay_id
  LEFT JOIN (
     -- 72-hour instability proxy: count of out-of-range vital-sign measurements
     SELECT ce.subject_id,
            ce.hadm_id,
            ce.stay_id,
            SUM(
              CASE
                WHEN LOWER(di.label) LIKE '%heart rate%'   AND (ce.valuenum < 40 OR ce.valuenum > 140) THEN 1
                WHEN LOWER(di.label) LIKE '%systolic%'     AND (ce.valuenum < 70 OR ce.valuenum > 180) THEN 1
                WHEN LOWER(di.label) LIKE '%respiratory%'  AND (ce.valuenum < 6  OR ce.valuenum > 40) THEN 1
                WHEN LOWER(di.label) LIKE '%temperature%'  AND (ce.valuenum < 34 OR ce.valuenum > 41) THEN 1
                ELSE 0
              END
            ) AS instability72h_score
     FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
     JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
       ON di.itemid = ce.itemid
     JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS s2
       ON s2.subject_id = ce.subject_id AND s2.hadm_id = ce.hadm_id AND s2.stay_id = ce.stay_id
     WHERE ce.charttime >= s2.intime AND ce.charttime < TIMESTAMP_ADD(s2.intime, INTERVAL 72 HOUR)
     GROUP BY ce.subject_id, ce.hadm_id, ce.stay_id
  ) AS instab
    ON instab.subject_id = s.subject_id
   AND instab.hadm_id = s.hadm_id
   AND instab.stay_id = s.stay_id
),
t AS (
  SELECT c.*,
         NTILE(10) OVER (ORDER BY instability72h_score DESC) AS decile
  FROM cohort c
)
SELECT
  (SELECT CAST(COUNT(*) AS FLOAT64) FROM t WHERE instability72h_score <= 65) /
  NULLIF((SELECT COUNT(*) FROM t), 0) AS percentile_65,
  AVG(CASE WHEN decile = 1 THEN icu_los_hours END) / 24.0 AS mean_icu_los_days_top_decile,
  AVG(CASE WHEN decile = 1 THEN CAST(death_flag AS FLOAT64) END) AS mortality_top_decile
FROM t;