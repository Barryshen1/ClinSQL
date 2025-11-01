WITH troponin_first AS (
  -- Get first (index) Troponin T per admission
  SELECT
    l.hadm_id,
    l.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents AS l
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems AS d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) = 'troponin t'
    AND l.valuenum IS NOT NULL
),
troponin_index AS (
  -- Keep only first Troponin T per admission
  SELECT
    hadm_id,
    troponin_value
  FROM
    troponin_first
  WHERE
    rn = 1
),
acs_admissions AS (
  -- Identify admissions with ACS diagnosis
  SELECT
    di.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS di
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    (d.icd_version = 9 AND di.icd_code LIKE '410%')
    OR
    (d.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^(I21|I22|I23|I24\.0|I24\.8|I24\.9)'))
),
eligible_patients AS (
  -- Filter patients: male, age 90–100
  SELECT
    subject_id
  FROM
    physionet-data.mimiciv_3_1_hosp.patients
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 90 AND 100
),
eligible_admissions AS (
  -- Admissions for eligible patients with ACS
  SELECT
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions AS a
  INNER JOIN
    eligible_patients AS p
    ON a.subject_id = p.subject_id
  INNER JOIN
    acs_admissions AS acs
    ON a.hadm_id = acs.hadm_id
),
troponin_with_category AS (
  -- Assign Troponin T category
  SELECT
    e.hadm_id,
    e.los,
    t.troponin_value,
    CASE
      WHEN t.troponin_value <= 0.01 THEN 'Normal'
      WHEN t.troponin_value <= 0.04 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category
  FROM
    eligible_admissions AS e
  INNER JOIN
    troponin_index AS t
    ON e.hadm_id = t.hadm_id
),
grouped_stats AS (
  -- Aggregate stats by category
  SELECT
    troponin_category,
    COUNT(*) AS count,
    AVG(los) AS mean_los
  FROM
    troponin_with_category
  GROUP BY
    troponin_category
),
total_count AS (
  -- Total number of admissions for percentage
  SELECT
    COUNT(*) AS total
  FROM
    troponin_with_category
)
SELECT
  g.troponin_category,
  g.count,
  ROUND(g.count * 100.0 / t.total, 2) AS percentage,
  ROUND(g.mean_los, 2) AS mean_los
FROM
  grouped_stats AS g
CROSS JOIN
  total_count AS t
ORDER BY
  CASE
    WHEN troponin_category = 'Normal' THEN 1
    WHEN troponin_category = 'Borderline' THEN 2
    WHEN troponin_category = 'Elevated' THEN 3
  END;