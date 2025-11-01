WITH cohort AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    icu.intime,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON icu.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 56 AND 66
    AND LOWER(dd.long_title) LIKE '%intracerebral hemorrhage%'
       OR LOWER(dd.long_title) LIKE '%intracranial hemorrhage%'
       OR LOWER(dd.long_title) LIKE '%intraventricular hemorrhage%'
),
diag_counts AS (
  SELECT
    c.stay_id,
    COUNT(*) AS diag_events
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
  WHERE ce.charttime IS NOT NULL
  GROUP BY c.stay_id
  UNION ALL
  SELECT
    c.stay_id,
    COUNT(*) AS diag_events
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
    AND le.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
  WHERE le.charttime IS NOT NULL
  GROUP BY c.stay_id
  UNION ALL
  SELECT
    c.stay_id,
    COUNT(*) AS diag_events
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` me
    ON c.hadm_id = me.hadm_id
    AND me.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
  WHERE me.charttime IS NOT NULL
  GROUP BY c.stay_id
),
agg_diag AS (
  SELECT
    stay_id,
    SUM(diag_events) AS total_diag_events
  FROM diag_counts
  GROUP BY stay_id
),
percentile_calc AS (
  SELECT
    APPROX_QUANTILES(total_diag_events, 100)[OFFSET(95)] AS p95_diag_events
  FROM agg_diag
),
cohort_stats AS (
  SELECT
    AVG(los) AS avg_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM cohort
),
overall_stats AS (
  SELECT
    AVG(los) AS avg_los_days,
    AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.hadm_id = a.hadm_id
)
SELECT
  p95_diag_events,
  cs.avg_los_days AS cohort_avg_los,
  cs.mortality_rate AS cohort_mortality,
  os.avg_los_days AS overall_avg_los,
  os.mortality_rate AS overall_mortality
FROM percentile_calc
CROSS JOIN cohort_stats cs
CROSS JOIN overall_stats os;