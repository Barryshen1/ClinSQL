WITH cohort AS (
  -- Step 1: Identify the cohort of male patients aged 61-71 admitted for chest pain
  SELECT DISTINCT
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    pat.gender = 'M'
    AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 61 AND 71
    AND LOWER(d_dx.long_title) LIKE '%chest pain%'
),
first_hs_tnt AS (
  -- Step 2: Find the first hs-TnT measurement for each hospital admission
  SELECT
    hadm_id,
    valuenum
  FROM (
    SELECT
      hadm_id,
      charttime,
      valuenum,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE
      itemid = 52559 -- itemid for 'Troponin T, High Sensitivity'
      AND valuenum IS NOT NULL
  )
  WHERE
    rn = 1
),
category_counts AS (
  -- Step 3: Join cohort with lab results, categorize, and count
  SELECT
    CASE
      WHEN tnt.valuenum < 14 THEN 'Normal'
      WHEN tnt.valuenum BETWEEN 14 AND 52 THEN 'Borderline'
      WHEN tnt.valuenum > 52 THEN 'Myocardial Injury'
      ELSE NULL
    END AS tnt_category,
    COUNT(tnt.hadm_id) AS number_of_patients
  FROM
    cohort
  INNER JOIN
    first_hs_tnt AS tnt
    ON cohort.hadm_id = tnt.hadm_id
  WHERE
    CASE
      WHEN tnt.valuenum < 14 THEN 'Normal'
      WHEN tnt.valuenum BETWEEN 14 AND 52 THEN 'Borderline'
      WHEN tnt.valuenum > 52 THEN 'Myocardial Injury'
      ELSE NULL
    END IS NOT NULL
  GROUP BY
    tnt_category
)
-- Step 4: Calculate the final percentage distribution
SELECT
  tnt_category,
  number_of_patients,
  (number_of_patients * 100.0) / SUM(number_of_patients) OVER () AS percentage_distribution
FROM
  category_counts
ORDER BY
  -- Order logically by severity
  CASE tnt_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
  END;