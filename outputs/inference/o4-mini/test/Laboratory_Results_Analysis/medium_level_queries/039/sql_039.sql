WITH cohort AS (
  -- female patients age 87-97 with a chest pain diagnosis on admission
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
      AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
      ON d.icd_code = dicd.icd_code
      AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND LOWER(dicd.long_title) LIKE '%chest pain%'
),

hs_tnt_items AS (
  -- identify likely high-sensitivity Troponin T lab itemids
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%high sensitivity%'
    AND LOWER(label) LIKE '%troponin%'
    AND LOWER(label) LIKE '%t%'
),

first_hs_tnt AS (
  -- first troponin measurement per admission
  SELECT
    c.subject_id,
    c.hadm_id,
    le.valuenum AS tnt_value,
    CASE
      WHEN le.valuenum <= 0.04 THEN 'Normal'
      WHEN le.valuenum <= 0.10 THEN 'Borderline'
      ELSE 'Injury'
    END AS category
  FROM
    cohort AS c
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON c.subject_id = le.subject_id
      AND c.hadm_id = le.hadm_id
    JOIN hs_tnt_items AS hi
      ON le.itemid = hi.itemid
  WHERE
    le.valuenum IS NOT NULL
    AND le.charttime >= c.admittime
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY c.hadm_id
      ORDER BY le.charttime
    ) = 1
),

stats AS (
  -- aggregate statistics by category
  SELECT
    category,
    COUNT(*) AS n_patients,
    AVG(tnt_value) AS mean_tnt,
    APPROX_QUANTILES(tnt_value, 4) AS quantiles
  FROM
    first_hs_tnt
  GROUP BY
    category
)

SELECT
  category,
  n_patients,
  ROUND(100.0 * n_patients / SUM(n_patients) OVER (), 1) AS pct_of_cohort,
  ROUND(mean_tnt, 3) AS mean_tnt,
  quantiles[OFFSET(2)] AS median_tnt,
  ROUND(quantiles[OFFSET(3)] - quantiles[OFFSET(1)], 3) AS iqr_tnt
FROM
  stats
ORDER BY
  CASE category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Injury' THEN 3
    ELSE 4
  END;