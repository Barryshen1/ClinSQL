WITH base AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.los AS icu_los,
    a.hospital_expire_flag,
    a.admission_type,
    p.gender,
    p.anchor_age,
    icu.first_careunit,
    icu.last_careunit
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON icu.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  WHERE LOWER(p.gender) LIKE 'm%'                                -- male
    AND p.anchor_age BETWEEN 63 AND 73
    AND (
          LOWER(a.admission_type) LIKE '%post%'                 -- postoperative admission type hint
          OR LOWER(icu.first_careunit) LIKE '%postop%'            -- post-op ICU unit hint
          OR LOWER(icu.last_careunit) LIKE '%postop%'
        )
),
fever AS (
  SELECT b.stay_id, COUNT(*) AS fever_cnt
  FROM base b
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS c
    ON c.stay_id = b.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON c.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%temperature%'
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 38.5
  GROUP BY b.stay_id
),
spo2 AS (
  SELECT b.stay_id, COUNT(*) AS spo2_cnt
  FROM base b
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS c
    ON c.stay_id = b.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON c.itemid = di.itemid
  WHERE (LOWER(di.label) LIKE '%spo2%' OR LOWER(di.label) LIKE '%o2 sat%')
    AND c.valuenum IS NOT NULL
    AND c.valuenum < 90
  GROUP BY b.stay_id
),
rr AS (
  SELECT b.stay_id, COUNT(*) AS rr_cnt
  FROM base b
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS c
    ON c.stay_id = b.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON c.itemid = di.itemid
  WHERE (LOWER(di.label) LIKE '%respiratory rate%' OR LOWER(di.label) LIKE '%rr%')
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 20
  GROUP BY b.stay_id
),
instability AS (
  SELECT
    b.stay_id,
    b.hadm_id,
    b.subject_id,
    b.icu_los,
    b.hospital_expire_flag,
    b.gender,
    b.anchor_age,
    COALESCE(f.fever_cnt, 0) AS fever_cnt,
    COALESCE(spo2.spo2_cnt, 0) AS spo2_cnt,
    COALESCE(r.rr_cnt, 0) AS rr_cnt,
    (COALESCE(f.fever_cnt, 0) + COALESCE(spo2.spo2_cnt, 0) + COALESCE(r.rr_cnt, 0)) AS instability_score
  FROM base b
  LEFT JOIN fever f ON b.stay_id = f.stay_id
  LEFT JOIN spo2 spo2 ON b.stay_id = spo2.stay_id
  LEFT JOIN rr r ON b.stay_id = r.stay_id
),
top_flag AS (
  -- 75th percentile threshold for instability_score across all eligible stays
  SELECT
    i.*,
    (SELECT thr
     FROM (
       SELECT quantiles[OFFSET(75)] AS thr
       FROM (SELECT APPROX_QUANTILES(instability_score, 100) AS quantiles FROM instability)
     )
    ) AS p75_thr
  FROM instability i
),
top AS (
  SELECT *,
         CASE WHEN instability_score >= p75_thr THEN 1 ELSE 0 END AS is_top
  FROM top_flag
),
summary AS (
  SELECT
    -- 95th percentile of instability_score within the top quartile (is_top = 1)
    (SELECT quantiles[OFFSET(95)]
     FROM (SELECT APPROX_QUANTILES(instability_score, 100) AS quantiles
           FROM top
           WHERE is_top = 1)
    ) AS instability_p95_top,
    -- Top quartile metrics
    AVG(CASE WHEN is_top = 1 AND fever_cnt > 0 THEN 1.0 ELSE 0.0 END) AS fever_top_rate,
    AVG(CASE WHEN is_top = 1 AND spo2_cnt > 0 THEN 1.0 ELSE 0.0 END) AS spo2_top_rate,
    AVG(CASE WHEN is_top = 1 AND rr_cnt > 0 THEN 1.0 ELSE 0.0 END) AS rr_top_rate,
    AVG(CASE WHEN is_top = 1 THEN icu_los END) AS los_top_mean,
    AVG(CASE WHEN is_top = 1 THEN hospital_expire_flag END) AS mortality_top_rate,
    -- Others (not in top quartile)
    AVG(CASE WHEN is_top = 0 AND fever_cnt > 0 THEN 1.0 ELSE 0.0 END) AS fever_other_rate,
    AVG(CASE WHEN is_top = 0 AND spo2_cnt > 0 THEN 1.0 ELSE 0.0 END) AS spo2_other_rate,
    AVG(CASE WHEN is_top = 0 AND rr_cnt > 0 THEN 1.0 ELSE 0.0 END) AS rr_other_rate,
    AVG(CASE WHEN is_top = 0 THEN icu_los END) AS los_other_mean,
    AVG(CASE WHEN is_top = 0 THEN hospital_expire_flag END) AS mortality_other_rate
  FROM top
)
SELECT * FROM summary;