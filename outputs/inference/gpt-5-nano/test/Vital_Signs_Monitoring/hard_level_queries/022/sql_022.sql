WITH eligible AS (
  -- Male, age 85-95, with acute respiratory failure during hospitalization
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  WHERE LOWER(p.gender) = 'm'
    AND p.anchor_age BETWEEN 85 AND 95
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      WHERE d.subject_id = i.subject_id
        AND d.hadm_id = i.hadm_id
        AND d.icd_version = 9
        AND d.icd_code IN ('518.81','518.82')
    )
),
vitals AS (
  -- First-24h means for HR, SBP, RR, Temp
  SELECT
    e.hadm_id,
    e.subject_id,
    e.stay_id,
    AVG(CASE
          WHEN LOWER(di.label) LIKE '%heart rate%' THEN ce.valuenum
          ELSE NULL
        END) AS hr_mean,
    AVG(CASE
          WHEN LOWER(di.label) LIKE '%systolic%' OR LOWER(di.label) LIKE '%blood pressure%' THEN ce.valuenum
          ELSE NULL
        END) AS sbp_mean,
    AVG(CASE
          WHEN LOWER(di.label) LIKE '%respiratory rate%' THEN ce.valuenum
          ELSE NULL
        END) AS rr_mean,
    AVG(CASE
          WHEN LOWER(di.label) LIKE '%temperature%' THEN ce.valuenum
          ELSE NULL
        END) AS temp_mean
  FROM eligible e
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.hadm_id = e.hadm_id
   AND ce.subject_id = e.subject_id
   AND ce.stay_id = e.stay_id
   AND ce.charttime >= e.intime
   AND ce.charttime < TIMESTAMP_ADD(e.intime, INTERVAL 24 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
  GROUP BY e.hadm_id, e.subject_id, e.stay_id
),
final_score AS (
  -- Compute the vital-sign instability score (vs_score) for each stay
  SELECT
    v.hadm_id,
    v.subject_id,
    v.stay_id,
    COALESCE(ABS(v.hr_mean - 75), 0) * 1
    + COALESCE(ABS(v.sbp_mean - 110), 0) * 1
    + COALESCE(ABS(v.rr_mean - 18), 0) * 1
    + COALESCE(ABS(v.temp_mean - 37.0), 0) * 4 AS vs_score
  FROM vitals v
),
percentile_of_85 AS (
  -- Compute percentile of 85 within the distribution of vs_score
  SELECT p.percentile_of_85
  FROM (
    SELECT vs_score
    FROM final_score
    UNION ALL
    SELECT 85 AS vs_score
  ) AS s
  CROSS JOIN (
    SELECT PERCENT_RANK() OVER (ORDER BY vs_score) AS percentile_of_85
    FROM (
      SELECT vs_score
      FROM final_score
      UNION ALL
      SELECT 85 AS vs_score
    )
  ) AS p
  WHERE p.percentile_of_85 IS NOT NULL
  LIMIT 1
),
topquart AS (
  -- For the most unstable quartile (top 25%), compute LOS and mortality
  SELECT
    AVG(t.icu_los) AS avg_icu_los_topquart,
    AVG(t.hospital_expire_flag) AS in_hospital_mortality_rate_topquart
  FROM (
    SELECT
      icu.los AS icu_los,
      a.hospital_expire_flag,
      f.vs_score,
      NTILE(4) OVER (ORDER BY f.vs_score DESC) AS quart
    FROM final_score f
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON f.hadm_id = icu.hadm_id
     AND f.subject_id = icu.subject_id
     AND f.stay_id = icu.stay_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON f.hadm_id = a.hadm_id
  ) AS t
  WHERE t.quart = 1
)
SELECT
  po.percentile_of_85 AS percentile_of_85,
  tq.avg_icu_los_topquart,
  tq.in_hospital_mortality_rate_topquart
FROM percentile_of_85 po
CROSS JOIN topquart tq;