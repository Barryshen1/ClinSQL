WITH
-- Define age range and gender
age_gender_filter AS (
  SELECT
    subject_id,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 67 AND 77
),

-- Identify ACS patients (ICD-10 codes I20-I25)
acs_patients AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    age_gender_filter a ON d.subject_id = a.subject_id
  WHERE
    d.icd_code LIKE 'I2%'
    AND d.icd_version = 10
),

-- Identify patients with ICU stays
icu_patients AS (
  SELECT DISTINCT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime AS icu_intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    acs_patients a ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
),

-- Calculate SAPS-II score components (simplified version)
saps_ii_components AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    MAX(CASE WHEN di.itemid IN (220045, 220046) THEN c.valuenum ELSE NULL END) AS heart_rate,
    MAX(CASE WHEN di.itemid IN (220050, 220051) THEN c.valuenum ELSE NULL END) AS systolic_bp,
    MAX(CASE WHEN di.itemid IN (220210, 220211) THEN c.valuenum ELSE NULL END) AS temperature,
    MAX(CASE WHEN di.itemid IN (220224, 220225) THEN c.valuenum ELSE NULL END) AS pao2_fio2,
    MAX(CASE WHEN di.itemid IN (220277, 220278) THEN c.valuenum ELSE NULL END) AS urine_output,
    MAX(CASE WHEN di.itemid IN (220621, 220622) THEN c.valuenum ELSE NULL END) AS sodium,
    MAX(CASE WHEN di.itemid IN (220635, 220636) THEN c.valuenum ELSE NULL END) AS potassium,
    MAX(CASE WHEN di.itemid IN (220649, 220650) THEN c.valuenum ELSE NULL END) AS bicarbonate,
    MAX(CASE WHEN di.itemid IN (220689, 220690) THEN c.valuenum ELSE NULL END) AS bilirubin,
    MAX(CASE WHEN di.itemid IN (220739, 220740) THEN c.valuenum ELSE NULL END) AS gcs
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON c.itemid = di.itemid
  JOIN
    icu_patients i ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  WHERE
    c.charttime BETWEEN i.icu_intime AND DATETIME_ADD(i.icu_intime, INTERVAL 24 HOUR)
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id
),

-- Calculate simplified SAPS-II score
saps_ii_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    -- Simplified SAPS-II calculation (actual formula would be more complex)
    (heart_rate * 0.003) +
    (systolic_bp * 0.002) +
    (temperature * 0.01) +
    (pao2_fio2 * 0.001) +
    (urine_output * 0.0001) +
    (sodium * 0.001) +
    (potassium * 0.001) +
    (bicarbonate * 0.001) +
    (bilirubin * 0.001) +
    (gcs * 0.01) AS saps_ii_score
  FROM
    saps_ii_components
),

-- Calculate 30-day mortality
mortality_30day AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    CASE
      WHEN a.deathtime IS NOT NULL AND
           TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) <= 30 THEN 1
      WHEN p.dod IS NOT NULL AND
           TIMESTAMP_DIFF(p.dod, a.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS died_within_30days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    icu_patients i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
),

-- Identify cardiac complications (ICD-10 I20-I52)
cardiac_complications AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id,
    1 AS has_cardiac_complication
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    icu_patients i ON d.subject_id = i.subject_id AND d.hadm_id = i.hadm_id
  WHERE
    d.icd_code BETWEEN 'I20' AND 'I52'
    AND d.icd_version = 10
),

-- Identify neurologic complications (ICD-10 G00-G99)
neurologic_complications AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id,
    1 AS has_neurologic_complication
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    icu_patients i ON d.subject_id = i.subject_id AND d.hadm_id = i.hadm_id
  WHERE
    d.icd_code BETWEEN 'G00' AND 'G99'
    AND d.icd_version = 10
),

-- Calculate LOS for survivors
los_survivors AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    icu_patients i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  JOIN
    mortality_30day m ON a.subject_id = m.subject_id AND a.hadm_id = m.hadm_id
  WHERE
    m.died_within_30days = 0
),

-- Age-matched general inpatients (no ACS)
general_inpatients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    age_gender_filter ag ON a.subject_id = ag.subject_id
  WHERE
    a.hadm_id NOT IN (SELECT hadm_id FROM acs_patients)
),

-- Cardiac complications in general inpatients
general_cardiac_complications AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id,
    1 AS has_cardiac_complication
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    general_inpatients g ON d.subject_id = g.subject_id AND d.hadm_id = g.hadm_id
  WHERE
    d.icd_code BETWEEN 'I20' AND 'I52'
    AND d.icd_version = 10
),

-- Neurologic complications in general inpatients
general_neurologic_complications AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id,
    1 AS has_neurologic_complication
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    general_inpatients g ON d.subject_id = g.subject_id AND d.hadm_id = g.hadm_id
  WHERE
    d.icd_code BETWEEN 'G00' AND 'G99'
    AND d.icd_version = 10
),

-- LOS for general inpatients
general_los AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    general_inpatients g ON a.subject_id = g.subject_id AND a.hadm_id = g.hadm_id
),

-- Calculate percentiles for comparison
percentile_comparison AS (
  SELECT
    PERCENTILE_CONT(s.saps_ii_score, 0.5) OVER() AS saps_ii_median,
    PERCENTILE_CONT(m.died_within_30days, 0.5) OVER() AS mortality_median,
    PERCENTILE_CONT(l.los_days, 0.5) OVER() AS los_median
  FROM
    saps_ii_scores s
  JOIN
    mortality_30day m ON s.subject_id = m.subject_id AND s.hadm_id = m.hadm_id
  JOIN
    los_survivors l ON s.subject_id = l.subject_id AND s.hadm_id = l.hadm_id
  LIMIT 1
)

-- Final results
SELECT
  -- ACS group metrics
  AVG(s.saps_ii_score) AS mean_saps_ii_score,
  AVG(m.died_within_30days) * 100 AS percent_30day_mortality,
  AVG(cc.has_cardiac_complication) * 100 AS percent_cardiac_complications,
  AVG(nc.has_neurologic_complication) * 100 AS percent_neurologic_complications,
  AVG(l.los_days) AS mean_los_survivors,

  -- General inpatient metrics
  AVG(gcc.has_cardiac_complication) * 100 AS general_percent_cardiac_complications,
  AVG(gnc.has_neurologic_complication) * 100 AS general_percent_neurologic_complications,
  AVG(gl.los_days) AS general_mean_los,

  -- Percentile comparisons
  (SELECT saps_ii_median FROM percentile_comparison) AS saps_ii_percentile,
  (SELECT mortality_median FROM percentile_comparison) AS mortality_percentile,
  (SELECT los_median FROM percentile_comparison) AS los_percentile

FROM
  saps_ii_scores s
JOIN
  mortality_30day m ON s.subject_id = m.subject_id AND s.hadm_id = m.hadm_id
LEFT JOIN
  cardiac_complications cc ON s.subject_id = cc.subject_id AND s.hadm_id = cc.hadm_id
LEFT JOIN
  neurologic_complications nc ON s.subject_id = nc.subject_id AND s.hadm_id = nc.hadm_id
LEFT JOIN
  los_survivors l ON s.subject_id = l.subject_id AND s.hadm_id = l.hadm_id
LEFT JOIN
  general_cardiac_complications gcc ON s.subject_id = gcc.subject_id AND s.hadm_id = gcc.hadm_id
LEFT JOIN
  general_neurologic_complications gnc ON s.subject_id = gnc.subject_id AND s.hadm_id = gnc.hadm_id
LEFT JOIN
  general_los gl ON s.subject_id = gl.subject_id AND s.hadm_id = gl.hadm_id;