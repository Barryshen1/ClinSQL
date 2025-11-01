with chest pain or an acute myocardial infarction (AMI).
-- For this cohort, it finds their first Troponin T measurement, and among those with a value > 0.01 ng/mL,
-- it calculates the mean, standard deviation, minimum, and maximum values.

WITH
-- CTE 1: Find admissions for female patients aged 58-68 with a diagnosis of chest pain or AMI.
-- This combines the age, gender, and diagnosis criteria into a single, efficient cohort definition.
PatientCohort AS (
  SELECT DISTINCT ad.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ad.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON ad.hadm_id = dx.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    -- Calculate age at admission and filter for the 58-68 range
    (DATETIME_DIFF(ad.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age) BETWEEN 58 AND 68
    -- Filter for female patients as per the clinical question
    AND p.gender = 'F'
    -- Filter for relevant diagnoses using case-insensitive search
    AND (
      LOWER(d_dx.long_title) LIKE '%chest pain%'
      OR LOWER(d_dx.long_title) LIKE '%myocardial infarction%'
    )
),

-- CTE 2: For the above cohort, find the first Troponin T measurement for each admission.
FirstTroponin AS (
  SELECT
    hadm_id,
    valuenum
  FROM (
    SELECT
      le.hadm_id,
      le.valuenum,
      -- Rank troponin tests by time to find the first one for each admission
      ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    -- Pre-filter the large labevents table by joining with our specific patient cohort
    INNER JOIN PatientCohort AS cohort
      ON le.hadm_id = cohort.hadm_id
    WHERE
      le.itemid = 51003 -- 51003 is the itemid for 'Troponin T'
      AND le.valuenum IS NOT NULL
      AND le.valueuom = 'ng/mL'
  ) AS ranked_trop
  WHERE
    rn = 1 -- Select only the first measurement
)

-- Final query: Calculate statistics on the first troponin measurements that are > 0.01 ng/mL.
SELECT
  AVG(valuenum) AS mean_troponin_t,
  STDDEV(valuenum) AS stddev_troponin_t,
  MIN(valuenum) AS min_troponin_t,
  MAX(valuenum) AS max_troponin_t
FROM
  FirstTroponin
WHERE
  valuenum > 0.01;