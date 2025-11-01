WITH ami_chest_pain_admissions AS (
  -- Find all hospital admissions with a diagnosis related to AMI or Chest Pain
  SELECT DISTINCT
    diag.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON diag.icd_code = d.icd_code
    AND diag.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%myocardial infarction%'
    OR LOWER(d.long_title) LIKE '%chest pain%'
), initial_troponin AS (
  -- Find the first Troponin T measurement for each hospital admission
  SELECT
    le.hadm_id,
    le.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Troponin T'
    AND le.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
), cohort AS (
  -- Assemble the final cohort of admissions that meet all criteria
  SELECT
    p.subject_id,
    p.anchor_age,
    ad.hadm_id,
    DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
    it.valuenum AS initial_troponin_t
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    ON p.subject_id = ad.subject_id
  INNER JOIN
    ami_chest_pain_admissions AS dx
    ON ad.hadm_id = dx.hadm_id
  INNER JOIN
    initial_troponin AS it
    ON ad.hadm_id = it.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
), patient_level_age AS (
  -- Create a distinct list of patients and their age from the cohort
  SELECT DISTINCT
    subject_id,
    anchor_age
  FROM
    cohort
)
-- Final aggregation to produce the summary statistics
SELECT
  COUNT(DISTINCT subject_id) AS number_of_patients,
  (
    SELECT
      AVG(anchor_age)
    FROM
      patient_level_age
  ) AS mean_age,
  AVG(los_days) AS mean_los_days,
  MIN(initial_troponin_t) AS min_initial_troponin_t,
  AVG(initial_troponin_t) AS mean_initial_troponin_t,
  MAX(initial_troponin_t) AS max_initial_troponin_t,
  STDDEV(initial_troponin_t) AS stddev_initial_troponin_t
FROM
  cohort;