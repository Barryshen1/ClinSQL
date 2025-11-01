WITH cohort AS (
  -- Base cohort: females 59-69, inpatient LOS >=48h, with first ICU stay
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    FIRST_VALUE(i.stay_id) OVER (PARTITION BY a.subject_id, a.hadm_id ORDER BY i.stay_id) AS first_stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admission_type IN ('ADMITTED', 'NEWBORN', 'EMERGENCY')
    AND DATE_DIFF(a.dischtime, a.admittime, HOUR) >= 48
),

glp1_items AS (
  -- Injectable GLP-1 itemids
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%glp-1%' 
     OR LOWER(label) LIKE '%exenatide%' 
     OR LOWER(label) LIKE '%liraglutide%' 
     OR LOWER(label) LIKE '%semaglutide%'  -- Injectable form
     OR LOWER(label) LIKE '%dulaglutide%'
),

glp1_events AS (
  -- GLP-1 administrations by time window
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    'first_48h' AS period,
    1 AS used_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON c.hadm_id = ie.hadm_id
    AND c.first_stay_id = ie.stay_id
  INNER JOIN glp1_items gi ON ie.itemid = gi.itemid
  WHERE ie.amount > 0
    AND ie.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)

  UNION ALL

  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    'final_12h' AS period,
    1 AS used_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON c.hadm_id = ie.hadm_id
    AND c.first_stay_id = ie.stay_id
  INNER JOIN glp1_items gi ON ie.itemid = gi.itemid
  WHERE ie.amount > 0
    AND ie.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime
),

summary AS (
  SELECT 
    period,
    COUNT(DISTINCT hadm_id) AS total_admissions,
    SUM(used_flag) AS admissions_with_glp1,
    ROUND(SUM(used_flag) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS prevalence_pct
  FROM glp1_events
  GROUP BY period

  UNION ALL

  -- Total cohort size (for reference; same for both periods)
  SELECT 
    'total' AS period,
    COUNT(DISTINCT hadm_id) AS total_admissions,
    NULL AS admissions_with_glp1,
    NULL AS prevalence_pct
  FROM cohort
)

SELECT 
  period,
  total_admissions,
  admissions_with_glp1,
  prevalence_pct
FROM summary
WHERE period != 'total'

UNION ALL

SELECT 
  'absolute_pp_difference' AS period,
  NULL AS total_admissions,
  NULL AS admissions_with_glp1,
  ROUND(
    (MAX(CASE WHEN period = 'final_12h' THEN prevalence_pct END) - 
     MAX(CASE WHEN period = 'first_48h' THEN prevalence_pct END)), 
    2
  ) AS prevalence_pct  -- Absolute percentage points
FROM summary
WHERE period IN ('first_48h', 'final_12h')
ORDER BY 
  CASE period 
    WHEN 'first_48h' THEN 1 
    WHEN 'final_12h' THEN 2 
    WHEN 'absolute_pp_difference' THEN 3 
  END
;