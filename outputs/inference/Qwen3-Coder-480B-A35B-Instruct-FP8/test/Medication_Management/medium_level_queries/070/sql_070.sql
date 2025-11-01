WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    p.anchor_age,
    i.intime,
    i.outtime,
    DATETIME_ADD(i.intime, INTERVAL 48 HOUR) AS first_48_end,
    DATETIME_SUB(i.outtime, INTERVAL 12 HOUR) AS last_12_start
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),

first_icu_stay AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    first_48_end,
    last_12_start
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM cohort
  )
  WHERE rn = 1
),

drug_mappings AS (
  SELECT
    hadm_id,
    starttime,
    stoptime,
    LOWER(drug) AS drug_name,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(drug), r'metformin') THEN 'metformin'
      WHEN REGEXP_CONTAINS(LOWER(drug), r'glipizide|glyburide|glimepiride') THEN 'sulfonylurea'
      WHEN REGEXP_CONTAINS(LOWER(drug), r'sitagliptin|saxagliptin|linagliptin|alogliptin') THEN 'dpp4'
      WHEN REGEXP_CONTAINS(LOWER(drug), r'empagliflozin|dapagliflozin|canagliflozin') THEN 'sglt2'
      ELSE NULL
    END AS drug_class
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    REGEXP_CONTAINS(LOWER(drug), r'metformin|glipizide|glyburide|glimepiride|sitagliptin|saxagliptin|linagliptin|alogliptin|empagliflozin|dapagliflozin|canagliflozin')
),

first_window_drugs AS (
  SELECT DISTINCT
    f.hadm_id,
    d.drug_class
  FROM
    first_icu_stay f
  JOIN
    drug_mappings d
  ON
    f.hadm_id = d.hadm_id
  WHERE
    d.starttime BETWEEN f.intime AND LEAST(f.first_48_end, f.outtime)
),

last_window_drugs AS (
  SELECT DISTINCT
    f.hadm_id,
    d.drug_class
  FROM
    first_icu_stay f
  JOIN
    drug_mappings d
  ON
    f.hadm_id = d.hadm_id
  WHERE
    d.starttime BETWEEN GREATEST(f.last_12_start, f.intime) AND f.outtime
),

first_window_counts AS (
  SELECT
    drug_class,
    COUNT(DISTINCT hadm_id) AS count_prescribed,
    (SELECT COUNT(DISTINCT hadm_id) FROM first_window_drugs) AS total
  FROM
    first_window_drugs
  GROUP BY
    drug_class
),

last_window_counts AS (
  SELECT
    drug_class,
    COUNT(DISTINCT hadm_id) AS count_prescribed,
    (SELECT COUNT(DISTINCT hadm_id) FROM last_window_drugs) AS total
  FROM
    last_window_drugs
  GROUP BY
    drug_class
),

first_window_pct AS (
  SELECT
    drug_class,
    ROUND(100 * count_prescribed / total, 2) AS first_window_pct
  FROM
    first_window_counts
),

last_window_pct AS (
  SELECT
    drug_class,
    ROUND(100 * count_prescribed / total, 2) AS last_window_pct
  FROM
    last_window_counts
)

SELECT
  COALESCE(f.drug_class, l.drug_class) AS drug_class,
  COALESCE(f.first_window_pct, 0) AS first_48h_pct,
  COALESCE(l.last_window_pct, 0) AS last_12h_pct,
  ROUND(COALESCE(l.last_window_pct, 0) - COALESCE(f.first_window_pct, 0), 2) AS net_change_pp
FROM
  first_window_pct f
FULL OUTER JOIN
  last_window_pct l
ON
  f.drug_class = l.drug_class
ORDER BY
  drug_class;