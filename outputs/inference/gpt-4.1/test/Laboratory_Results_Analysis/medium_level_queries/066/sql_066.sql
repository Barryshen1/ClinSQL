WITH chest_pain_admissions AS (
  -- Find admissions for men aged 39-49 with chest pain diagnosis
  SELECT
    adm.subject_id,
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON diag.icd_code = dicd.icd_code AND diag.icd_version = dicd.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 39 AND 49
    AND (
      -- ICD-10 chest pain codes (R07.1, R07.2, R07.3, R07.8, R07.9)
      (diag.icd_version = 10 AND diag.icd_code IN ('R071', 'R072', 'R073', 'R078', 'R079'))
      -- ICD-9 chest pain codes (786.50, 786.51, 786.52, 786.59)
      OR (diag.icd_version = 9 AND diag.icd_code IN ('78650', '78651', '78652', '78659'))
      -- Or diagnosis description contains 'chest pain'
      OR LOWER(dicd.long_title) LIKE '%chest pain%'
    )
),
hs_tnt_labitems AS (
  -- Find itemids for hs-TnT
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%troponin t%'
    AND (
      LOWER(label) LIKE '%hs%' OR LOWER(label) LIKE '%high sensitivity%'
    )
),
initial_hs_tnt AS (
  -- Get first hs-TnT value per admission
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN hs_tnt_labitems dlab
      ON l.itemid = dlab.itemid
    JOIN chest_pain_admissions adm
      ON l.hadm_id = adm.hadm_id
  WHERE
    l.valuenum IS NOT NULL
),
first_hs_tnt_per_admission AS (
  -- Only keep the first hs-TnT per admission
  SELECT
    subject_id,
    hadm_id,
    charttime,
    valuenum,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
  FROM
    initial_hs_tnt
),
categorized_hs_tnt AS (
  SELECT
    hadm_id,
    valuenum,
    CASE
      WHEN valuenum < 14 THEN 'Normal'
      WHEN valuenum >= 14 AND valuenum <= 52 THEN 'Borderline'
      WHEN valuenum > 52 THEN 'Myocardial injury'
      ELSE 'Unknown'
    END AS category
  FROM
    first_hs_tnt_per_admission
  WHERE
    rn = 1
),
quantiles_per_category AS (
  SELECT
    category,
    APPROX_QUANTILES(valuenum, 4) AS quantiles
  FROM
    categorized_hs_tnt
  GROUP BY
    category
)
SELECT
  c.category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / COUNT(*) OVER (), 2) AS percentage,
  ROUND(AVG(c.valuenum), 2) AS mean_hs_tnt,
  ROUND(q.quantiles[SAFE_OFFSET(2)], 2) AS median_hs_tnt,
  ROUND(q.quantiles[SAFE_OFFSET(1)], 2) AS hs_tnt_25th,
  ROUND(q.quantiles[SAFE_OFFSET(3)], 2) AS hs_tnt_75th,
  ROUND(q.quantiles[SAFE_OFFSET(3)] - q.quantiles[SAFE_OFFSET(1)], 2) AS hs_tnt_iqr
FROM
  categorized_hs_tnt c
  JOIN quantiles_per_category q
    ON c.category = q.category
GROUP BY
  c.category, q.quantiles
ORDER BY
  CASE c.category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial injury' THEN 3
    ELSE 4
  END;