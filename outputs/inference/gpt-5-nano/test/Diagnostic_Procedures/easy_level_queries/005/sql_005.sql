WITH eligible_subjects AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.subject_id = p.subject_id
  WHERE (
        LOWER(p.gender) = 'm'
        OR LOWER(p.gender) = 'male'
      )
  AND p.anchor_age IS NOT NULL
  AND p.anchor_year IS NOT NULL
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 57 AND 67
),

-- Step 2: identify echocardiography procedure events in ICU
echo_events AS (
  SELECT ei.subject_id,
         ei.hadm_id,
         ei.stay_id,
         ei.starttime
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` AS ei
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ei.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%echo%'  -- captures echocardiography related entries
),

-- Step 3: per-subject distinct echo counts
echo_counts AS (
  SELECT ee.subject_id,
         COUNT(DISTINCT CONCAT(CAST(ee.hadm_id AS STRING), '|', CAST(ee.stay_id AS STRING), '|', CAST(ee.starttime AS STRING))) AS echo_count
  FROM echo_events AS ee
  GROUP BY ee.subject_id
)

-- Step 4: compute 75th percentile across eligible subjects (including those with zero echoes)
SELECT
  -- 75th percentile across all eligible subjects, treating missing as 0 echoes
  APPROX_QUANTILES(COALESCE(ec.echo_count, 0), 100)[OFFSET(74)] AS p75_echo_count
FROM eligible_subjects AS es
LEFT JOIN echo_counts AS ec
  ON es.subject_id = ec.subject_id;