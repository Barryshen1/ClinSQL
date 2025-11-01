WITH cohort AS (
  SELECT 
    p.subject_id,
    icu.stay_id,
    icu.hadm_id,
    p.anchor_age,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON p.subject_id = icu.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
),

-- Identify ARF patients
arf_patients AS (
  SELECT DISTINCT c.*
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON c.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
  WHERE (d.icd_version = 9 AND d.icd_code LIKE '584%')
     OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
),

-- Get vital signs in first 48 hours
vitals AS (
  SELECT 
    ce.stay_id,
    ce.charttime,
    MAX(CASE WHEN di.label LIKE '%Heart Rate%' THEN ce.valuenum END) AS heart_rate,
    MAX(CASE WHEN di.label LIKE '%Systolic%' THEN ce.valuenum END) AS sbp,
    MAX(CASE WHEN di.label LIKE '%Diastolic%' THEN ce.valuenum END) AS dbp,
    MAX(CASE WHEN di.label LIKE '%Respiratory Rate%' THEN ce.valuenum END) AS resp_rate,
    MAX(CASE WHEN di.label LIKE '%Temperature%' THEN ce.valuenum END) AS temp,
    MAX(CASE WHEN di.label LIKE '%GCS%' THEN ce.valuenum END) AS gcs
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN arf_patients a
    ON ce.stay_id = a.stay_id
  WHERE ce.charttime BETWEEN a.intime AND DATETIME_ADD(a.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    AND di.label IN (
      'Heart Rate', 'Respiratory Rate', 'Temperature Celsius', 'Temperature Fahrenheit',
      'Arterial Blood Pressure systolic', 'Arterial Blood Pressure diastolic',
      'GCS - Verbal Response', 'GCS - Motor Response', 'GCS - Eye Opening'
    )
  GROUP BY ce.stay_id, ce.charttime
),

-- Compute instability score per hour
hourly_scores AS (
  SELECT 
    stay_id,
    charttime,
    (
      IF(heart_rate > 130, 1, 0) +
      IF((sbp + dbp*2)/3 < 65, 1, 0) +
      IF(resp_rate > 25, 1, 0) +
      IF(temp < 35 OR temp > 38.5, 1, 0) +
      IF(gcs < 15, 1, 0)
    ) AS instability_score
  FROM vitals
),

-- Aggregate score per stay
stay_scores AS (
  SELECT 
    stay_id,
    SUM(instability_score) AS total_instability_score
  FROM hourly_scores
  GROUP BY stay_id
),

-- Add scores to ARF patients
arf_with_scores AS (
  SELECT 
    a.*,
    COALESCE(s.total_instability_score, 0) AS score
  FROM arf_patients a
  LEFT JOIN stay_scores s
    ON a.stay_id = s.stay_id
),

-- Compute 95th percentile
percentiles AS (
  SELECT 
    PERCENTILE_CONT(score, 0.95) OVER() AS p95,
    PERCENTILE_CONT(score, 0.75) OVER() AS p75
  FROM arf_with_scores
  LIMIT 1
),

-- Identify top quartile
top_quartile AS (
  SELECT 
    a.*,
    CASE WHEN a.score >= p.p75 THEN 1 ELSE 0 END AS in_top_quartile
  FROM arf_with_scores a
  CROSS JOIN percentiles p
),

-- Compare outcomes
comparison AS (
  SELECT
    in_top_quartile,
    AVG(CASE WHEN score >= p.p75 THEN 1 ELSE 0 END) AS pct_top_quartile,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate,
    AVG(icu_los) AS avg_icu_los,
    AVG(CASE WHEN EXISTS (
      SELECT 1 FROM vitals v
      WHERE v.stay_id = a.stay_id
        AND (v.sbp + v.dbp*2)/3 < 65
    ) THEN 1 ELSE 0 END) AS pct_hypotension,
    AVG(CASE WHEN EXISTS (
      SELECT 1 FROM vitals v
      WHERE v.stay_id = a.stay_id
        AND v.heart_rate > 130
    ) THEN 1 ELSE 0 END) AS pct_tachycardia
  FROM top_quartile a
  CROSS JOIN percentiles p
  GROUP BY in_top_quartile
)

SELECT * FROM comparison;