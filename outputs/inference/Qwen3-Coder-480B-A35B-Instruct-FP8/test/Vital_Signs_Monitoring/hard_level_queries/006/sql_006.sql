WITH cohort AS (
  -- Step 1: Identify male patients aged 60–70 with UGIB
  SELECT DISTINCT
    p.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los AS icu_los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON i.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND LOWER(dd.long_title) LIKE '%upper gastrointestinal bleeding%'
),

-- Step 2: Extract vitals in first 48 hours of ICU stay and compute instability flags
vitals AS (
  SELECT
    c.stay_id,
    MAX(CASE WHEN di.label = 'Heart Rate' AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_flag,
    MAX(CASE WHEN di.label = 'MAP' AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS hypotension_flag,
    MAX(CASE WHEN di.label = 'Respiratory Rate' AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS tachypnea_flag
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    di.label IN ('Heart Rate', 'MAP', 'Respiratory Rate')
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY
    c.stay_id
),

-- Step 3: Compute instability index (count of hours with instability)
instability_scores AS (
  SELECT
    c.stay_id,
    COUNT(*) AS vii
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    di.label IN ('Heart Rate', 'MAP', 'Respiratory Rate')
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    AND (
      (di.label = 'Heart Rate' AND ce.valuenum > 100)
      OR (di.label = 'MAP' AND ce.valuenum < 65)
      OR (di.label = 'Respiratory Rate' AND ce.valuenum > 20)
    )
  GROUP BY
    c.stay_id
),

-- Step 4: Compute 95th percentile of VII
percentiles AS (
  SELECT
    APPROX_QUANTILES(vii, 100)[OFFSET(95)] AS vii_95th
  FROM instability_scores
),

-- Step 5: Identify top decile of VII
top_decile AS (
  SELECT
    vii.stay_id,
    vii.vii,
    c.icu_los,
    c.hospital_expire_flag
  FROM instability_scores vii
  JOIN cohort c ON vii.stay_id = c.stay_id
  WHERE vii.vii >= (
    SELECT APPROX_QUANTILES(vii, 10)[OFFSET(9)]
    FROM instability_scores
  )
),

-- Step 6: Controls (not in top decile)
controls AS (
  SELECT
    vii.stay_id,
    vii.vii,
    c.icu_los,
    c.hospital_expire_flag
  FROM instability_scores vii
  JOIN cohort c ON vii.stay_id = c.stay_id
  WHERE vii.vii < (
    SELECT APPROX_QUANTILES(vii, 10)[OFFSET(9)]
    FROM instability_scores
  )
),

-- Step 7: Aggregate stats for top decile and controls
summary_stats AS (
  SELECT
    'Top Decile' AS group_name,
    AVG(v.tachycardia_flag) AS pct_tachycardia,
    AVG(v.hypotension_flag) AS pct_hypotension,
    AVG(v.tachypnea_flag) AS pct_tachypnea,
    AVG(td.icu_los) AS avg_icu_los,
    AVG(td.hospital_expire_flag) AS mortality_rate
  FROM top_decile td
  JOIN vitals v ON td.stay_id = v.stay_id

  UNION ALL

  SELECT
    'Controls' AS group_name,
    AVG(v.tachycardia_flag) AS pct_tachycardia,
    AVG(v.hypotension_flag) AS pct_hypotension,
    AVG(v.tachypnea_flag) AS pct_tachypnea,
    AVG(c.icu_los) AS avg_icu_los,
    AVG(c.hospital_expire_flag) AS mortality_rate
  FROM controls c
  JOIN vitals v ON c.stay_id = v.stay_id
)

-- Final output
SELECT * FROM summary_stats;