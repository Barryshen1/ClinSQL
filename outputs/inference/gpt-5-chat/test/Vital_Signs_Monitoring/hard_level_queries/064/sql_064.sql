WITH arf_male_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    p.anchor_age,
    p.gender,
    icu.intime,
    icu.outtime,
    icu.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON icu.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND LOWER(dd.long_title) LIKE '%acute respiratory failure%'
),
instability_events AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    SUM(CASE WHEN LOWER(di.label) LIKE '%mean arterial pressure%' AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS hypotension_count,
    SUM(CASE WHEN LOWER(di.label) LIKE '%heart rate%' AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_count
  FROM arf_male_icu a
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON a.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN a.intime AND TIMESTAMP_ADD(a.intime, INTERVAL 48 HOUR)
  GROUP BY a.subject_id, a.hadm_id, a.stay_id
),
scores AS (
  SELECT
    a.*,
    e.hypotension_count,
    e.tachycardia_count,
    (e.hypotension_count + e.tachycardia_count) AS composite_score
  FROM arf_male_icu a
  LEFT JOIN instability_events e
    ON a.subject_id = e.subject_id
    AND a.hadm_id = e.hadm_id
    AND a.stay_id = e.stay_id
),
percentiles AS (
  SELECT
    APPROX_QUANTILES(composite_score, 100)[OFFSET(95)] AS p95,
    APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] AS p75
  FROM scores
),
tagged AS (
  SELECT
    s.*,
    p.p95,
    p.p75,
    CASE WHEN s.composite_score >= p.p75 THEN 1 ELSE 0 END AS top_quartile
  FROM scores s
  CROSS JOIN percentiles p
)
SELECT
  'Cohort metrics' AS metric_group,
  p95 AS composite_score_95th_percentile,
  NULL AS hypotension_rate,
  NULL AS tachycardia_rate,
  NULL AS mean_icu_los_days,
  NULL AS mortality_rate
FROM percentiles

UNION ALL

SELECT
  CASE WHEN top_quartile = 1 THEN 'Top quartile patients' ELSE 'Other patients' END AS metric_group,
  NULL AS composite_score_95th_percentile,
  AVG(CASE WHEN hypotension_count > 0 THEN 1 ELSE 0 END) AS hypotension_rate,
  AVG(CASE WHEN tachycardia_count > 0 THEN 1 ELSE 0 END) AS tachycardia_rate,
  AVG(los) AS mean_icu_los_days,
  AVG(hospital_expire_flag) AS mortality_rate
FROM tagged
GROUP BY top_quartile;