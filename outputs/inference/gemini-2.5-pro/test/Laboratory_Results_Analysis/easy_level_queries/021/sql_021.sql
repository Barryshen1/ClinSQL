WITH
  -- Step 1: Identify all hospital admissions with a diagnosis of pneumonia.
  PneumoniaAdmissions AS (
    SELECT DISTINCT
      diag.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_diag
      ON diag.icd_code = d_diag.icd_code
      AND diag.icd_version = d_diag.icd_version
    WHERE
      LOWER(d_diag.long_title) LIKE '%pneumonia%'
  ),
  -- Step 2: Correlate pneumonia admissions with male patients and get their discharge times.
  MalePneumoniaAdmissions AS (
    SELECT
      adm.hadm_id,
      adm.dischtime
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
      INNER JOIN PneumoniaAdmissions AS pa
      ON adm.hadm_id = pa.hadm_id
    WHERE
      pat.gender = 'M'
  ),
  -- Step 3: Find the last glucose measurement within 24 hours of discharge for each admission.
  LastGlucoseAtDischarge AS (
    SELECT
      le.valuenum,
      -- Rank measurements by time to find the last one for each admission
      ROW_NUMBER() OVER (
        PARTITION BY le.hadm_id
        ORDER BY
          le.charttime DESC
      ) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      INNER JOIN MalePneumoniaAdmissions AS mpa
      ON le.hadm_id = mpa.hadm_id
    WHERE
      -- ItemIDs for Glucose in Serum/Plasma (50931) and Blood (50809)
      le.itemid IN (50931, 50809)
      AND le.valuenum IS NOT NULL
      -- Filter for measurements taken in the 24 hours leading up to discharge
      AND le.charttime BETWEEN DATETIME_SUB(mpa.dischtime, INTERVAL 24 HOUR) AND mpa.dischtime
  )
-- Step 4: Calculate the 75th percentile of the final glucose values.
SELECT
  APPROX_QUANTILES(valuenum, 100) [
OFFSET
  (75)] AS glucose_75th_percentile_at_discharge
FROM
  LastGlucoseAtDischarge
WHERE
  -- Only consider the last measurement for each admission
  rn = 1;