WITH cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.outtime,
    DATETIME_DIFF(ie.outtime, ie.intime, HOUR) AS icu_los_hrs,
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE 
    (p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year)) BETWEEN 43 AND 53
    AND ie.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 9 AND icd_code = '51881') OR 
        (icd_version = 10 AND icd_code LIKE 'J96%')
    )
    AND DATETIME_DIFF(ie.outtime, ie.intime, HOUR) >= 48
),

vital_events AS (
  SELECT 
    c.stay_id,
    ce.charttime,
    CASE 
      WHEN ce.itemid IN (211, 220045) THEN 'HR'
      WHEN ce.itemid IN (51, 442, 455, 6701, 220179, 220050) THEN 'SBP'
      WHEN ce.itemid IN (618, 615, 220210, 224690) THEN 'RR'
      WHEN ce.itemid IN (223761, 678, 223762, 676) THEN 'TEMP'
    END AS vital_type,
    ce.valuenum AS value
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE 
    ce.charttime >= c.intime 
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.itemid IN (211, 220045, 51, 442, 455, 6701, 220179, 220050, 618, 615, 220210, 224690, 223761, 678, 223762, 676)
    AND ce.valuenum IS NOT NULL
),

cohort_vital_abnormal AS (
  SELECT 
    stay_id,
    COUNT(*) AS total_measurements,
    SUM(
      CASE 
        WHEN (vital_type = 'HR' AND (value < 60 OR value > 100)) OR
             (vital_type = 'SBP' AND (value < 90 OR value > 140)) OR
             (vital_type = 'RR' AND (value < 12 OR value > 20)) OR
             (vital_type = 'TEMP' AND (value < 36 OR value > 38))
        THEN 1
        ELSE 0
      END
    ) AS abnormal_count
  FROM vital_events
  GROUP BY stay_id
  HAVING total_measurements > 0  -- Exclude patients with no valid vitals
),

cohort_index AS (
  SELECT 
    c.*,
    (cv.abnormal_count / cv.total_measurements) AS instability_index
  FROM cohort c
  INNER JOIN cohort_vital_abnormal cv
    ON c.stay_id = cv.stay_id
),

percentiles AS (
  SELECT 
    APPROX_QUANTILES(instability_index, 100)[OFFSET(95)] AS p95_index,
    APPROX_QUANTILES(instability_index, 100)[OFFSET(75)] AS p75_index
  FROM cohort_index
),

top_quartile_cohort AS (
  SELECT 
    ci.*
  FROM cohort_index ci
  CROSS JOIN percentiles p
  WHERE ci.instability_index >= p.p75_index
),

top_quartile_events AS (
  SELECT 
    tq.stay_id,
    COALESCE(SUM(CASE WHEN ce.itemid IN (52, 456, 220181, 225312) AND ce.valuenum < 65 THEN 1 ELSE 0 END), 0) AS map_events,
    COALESCE(SUM(CASE WHEN ce.itemid IN (211, 220045) AND ce.valuenum > 100 THEN 1 ELSE 0 END), 0) AS tachycardia_events
  FROM top_quartile_cohort tq
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON tq.stay_id = ce.stay_id
    AND ce.valuenum IS NOT NULL
  GROUP BY tq.stay_id
),

general_icu AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    ie.intime,
    ie.outtime,
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE 
    DATETIME_DIFF(ie.outtime, ie.intime, HOUR) >= 48
    AND (p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year)) >= 18
),

general_icu_events AS (
  SELECT 
    g.stay_id,
    COALESCE(SUM(CASE WHEN ce.itemid IN (52, 456, 220181, 225312) AND ce.valuenum < 65 THEN 1 ELSE 0 END), 0) AS map_events,
    COALESCE(SUM(CASE WHEN ce.itemid IN (211, 220045) AND ce.valuenum > 100 THEN 1 ELSE 0 END), 0) AS tachycardia_events
  FROM general_icu g
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON g.stay_id = ce.stay_id
    AND ce.valuenum IS NOT NULL
  GROUP BY g.stay_id
),

comparison_groups AS (
  SELECT 
    'Top Quartile Cohort' AS group_name,
    AVG(tqe.map_events) AS avg_map_events,
    AVG(tqe.tachycardia_events) AS avg_tachycardia_events,
    AVG(DATETIME_DIFF(tq.outtime, tq.intime, DAY)) AS avg_icu_los,
    AVG(tq.hospital_expire_flag) AS mortality_rate
  FROM top_quartile_cohort tq
  INNER JOIN top_quartile_events tqe
    ON tq.stay_id = tqe.stay_id
  UNION ALL
  SELECT 
    'General ICU Population' AS group_name,
    AVG(ge.map_events) AS avg_map_events,
    AVG(ge.tachycardia_events) AS avg_tachycardia_events,
    AVG(DATETIME_DIFF(g.outtime, g.intime, DAY)) AS avg_icu_los,
    AVG(g.hospital_expire_flag) AS mortality_rate
  FROM general_icu g
  INNER JOIN general_icu_events ge
    ON g.stay_id = ge.stay_id
)

-- Final Output: 95th percentile VII and comparison
SELECT 
  '95th Percentile Vital Instability Index' AS metric,
  (SELECT p95_index FROM percentiles) AS value,
  NULL AS group_name,
  NULL AS avg_map_events,
  NULL AS avg_tachycardia_events,
  NULL AS avg_icu_los,
  NULL AS mortality_rate
UNION ALL
SELECT 
  NULL AS metric,
  NULL AS value,
  group_name,
  avg_map_events,
  avg_tachycardia_events,
  avg_icu_los,
  mortality_rate
FROM comparison_groups;