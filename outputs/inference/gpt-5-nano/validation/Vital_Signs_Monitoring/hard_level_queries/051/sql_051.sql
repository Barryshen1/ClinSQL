WITH cohort AS (
  SELECT
    st.subject_id,
    st.hadm_id,
    st.stay_id,
    st.intime,
    st.outtime,
    TIMESTAMP_DIFF(st.outtime, st.intime, SECOND) / 3600.0 AS icu_los_hrs,
    a.deathtime,
    a.hospital_expire_flag,
    LOWER(p.gender) AS gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS st
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON st.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON st.subject_id = p.subject_id
  WHERE LOWER(p.gender) = 'm'
    AND p.anchor_age BETWEEN 89 AND 99
),
stroke_flag AS (
  SELECT c.stay_id,
         MAX(CASE
               WHEN LOWER(dd.long_title) LIKE '%ischemic stroke%' OR LOWER(dd.long_title) LIKE '%cerebral infarction%'
                 THEN 1
               ELSE 0
             END) AS is_ischemic_stroke
  FROM cohort AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = c.subject_id AND di.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  GROUP BY c.stay_id
),
instability AS (
  SELECT
     c.stay_id,
     SUM(CASE WHEN le.valuenum IS NOT NULL
              AND ((le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
                   OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper))
              THEN 1 ELSE 0 END) AS instability_score,
     COUNT(DISTINCT DATE(le.charttime)) AS abnormal_episodes
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.subject_id = c.subject_id
   AND le.hadm_id = c.hadm_id
  WHERE le.charttime >= c.intime
    AND le.charttime <= TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.stay_id
),
merged AS (
  SELECT
     i.stay_id,
     i.instability_score,
     i.abnormal_episodes,
     c.icu_los_hrs,
     s.is_ischemic_stroke,
     CASE WHEN c.deathtime IS NOT NULL OR c.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mortality_flag
  FROM instability i
  JOIN stroke_flag s ON i.stay_id = s.stay_id
  JOIN cohort c ON i.stay_id = c.stay_id
),
threshold AS (
  SELECT PERCENTILE_CONT(instability_score, 0.75) OVER () AS p75
  FROM merged
  LIMIT 1
)
SELECT
  CASE WHEN m.is_ischemic_stroke = 1 THEN 'Ischemic Stroke' ELSE 'General ICU' END AS group_label,
  COUNT(*) AS N,
  AVG(m.instability_score) AS mean_instability,
  AVG(m.abnormal_episodes) AS mean_abnormal_episodes,
  AVG(m.icu_los_hrs) AS mean_icu_los_hrs,
  AVG(m.mortality_flag) AS mortality_rate
FROM merged m
CROSS JOIN threshold t
WHERE m.instability_score >= t.p75
GROUP BY group_label
ORDER BY group_label;