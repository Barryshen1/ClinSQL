WITH pneumonia_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS did
    ON di.icd_code = did.icd_code
    AND di.icd_version = did.icd_version
  WHERE
    LOWER(did.long_title) LIKE '%pneumonia%'
),

-- CTE to calculate the 24-hour average creatinine for each relevant admission day
daily_avg_creatinine AS (
  SELECT
    AVG(le.valuenum) AS avg_creatinine_24h
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  -- Join to get admission time
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON p.subject_id = adm.subject_id
  -- Join to filter for pneumonia stays
  JOIN pneumonia_admissions AS pa
    ON adm.hadm_id = pa.hadm_id
  -- Join to get lab measurements
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON adm.hadm_id = le.hadm_id
  WHERE
    -- 1. Filter for female patients
    p.gender = 'F'
    -- 2. Filter for serum creatinine (itemid 50912)
    AND le.itemid = 50912
    -- 3. Ensure the value is a number for calculation
    AND le.valuenum IS NOT NULL
  -- Group by patient, admission, and each 24-hour window since admission
  GROUP BY
    p.subject_id,
    adm.hadm_id,
    -- This calculation creates a 'day number' for each lab event relative to the admission time
    FLOOR(TIMESTAMP_DIFF(le.charttime, adm.admittime, HOUR) / 24)
)

-- Final step: find the minimum value from all the calculated 24-hour averages
SELECT
  MIN(avg_creatinine_24h) AS min_24hr_avg_serum_creatinine
FROM
  daily_avg_creatinine;