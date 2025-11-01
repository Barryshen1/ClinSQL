WITH pneumonia_admissions AS (
  -- Step 1: Find all unique hospital admissions (hadm_id) with a pneumonia diagnosis.
  SELECT DISTINCT
    dia.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dia
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON dia.icd_code = d.icd_code AND dia.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%pneumonia%'
),
peak_creatinine_admissions AS (
  -- Step 2: For each male pneumonia admission, find the peak serum creatinine value.
  SELECT
    le.hadm_id,
    MAX(le.valuenum) AS peak_serum_creatinine
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  INNER JOIN
    pneumonia_admissions AS pa ON le.hadm_id = pa.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p ON le.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND le.itemid = 50912 -- 50912 is the itemid for Creatinine
    AND le.valuenum IS NOT NULL -- Ensure the value is a number for aggregation
  GROUP BY
    le.hadm_id
)
-- Step 3: Calculate the standard deviation of the peak creatinine values across all included admissions.
SELECT
  STDDEV(peak_serum_creatinine) AS stddev_peak_creatinine
FROM
  peak_creatinine_admissions;