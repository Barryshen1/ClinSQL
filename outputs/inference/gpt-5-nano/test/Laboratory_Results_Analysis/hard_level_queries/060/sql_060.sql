WITH
-- 1) Cardiac arrest admissions in the female 52-62 cohort
CA_cohort AS (
  SELECT a.subject_id,
         a.hadm_id,
         a.admittime,
         a.dischtime,
         a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
    ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  WHERE LOWER(ddi.long_title) LIKE '%cardiac arrest%'
    AND p.gender = 'F'
    AND (
          (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 52 AND 62
        )
),
-- 2) General female 52-62 admissions (no cardiac arrest for the admission)
General_cohort AS (
  SELECT a.subject_id,
         a.hadm_id,
         a.admittime,
         a.dischtime,
         a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
    ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  WHERE LOWER(ddi.long_title) NOT LIKE '%cardiac arrest%'
    AND p.gender = 'F'
    AND (
          (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 52 AND 62
        )
),
-- 3) Instability score per admission (first 48h) for CA cohort
CA_instability AS (
  SELECT c.hadm_id,
         SUM( CASE
                -- Heart Rate
                WHEN LOWER(di.label) LIKE '%heart rate%' AND ce.valuenum IS NOT NULL
                     AND (ce.valuenum < 60 OR ce.valuenum > 100) THEN 1
                -- Respiratory Rate
                WHEN LOWER(di.label) LIKE '%respiratory rate%' AND ce.valuenum IS NOT NULL
                     AND (ce.valuenum < 12 OR ce.valuenum > 24) THEN 1
                -- Systolic BP
                WHEN LOWER(di.label) LIKE '%systolic blood pressure%' AND ce.valuenum IS NOT NULL
                     AND (ce.valuenum < 90 OR ce.valuenum > 180) THEN 1
                -- Mean Arterial Pressure
                WHEN LOWER(di.label) LIKE '%mean arterial pressure%' AND ce.valuenum IS NOT NULL
                     AND (ce.valuenum < 65 OR ce.valuenum > 105) THEN 1
                -- Temperature
                WHEN LOWER(di.label) LIKE '%temperature%' AND ce.valuenum IS NOT NULL
                     AND (ce.valuenum < 36.0 OR ce.valuenum > 38.3) THEN 1
                -- SpO2 / Oxygen saturation
                WHEN (LOWER(di.label) LIKE '%spo2%' OR LOWER(di.label) LIKE '%oxygen saturation%')
                     AND ce.valuenum IS NOT NULL
                     AND ce.valuenum < 92 THEN 1
                ELSE 0
              END) AS instability_score
  FROM CA_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
         ON ce.subject_id = c.subject_id AND ce.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
         ON ce.itemid = di.itemid
  WHERE ce.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.hadm_id
),
CA_LOS AS (
  SELECT a.hadm_id,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN CA_instability AS ci ON a.hadm_id = ci.hadm_id
),
CA_MORT AS (
  SELECT hadm_id,
         MAX(hospital_expire_flag) AS died
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE hadm_id IN (SELECT hadm_id FROM CA_instability)
  GROUP BY hadm_id
),
CA_CRIT_LAB AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.subject_id = a.subject_id AND le.hadm_id = a.hadm_id
  WHERE le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND LOWER(le.flag) LIKE '%critical%'
  GROUP BY a.hadm_id
),
CA_SUMMARY AS (
  SELECT
    'CA_fem52_62' AS cohort_tag,
    COUNT(*) AS n_admissions,
    -- Q1 of instability_score across CA cohort (first 48h)
    (SELECT quantiles[OFFSET(1)]
     FROM (
       SELECT APPROX_QUANTILES(COALESCE(ci.instability_score, 0), 4) AS quantiles
       FROM CA_instability ci
       WHERE ci.hadm_id IN (SELECT hadm_id FROM CA_cohort)
     )) AS instability_q1,
    -- Median (50th percentile) of instability_score across CA cohort
    (SELECT quantiles[OFFSET(2)]
     FROM (
       SELECT APPROX_QUANTILES(COALESCE(ci.instability_score, 0), 4) AS quantiles
       FROM CA_instability ci
       WHERE ci.hadm_id IN (SELECT hadm_id FROM CA_cohort)
     )) AS instability_median,
    -- Median LOS for CA cohort
    (SELECT quantiles[OFFSET(2)]
     FROM (
       SELECT APPROX_QUANTILES(los_days, 4) AS quantiles
       FROM CA_LOS
     )) AS median_los_days,
    -- Mortality rate (died flag)
    (SELECT AVG(CAST(died AS FLOAT64))
     FROM CA_MORT) AS mortality_rate,
    -- Number with critical labs within 48h
    (SELECT COUNT(*) FROM CA_CRIT_LAB) AS n_admissions_with_critical_lab
  FROM CA_cohort
),
-- 4) General female 52-62 instability and outcomes
General_instability AS (
  SELECT g.hadm_id,
         SUM( CASE
                WHEN LOWER(di.label) LIKE '%heart rate%' AND ce.valuenum IS NOT NULL
                     AND (ce.valuenum < 60 OR ce.valuenum > 100) THEN 1
                WHEN LOWER(di.label) LIKE '%respiratory rate%' AND ce.valuenum IS NOT NULL
                     AND (ce.valuenum < 12 OR ce.valuenum > 24) THEN 1
                WHEN LOWER(di.label) LIKE '%systolic blood pressure%' AND ce.valuenum IS NOT NULL
                     AND (ce.valuenum < 90 OR ce.valuenum > 180) THEN 1
                WHEN LOWER(di.label) LIKE '%mean arterial pressure%' AND ce.valuenum IS NOT NULL
                     AND (ce.valuenum < 65 OR ce.valuenum > 105) THEN 1
                WHEN LOWER(di.label) LIKE '%temperature%' AND ce.valuenum IS NOT NULL
                     AND (ce.valuenum < 36.0 OR ce.valuenum > 38.3) THEN 1
                WHEN LOWER(di.label) LIKE '%spo2%' OR LOWER(di.label) LIKE '%oxygen saturation%' AND ce.valuenum IS NOT NULL
                     AND ce.valuenum < 92 THEN 1
                ELSE 0
              END) AS instability_score
  FROM General_cohort g
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
         ON ce.subject_id = g.subject_id AND ce.hadm_id = g.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
         ON ce.itemid = di.itemid
  WHERE ce.charttime BETWEEN g.admittime AND TIMESTAMP_ADD(g.admittime, INTERVAL 48 HOUR)
  GROUP BY g.hadm_id
),
General_LOS AS (
  SELECT hadm_id,
         TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE hadm_id IN (SELECT hadm_id FROM General_cohort)
),
General_MORT AS (
  SELECT hadm_id,
         MAX(hospital_expire_flag) AS died
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE hadm_id IN (SELECT hadm_id FROM General_cohort)
  GROUP BY hadm_id
),
General_CRIT_LAB AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.subject_id = a.subject_id AND le.hadm_id = a.hadm_id
  WHERE le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND LOWER(le.flag) LIKE '%critical%'
  GROUP BY a.hadm_id
),
General_SUMMARY AS (
  SELECT
    'General_fem52_62' AS cohort_tag,
    COUNT(*) AS n_admissions,
    -- Q1 of instability_score across General cohort
    (SELECT quantiles[OFFSET(1)]
     FROM (
       SELECT APPROX_QUANTILES(COALESCE(gi.instability_score, 0), 4) AS quantiles
       FROM General_instability gi
       WHERE gi.hadm_id IN (SELECT hadm_id FROM General_cohort)
     )) AS instability_q1,
    -- Median (50th percentile) of instability_score across General cohort
    (SELECT quantiles[OFFSET(2)]
     FROM (
       SELECT APPROX_QUANTILES(COALESCE(gi.instability_score, 0), 4) AS quantiles
       FROM General_instability gi
       WHERE gi.hadm_id IN (SELECT hadm_id FROM General_cohort)
     )) AS instability_median,
    -- Median LOS for General cohort
    (SELECT quantiles[OFFSET(2)]
     FROM (
       SELECT APPROX_QUANTILES(los_days, 4) AS quantiles
       FROM General_LOS
     )) AS median_los_days,
    -- Mortality rate
    (SELECT AVG(CAST(died AS FLOAT64))
     FROM General_MORT) AS mortality_rate,
    -- Number with critical labs within 48h
    (SELECT COUNT(*) FROM General_CRIT_LAB) AS n_admissions_with_critical_lab
  FROM General_cohort
)

-- Final: return one row per cohort
SELECT *
FROM CA_SUMMARY
UNION ALL
SELECT *
FROM General_SUMMARY;