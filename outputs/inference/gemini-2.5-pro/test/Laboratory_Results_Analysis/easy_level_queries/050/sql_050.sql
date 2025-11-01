WITH
  -- Step 1: Identify all hospital admissions with a diagnosis of sepsis.
  sepsis_admissions AS (
    SELECT DISTINCT
      dx.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
        ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
    WHERE
      LOWER(d_dx.long_title) LIKE '%sepsis%'
  ),

  -- Step 2: Get the first platelet count within 24 hours for each male sepsis admission.
  admission_platelets AS (
    SELECT
      adm.hadm_id,
      le.valuenum,
      -- Rank platelet counts by time to find the first one per admission
      ROW_NUMBER() OVER (PARTITION BY adm.hadm_id ORDER BY le.charttime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON adm.hadm_id = le.hadm_id
    WHERE
      -- Filter for the sepsis admissions identified in the first CTE
      adm.hadm_id IN (SELECT hadm_id FROM sepsis_admissions)
      -- Filter for male patients
      AND pat.gender = 'M'
      -- Filter for Platelet Count (itemid 51265)
      AND le.itemid = 51265
      -- Filter for non-null numeric values
      AND le.valuenum IS NOT NULL
      -- Define the "admission" window as the first 24 hours
      AND le.charttime BETWEEN adm.admittime AND TIMESTAMP_ADD(
        adm.admittime,
        INTERVAL 24 HOUR
      )
  )

-- Step 3: Calculate the standard deviation of the first admission platelet counts.
SELECT
  STDDEV(valuenum) AS admission_platelet_stddev
FROM
  admission_platelets
WHERE
  -- Only include the first measurement for each admission
  rn = 1;