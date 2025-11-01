WITH
-- 1) Identify ARF admissions
arf_adm AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%acute renal failure%'
),

-- 2) Define the ICU cohort: male, age 45–55, with ARF, joined to their ICU stays
cohort AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    -- Compute ICU LOS in hours
    TIMESTAMP_DIFF(ic.outtime, ic.intime, MINUTE) / 60.0 AS los_hours,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ic.subject_id = adm.subject_id
   AND ic.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ic.subject_id = p.subject_id
  JOIN arf_adm a
    ON ic.subject_id = a.subject_id
   AND ic.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
),

-- 3) Lookup itemids for MAP and HR
map_hr_items AS (
  SELECT itemid,
         CASE
           WHEN LOWER(label) LIKE '%mean arterial pressure%' THEN 'MAP'
           WHEN LOWER(label) LIKE '%heart rate%' THEN 'HR'
         END AS vital
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
     OR LOWER(label) LIKE '%heart rate%'
),

-- 4) Extract instability events in the first 48h
instability_events AS (
  SELECT
    c.stay_id,
    m.vital,
    ce.valuenum AS value,
    ce.charttime
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id
   AND c.hadm_id = ce.hadm_id
   AND c.stay_id = ce.stay_id
  JOIN map_hr_items m
    ON ce.itemid = m.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime
                        AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
),

-- 5) Summarize per stay: counts of hypotension and tachycardia
stay_instability AS (
  SELECT
    stay_id,
    SUM(CASE WHEN vital = 'MAP' AND value < 65 THEN 1 ELSE 0 END)   AS hypotension_count,
    SUM(CASE WHEN vital = 'HR'  AND value > 100 THEN 1 ELSE 0 END)   AS tachycardia_count
  FROM instability_events
  GROUP BY stay_id
),

-- 6) Composite score per stay
stay_scores AS (
  SELECT
    s.stay_id,
    s.hypotension_count,
    s.tachycardia_count,
    (s.hypotension_count + s.tachycardia_count) AS composite_score
  FROM stay_instability s
),

-- 7) Combine back to the cohort
cohort_scores AS (
  SELECT
    c.*,
    ss.hypotension_count,
    ss.tachycardia_count,
    ss.composite_score
  FROM cohort c
  LEFT JOIN stay_scores ss
    ON c.stay_id = ss.stay_id
  WHERE ss.composite_score IS NOT NULL
),

-- 8) Compute the 95th percentile and top quartile cutoff
percentiles AS (
  SELECT
    APPROX_QUANTILES(composite_score, 100)[OFFSET(95)] AS p95,
    APPROX_QUANTILES(composite_score, 4)[OFFSET(3)]   AS q3
  FROM cohort_scores
),

-- 9) Tag top quartile stays
tagged AS (
  SELECT
    cs.*,
    p.p95,
    p.q3,
    CASE WHEN cs.composite_score >= p.q3 THEN 'Top Quartile' ELSE 'Others' END AS quartile_group
  FROM cohort_scores cs
  CROSS JOIN percentiles p
)

-- 10) Final outputs: the 95th percentile, and comparison of metrics
SELECT
  -- 95th percentile composite score
  (SELECT p95 FROM percentiles) AS composite_score_95th,

  -- Comparison metrics by quartile group
  tg.quartile_group,
  COUNT(*)                               AS n_stays,
  AVG(hypotension_count)                 AS avg_hypotension_events,
  AVG(tachycardia_count)                 AS avg_tachycardia_events,
  AVG(los_hours)                         AS avg_icu_los_hours,
  AVG(hospital_expire_flag)              AS mortality_rate
FROM tagged tg
GROUP BY quartile_group
ORDER BY quartile_group;