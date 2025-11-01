WITH
  -- Step 1: Identify the target patient cohort (male, aged 37-47 in the ICU)
  cohort AS (
    SELECT
      icu.stay_id
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON icu.subject_id = p.subject_id
    WHERE
      p.gender = 'M'
      AND (
        (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) + p.anchor_age
      ) BETWEEN 37 AND 47
  ),

  -- Step 2: Identify ICU stays where noninvasive ventilation (CPAP/BiPAP) was used
  niv_stays AS (
    SELECT DISTINCT
      stay_id
    FROM
      `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE
      itemid = 224684 -- Ventilator Mode
      AND value = 'CPAP/BIPAP'
  ),

  -- Step 3: Calculate the maximum diastolic blood pressure recorded for each ICU stay
  max_dbp_per_stay AS (
    SELECT
      stay_id,
      MAX(valuenum) AS max_diastolic_bp
    FROM
      `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE
      itemid IN (
        220051, -- Arterial Blood Pressure diastolic
        220180, -- Non Invasive Blood Pressure diastolic
        225310, -- ART BP Diastolic
        224643, -- Manual Blood Pressure Diastolic Left
        224644, -- Manual Blood Pressure Diastolic Right
        227242 -- Manual Blood Pressure Diastolic
      )
      AND valuenum IS NOT NULL
      AND valuenum > 0 AND valuenum < 300 -- Apply a plausible range filter
    GROUP BY
      stay_id
  )

-- Step 4: Join the cohort, intervention, and measurement to calculate the final percentile
SELECT
  PERCENTILE_CONT(dbp.max_diastolic_bp, 0.25) OVER () AS p25_max_diastolic_bp
FROM
  cohort
INNER JOIN
  niv_stays
  ON cohort.stay_id = niv_stays.stay_id
INNER JOIN
  max_dbp_per_stay AS dbp
  ON cohort.stay_id = dbp.stay_id
LIMIT 1;