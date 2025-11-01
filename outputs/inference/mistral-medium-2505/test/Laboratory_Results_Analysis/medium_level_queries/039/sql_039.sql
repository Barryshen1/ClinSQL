WITH
-- Get female patients aged 87-97
eligible_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 87 AND 97
),

-- Get admissions with chest pain diagnosis
chest_pain_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM eligible_patients)
    AND LOWER(di.long_title) LIKE '%chest pain%'
),

-- Get hs-TnT measurements (first per admission)
hs_tnt_measurements AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS measurement_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  WHERE
    l.hadm_id IN (SELECT hadm_id FROM chest_pain_admissions)
    AND dl.label = 'High Sensitivity Troponin T'
    AND l.valuenum IS NOT NULL
),

-- Get only the first measurement per admission
index_hs_tnt AS (
  SELECT
    subject_id,
    hadm_id,
    valuenum AS hs_tnt_value
  FROM
    hs_tnt_measurements
  WHERE
    measurement_rank = 1
),

-- Categorize the hs-TnT values
categorized_hs_tnt AS (
  SELECT
    hs_tnt_value,
    CASE
      WHEN hs_tnt_value <= 0.04 THEN 'Normal'
      WHEN hs_tnt_value > 0.04 AND hs_tnt_value <= 0.1 THEN 'Borderline'
      WHEN hs_tnt_value > 0.1 THEN 'Injury'
    END AS category
  FROM
    index_hs_tnt
)

-- Final statistics
SELECT
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(hs_tnt_value), 4) AS mean,
  ROUND(PERCENTILE_CONT(hs_tnt_value, 0.5) OVER (PARTITION BY category), 4) AS median,
  ROUND(PERCENTILE_CONT(hs_tnt_value, 0.25) OVER (PARTITION BY category), 4) AS q1,
  ROUND(PERCENTILE_CONT(hs_tnt_value, 0.75) OVER (PARTITION BY category), 4) AS q3,
  ROUND(PERCENTILE_CONT(hs_tnt_value, 0.75) OVER (PARTITION BY category) -
        PERCENTILE_CONT(hs_tnt_value, 0.25) OVER (PARTITION BY category), 4) AS iqr
FROM
  categorized_hs_tnt
GROUP BY
  category, hs_tnt_value
ORDER BY
  category;