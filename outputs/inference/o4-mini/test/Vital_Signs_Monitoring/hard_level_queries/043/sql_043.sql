WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.subject_id = adm.subject_id
    AND icu.hadm_id = adm.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON icu.subject_id = di.subject_id
    AND icu.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dxd
    ON di.icd_code = dxd.icd_code
    AND di.icd_version = dxd.icd_version
  WHERE
    p.anchor_age BETWEEN 40 AND 50
    AND p.gender = 'M'
    AND LOWER(dxd.long_title) LIKE '%respiratory failure%'
    -- keep only diagnoses for this admission
    AND di.seq_num = 1
),
vitals_48h AS (
  SELECT
    c.stay_id,
    di.label,
    ce.valuenum
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id
    AND c.hadm_id = ce.hadm_id
    AND c.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    ce.charttime BETWEEN c.intime
      AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
    AND di.label IN ('Mean Arterial Pressure', 'Heart Rate')
    AND ce.valuenum IS NOT NULL
),
per_stay_burden AS (
  SELECT
    stay_id,
    SUM(CASE WHEN label = 'Mean Arterial Pressure' AND valuenum < 65 THEN 1 ELSE 0 END) AS hypo_count,
    SUM(CASE WHEN label = 'Mean Arterial Pressure' THEN 1 ELSE 0 END)                   AS map_count,
    SUM(CASE WHEN label = 'Heart Rate' AND valuenum > 100 THEN 1 ELSE 0 END)             AS tachy_count,
    SUM(CASE WHEN label = 'Heart Rate' THEN 1 ELSE 0 END)                               AS hr_count
  FROM
    vitals_48h
  GROUP BY
    stay_id
  HAVING
    map_count > 0
    AND hr_count > 0
),
metrics AS (
  SELECT
    b.stay_id,
    b.hypo_count / b.map_count    AS hypotensive_burden,
    b.tachy_count / b.hr_count    AS tachycardic_burden,
    (b.hypo_count / b.map_count) + (b.tachy_count / b.hr_count) AS vii,
    c.los,
    c.hospital_expire_flag
  FROM
    per_stay_burden b
  JOIN
    cohort c
    ON b.stay_id = c.stay_id
)
SELECT
  -- Vital Instability Index distribution
  STDDEV(vii)                                                  AS vii_stddev,
  -- approximate quantiles returns an array; extract the desired percentiles
  APPROX_QUANTILES(vii, 100)[OFFSET(25)]                       AS vii_p25,
  APPROX_QUANTILES(vii, 100)[OFFSET(50)]                       AS vii_p50,
  APPROX_QUANTILES(vii, 100)[OFFSET(75)]                       AS vii_p75,
  APPROX_QUANTILES(vii, 100)[OFFSET(95)]                       AS vii_p95,
  -- average burdens, LOS, and mortality
  AVG(hypotensive_burden)                                      AS avg_hypotensive_burden,
  AVG(tachycardic_burden)                                      AS avg_tachycardic_burden,
  AVG(los)                                                     AS avg_icu_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64))                   AS mortality_rate
FROM
  metrics;