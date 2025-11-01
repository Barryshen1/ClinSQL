WITH
  -- Step 1: Identify the cohort of male patients aged 45-55 admitted for pneumonia.
  patient_cohort AS (
    SELECT DISTINCT
      adm.hadm_id,
      adm.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
      ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
    WHERE
      pat.gender = 'M'
      AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 45 AND 55
      AND LOWER(d_dx.long_title) LIKE '%pneumonia%'
  ),
  -- Step 2: For each admission in the cohort, calculate the average serum creatinine
  -- measured within the first 24 hours.
  avg_creatinine_per_admission AS (
    SELECT
      pc.hadm_id,
      AVG(le.valuenum) AS avg_creatinine
    FROM patient_cohort AS pc
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON pc.hadm_id = le.hadm_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
      ON le.itemid = dli.itemid
    WHERE
      -- Identify serum creatinine measurements
      dli.label = 'Creatinine' AND dli.fluid = 'Blood'
      -- Ensure the value is a number
      AND le.valuenum IS NOT NULL
      -- Filter for the first 24 hours of the admission
      AND le.charttime BETWEEN pc.admittime AND DATETIME_ADD(pc.admittime, INTERVAL 24 HOUR)
    GROUP BY
      pc.hadm_id
  )
-- Step 3: Calculate the standard deviation of the average creatinine values across the cohort.
SELECT
  STDDEV_SAMP(avg_creatinine) AS sd_of_avg_serum_creatinine
FROM avg_creatinine_per_admission;