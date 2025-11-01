WITH
-- 1. Identify dialysis‐type RRT itemids
rrt_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%dialysis%'
),

-- 2. Identify MAP and HR itemids
map_hr_items AS (
  SELECT
    MAX(CASE WHEN LOWER(label) LIKE '%mean arterial pressure%' THEN itemid END) AS map_itemid,
    MAX(CASE WHEN LOWER(label) LIKE '%heart rate%'           THEN itemid END) AS hr_itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
),

-- 3. Base ICU stays with patient/admission info
stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.gender,
    p.anchor_age,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.subject_id = adm.subject_id
   AND icu.hadm_id    = adm.hadm_id
),

-- 4. Flag stays with RRT in first 72h
rrt_flag AS (
  SELECT DISTINCT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  JOIN rrt_items r
    ON ie.itemid = r.itemid
  JOIN stays s
    ON ie.subject_id = s.subject_id
   AND ie.hadm_id    = s.hadm_id
   AND ie.stay_id    = s.stay_id
  WHERE ie.starttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
),

-- 5. All MAP and HR chart events in first 72h
vitals AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum,
    CASE WHEN ce.itemid = m.map_itemid THEN 'MAP'
         WHEN ce.itemid = m.hr_itemid  THEN 'HR'
    END AS vital
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN map_hr_items m
    ON ce.itemid IN (m.map_itemid, m.hr_itemid)
  JOIN stays s
    ON ce.subject_id = s.subject_id
   AND ce.hadm_id    = s.hadm_id
   AND ce.stay_id    = s.stay_id
  WHERE ce.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
),

-- 6. Hourly flags per stay
hourly AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    h.hour,
    MAX(CASE WHEN v.vital = 'MAP' AND v.valuenum < 65 THEN 1 ELSE 0 END)  AS hypotensive,
    MAX(CASE WHEN v.vital = 'HR'  AND v.valuenum > 100 THEN 1 ELSE 0 END)  AS tachycardic
  FROM stays s
  CROSS JOIN UNNEST(GENERATE_ARRAY(0,71)) AS h(hour)
  LEFT JOIN vitals v
    ON v.subject_id = s.subject_id
   AND v.hadm_id    = s.hadm_id
   AND v.stay_id    = s.stay_id
   AND v.charttime BETWEEN TIMESTAMP_ADD(s.intime,  INTERVAL h.hour   HOUR)
                     AND TIMESTAMP_ADD(s.intime,  INTERVAL h.hour+1 HOUR)
  GROUP BY s.subject_id, s.hadm_id, s.stay_id, h.hour
),

-- 7. Per-stay summaries
stay_summary AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.stay_id,
    s.gender,
    s.anchor_age,
    s.hospital_expire_flag,
    s.los,
    COUNTIF(h.hypotensive = 1)                         AS hypotensive_hours,
    COUNTIF(h.tachycardic = 1)                         AS tachycardic_hours,
    COUNTIF(h.hypotensive = 1 AND h.tachycardic = 1)   AS instab_hours,
    COUNTIF(h.hypotensive = 1 AND h.tachycardic = 1) / 72.0 AS instability_index
  FROM hourly h
  JOIN stays s
    ON h.subject_id = s.subject_id
   AND h.hadm_id    = s.hadm_id
   AND h.stay_id    = s.stay_id
  GROUP BY
    h.subject_id,
    h.hadm_id,
    h.stay_id,
    s.gender,
    s.anchor_age,
    s.hospital_expire_flag,
    s.los
),

-- 8. Tag RRT stays and cohort labels
labeled AS (
  SELECT
    ss.*,
    CASE
      WHEN ss.stay_id IN (SELECT stay_id FROM rrt_flag)
       AND ss.gender = 'F'
       AND ss.anchor_age BETWEEN 58 AND 68
      THEN 'target'
      WHEN ss.stay_id IN (SELECT stay_id FROM rrt_flag)
      THEN 'comparator'
      ELSE NULL
    END AS cohort
  FROM stay_summary ss
),

-- 9. Filter only RRT cohorts
cohorts AS (
  SELECT * FROM labeled
  WHERE cohort IN ('target','comparator')
)

-- 10. Final aggregations
SELECT
  APPROX_QUANTILES(
    CASE WHEN cohort = 'target' THEN instability_index ELSE NULL END,
    100
  ) AS target_instab_index_pct,
  cohort,
  AVG(hypotensive_hours)    AS avg_hypotensive_hours,
  AVG(tachycardic_hours)    AS avg_tachycardic_hours,
  AVG(los)                  AS avg_icu_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM cohorts
GROUP BY cohort
ORDER BY cohort;