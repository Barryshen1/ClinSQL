WITH cohort AS (
  -- Step 1: Identify female patients aged 81-91 admitted for chest pain or AMI
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND (
      -- Chest pain ICD-10 codes
      (d.icd_version = 10 AND (
        d.icd_code LIKE 'R079' OR
        d.icd_code LIKE 'R072' OR
        d.icd_code LIKE 'R071' OR
        d.icd_code LIKE 'R0789'
      ))
      OR
      -- AMI ICD-10 codes
      (d.icd_version = 10 AND (
        d.icd_code LIKE 'I21%' OR
        d.icd_code LIKE 'I22%'
      ))
      -- Optionally add ICD-9 codes if relevant (e.g., 410 for AMI, 78650 for chest pain)
      OR
      (d.icd_version = 9 AND (
        d.icd_code LIKE '410%' OR
        d.icd_code LIKE '78650'
      ))
    )
),
hs_tnt_items AS (
  -- Step 2: Find itemids for hs-TnT
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%' AND LOWER(label) LIKE '%high%'
),
index_hs_tnt AS (
  -- Step 2: For each admission, get the earliest hs-TnT measurement
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN hs_tnt_items i ON l.itemid = i.itemid
  WHERE
    l.valuenum IS NOT NULL
),
first_hs_tnt AS (
  -- Get the index (first) hs-TnT per admission
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    ih.charttime,
    ih.valuenum AS hs_tnt_value
  FROM
    cohort c
    JOIN (
      SELECT
        subject_id,
        hadm_id,
        MIN(charttime) AS first_charttime
      FROM index_hs_tnt
      GROUP BY subject_id, hadm_id
    ) idx
      ON c.subject_id = idx.subject_id AND c.hadm_id = idx.hadm_id
    JOIN index_hs_tnt ih
      ON c.subject_id = ih.subject_id AND c.hadm_id = ih.hadm_id AND ih.charttime = idx.first_charttime
),
categorized AS (
  -- Step 3: Categorize hs-TnT
  SELECT
    subject_id,
    hadm_id,
    hs_tnt_value,
    CASE
      WHEN hs_tnt_value < 14 THEN 'Normal'
      WHEN hs_tnt_value >= 14 AND hs_tnt_value < 52 THEN 'Borderline'
      WHEN hs_tnt_value >= 52 THEN 'Myocardial injury'
      ELSE 'Unknown'
    END AS hs_tnt_category,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los
  FROM first_hs_tnt
)
-- Step 5: Aggregate results
SELECT
  hs_tnt_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS percentage,
  ROUND(AVG(los), 2) AS mean_los
FROM categorized
WHERE hs_tnt_category != 'Unknown'
GROUP BY hs_tnt_category
ORDER BY hs_tnt_category;