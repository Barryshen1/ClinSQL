WITH
-- 1) ICU stays for male patients aged 56-66
icu_cohort AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
),

-- 2) Relevant charted measurements (MAP, SBP, DBP) during the icustay
measures AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum,
    LOWER(COALESCE(di.label, '')) AS label,
    LOWER(COALESCE(ce.valueuom, '')) AS valueuom,
    CASE
      WHEN LOWER(COALESCE(di.label, '')) LIKE '%mean%' AND (LOWER(di.label) LIKE '%arterial%' OR LOWER(di.label) LIKE '%blood pressure%' OR LOWER(di.label) LIKE '%map%') THEN 'map'
      WHEN LOWER(COALESCE(di.label, '')) LIKE '%systolic%' THEN 'sbp'
      WHEN LOWER(COALESCE(di.label, '')) LIKE '%diastolic%' THEN 'dbp'
      ELSE NULL
    END AS meas_type
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  JOIN
    icu_cohort ic
  ON
    ce.stay_id = ic.stay_id
    AND ce.charttime BETWEEN ic.intime AND ic.outtime
  WHERE
    ce.valuenum IS NOT NULL
    -- Prefer mmHg-like units (some entries use variations); this reduces unit-mismatch
    AND (LOWER(ce.valueuom) LIKE '%mm%')
    AND (
      LOWER(di.label) LIKE '%mean%'     -- catch direct MAP labels
      OR LOWER(di.label) LIKE '%systolic%'
      OR LOWER(di.label) LIKE '%diastolic%'
      OR LOWER(di.label) LIKE '%map%'
    )
),

-- 3) Direct MAP measurements
direct_map AS (
  SELECT
    stay_id,
    charttime,
    valuenum AS map_val
  FROM
    measures
  WHERE
    meas_type = 'map'
),

-- 4) Compute MAP from SBP/DBP pairs within 60 seconds
sbp AS (
  SELECT stay_id, charttime, valuenum AS sbp_val
  FROM measures
  WHERE meas_type = 'sbp'
),
dbp AS (
  SELECT stay_id, charttime, valuenum AS dbp_val
  FROM measures
  WHERE meas_type = 'dbp'
),
computed_map AS (
  SELECT
    s.stay_id,
    -- midpoint of the two DATETIME values
    DATETIME_ADD(
      s.charttime,
      INTERVAL CAST(DATETIME_DIFF(d.charttime, s.charttime, SECOND) / 2 AS INT64) SECOND
    ) AS charttime_avg,
    (2 * d.dbp_val + s.sbp_val) / 3.0 AS map_val
  FROM
    sbp s
  JOIN
    dbp d
  ON
    s.stay_id = d.stay_id
    -- pair SBP and DBP within 60 seconds
    AND ABS(DATETIME_DIFF(s.charttime, d.charttime, SECOND)) <= 60
  -- DISTINCT pairs may be multiple; that's acceptable to capture MAP estimates
),

-- 5) All MAP observations (direct + computed)
all_map_obs AS (
  SELECT * FROM direct_map
  UNION ALL
  SELECT stay_id, charttime_avg AS charttime, map_val FROM computed_map
),

-- 6) Per-stay mean MAP
per_stay_map AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    AVG(m.map_val) AS mean_map,
    COUNT(*) AS n_map_obs
  FROM
    icu_cohort ic
  LEFT JOIN
    all_map_obs m
  USING(stay_id)
  WHERE
    m.map_val IS NOT NULL
  GROUP BY
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id
  HAVING
    COUNT(*) >= 1  -- require at least one MAP observation to include the stay
),

-- 7) Categorize per-stay mean MAP into bins
per_stay_cat AS (
  SELECT
    *,
    CASE
      WHEN mean_map < 65 THEN '<65'
      WHEN mean_map >= 65 AND mean_map <= 74 THEN '65-74'
      WHEN mean_map >= 75 AND mean_map <= 84 THEN '75-84'
      WHEN mean_map >= 85 THEN '>=85'
      ELSE 'unknown'
    END AS map_category
  FROM
    per_stay_map
),

-- 8) Flag hospital admissions (hadm_id) with stroke diagnoses (HOSP diagnoses)
hadm_stroke AS (
  SELECT DISTINCT
    d.hadm_id,
    1 AS stroke_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    d.hadm_id IS NOT NULL
    AND (
      LOWER(dd.long_title) LIKE '%stroke%'
      OR LOWER(dd.long_title) LIKE '%cerebrovascular%'
      OR LOWER(dd.long_title) LIKE '%cva%'
      OR LOWER(dd.long_title) LIKE '%cerebral infarction%'
      OR LOWER(dd.long_title) LIKE '%intracerebral hemorrhage%'
      OR LOWER(dd.long_title) LIKE '%subarachnoid%'
      OR LOWER(dd.long_title) LIKE '%intracranial hemorrhage%'
    )
)

-- 9) Final aggregation: per MAP category, count unique patients and stroke rates
SELECT
  psc.map_category AS map_bin,
  COUNT(DISTINCT psc.subject_id) AS patient_count,
  COUNT(DISTINCT CASE WHEN hs.stroke_flag = 1 THEN psc.subject_id END) AS patients_with_stroke,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN hs.stroke_flag = 1 THEN psc.subject_id END),
    NULLIF(COUNT(DISTINCT psc.subject_id), 0)
  ) AS stroke_rate
FROM
  per_stay_cat psc
LEFT JOIN
  hadm_stroke hs
ON
  psc.hadm_id = hs.hadm_id
GROUP BY
  map_bin
ORDER BY
  CASE
    WHEN map_bin = '<65' THEN 1
    WHEN map_bin = '65-74' THEN 2
    WHEN map_bin = '75-84' THEN 3
    WHEN map_bin = '>=85' THEN 4
    ELSE 5
  END;