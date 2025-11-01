WITH initial_troponin AS (
  SELECT
    subject_id,
    hadm_id,
    valuenum
  FROM (
    SELECT
      subject_id,
      hadm_id,
      valuenum,
      -- Use ROW_NUMBER to find the first measurement based on charttime for each admission
      ROW_NUMBER() OVER(PARTITION BY hadm_id ORDER BY charttime) as rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE
      itemid = 50993 -- d_labitems.label = 'Troponin T'
      AND valuenum IS NOT NULL
      AND valueuom = 'ng/mL'
  ) AS ranked_labs
  WHERE
    rn = 1
),

-- CTE to identify admissions with a diagnosis of chest pain or AMI
relevant_admissions AS (
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` USING (icd_code, icd_version)
  WHERE
    LOWER(long_title) LIKE '%chest pain%' OR LOWER(long_title) LIKE '%myocardial infarction%'
)

-- Main query to join, filter, and calculate statistics
SELECT
  APPROX_QUANTILES(it.valuenum, 100)[OFFSET(25)] AS p25_troponin_t,
  APPROX_QUANTILES(it.valuenum, 100)[OFFSET(50)] AS p50_troponin_t,
  APPROX_QUANTILES(it.valuenum, 100)[OFFSET(75)] AS p75_troponin_t,
  MIN(it.valuenum) AS min_troponin_t,
  MAX(it.valuenum) AS max_troponin_t
FROM
  initial_troponin AS it
-- Ensure the admission had the relevant diagnosis
INNER JOIN
  relevant_admissions AS ra
  ON it.hadm_id = ra.hadm_id
-- Join to patient demographics to filter by gender and get anchor dates for age calculation
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON it.subject_id = pat.subject_id
-- Join to admissions to get admittime for accurate age calculation
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  ON it.hadm_id = adm.hadm_id
-- Apply the final cohort filters
WHERE
  pat.gender = 'F'
  -- Calculate age at admission for more accurate filtering
  AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 82 AND 92
  AND it.valuenum > 0.01;