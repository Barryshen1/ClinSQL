WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 68 AND 78
),
t2dm_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '250%')
     OR (icd_version = 10 AND icd_code LIKE 'E11%')
),
hf_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '428%')
     OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
cohort_final AS (
  SELECT c.*
  FROM cohort c
  INNER JOIN t2dm_hadm t ON c.hadm_id = t.hadm_id
  INNER JOIN hf_hadm h ON c.hadm_id = h.hadm_id
),
total_adms AS (
  SELECT COUNT(DISTINCT hadm_id) AS total
  FROM cohort_final
),
counts AS (
  -- Metformin first48
  SELECT 'Metformin' AS drug_class, 'first48' AS period, COUNT(*) AS n
  FROM (
    SELECT DISTINCT c.hadm_id
    FROM cohort_final c
    JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
      ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
      ON e.subject_id = ed.subject_id
      AND e.emar_id = ed.emar_id
      AND e.emar_seq = ed.emar_seq
    WHERE LOWER(ed.product_description) LIKE '%metformin%'
      AND e.charttime >= c.admittime
      AND e.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  )
  UNION ALL
  -- Metformin last12
  SELECT 'Metformin' AS drug_class, 'last12' AS period, COUNT(*) AS n
  FROM (
    SELECT DISTINCT c.hadm_id
    FROM cohort_final c
    JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
      ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
      ON e.subject_id = ed.subject_id
      AND e.emar_id = ed.emar_id
      AND e.emar_seq = ed.emar_seq
    WHERE LOWER(ed.product_description) LIKE '%metformin%'
      AND e.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
      AND e.charttime <= c.dischtime
  )
  UNION ALL
  -- Sulfonylureas first48
  SELECT 'Sulfonylureas' AS drug_class, 'first48' AS period, COUNT(*) AS n
  FROM (
    SELECT DISTINCT c.hadm_id
    FROM cohort_final c
    JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
      ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
      ON e.subject_id = ed.subject_id
      AND e.emar_id = ed.emar_id
      AND e.emar_seq = ed.emar_seq
    WHERE (LOWER(ed.product_description) LIKE '%glipizide%'
        OR LOWER(ed.product_description) LIKE '%glyburide%'
        OR LOWER(ed.product_description) LIKE '%glimepiride%')
      AND e.charttime >= c.admittime
      AND e.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  )
  UNION ALL
  -- Sulfonylureas last12
  SELECT 'Sulfonylureas' AS drug_class, 'last12' AS period, COUNT(*) AS n
  FROM (
    SELECT DISTINCT c.hadm_id
    FROM cohort_final c
    JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
      ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
      ON e.subject_id = ed.subject_id
      AND e.emar_id = ed.emar_id
      AND e.emar_seq = ed.emar_seq
    WHERE (LOWER(ed.product_description) LIKE '%glipizide%'
        OR LOWER(ed.product_description) LIKE '%glyburide%'
        OR LOWER(ed.product_description) LIKE '%glimepiride%')
      AND e.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
      AND e.charttime <= c.dischtime
  )
  UNION ALL
  -- DPP-4 first48
  SELECT 'DPP-4 inhibitors' AS drug_class, 'first48' AS period, COUNT(*) AS n
  FROM (
    SELECT DISTINCT c.hadm_id
    FROM cohort_final c
    JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
      ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
      ON e.subject_id = ed.subject_id
      AND e.emar_id = ed.emar_id
      AND e.emar_seq = ed.emar_seq
    WHERE (LOWER(ed.product_description) LIKE '%sitagliptin%'
        OR LOWER(ed.product_description) LIKE '%saxagliptin%'
        OR LOWER(ed.product_description) LIKE '%linagliptin%'
        OR LOWER(ed.product_description) LIKE '%alogliptin%')
      AND e.charttime >= c.admittime
      AND e.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  )
  UNION ALL
  -- DPP-4 last12
  SELECT 'DPP-4 inhibitors' AS drug_class, 'last12' AS period, COUNT(*) AS n
  FROM (
    SELECT DISTINCT c.hadm_id
    FROM cohort_final c
    JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
      ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
      ON e.subject_id = ed.subject_id
      AND e.emar_id = ed.emar_id
      AND e.emar_seq = ed.emar_seq
    WHERE (LOWER(ed.product_description) LIKE '%sitagliptin%'
        OR LOWER(ed.product_description) LIKE '%saxagliptin%'
        OR LOWER(ed.product_description) LIKE '%linagliptin%'
        OR LOWER(ed.product_description) LIKE '%alogliptin%')
      AND e.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
      AND e.charttime <= c.dischtime
  )
  UNION ALL
  -- SGLT2 first48
  SELECT 'SGLT2 inhibitors' AS drug_class, 'first48' AS period, COUNT(*) AS n
  FROM (
    SELECT DISTINCT c.hadm_id
    FROM cohort_final c
    JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
      ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
      ON e.subject_id = ed.subject_id
      AND e.emar_id = ed.emar_id
      AND e.emar_seq = ed.emar_seq
    WHERE (LOWER(ed.product_description) LIKE '%canagliflozin%'
        OR LOWER(ed.product_description) LIKE '%dapagliflozin%'
        OR LOWER(ed.product_description) LIKE '%empagliflozin%'
        OR LOWER(ed.product_description) LIKE '%ertugliflozin%')
      AND e.charttime >= c.admittime
      AND e.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  )
  UNION ALL
  -- SGLT2 last12
  SELECT 'SGLT2 inhibitors' AS drug_class, 'last12' AS period, COUNT(*) AS n
  FROM (
    SELECT DISTINCT c.hadm_id
    FROM cohort_final c
    JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
      ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
      ON e.subject_id = ed.subject_id
      AND e.emar_id = ed.emar_id
      AND e.emar_seq = ed.emar_seq
    WHERE (LOWER(ed.product_description) LIKE '%canagliflozin%'
        OR LOWER(ed.product_description) LIKE '%dapagliflozin%'
        OR LOWER(ed.product_description) LIKE '%empagliflozin%'
        OR LOWER(ed.product_description) LIKE '%ertugliflozin%')
      AND e.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
      AND e.charttime <= c.dischtime
  )
)
SELECT
  drug_class,
  ROUND(MAX(CASE WHEN period = 'first48' THEN n ELSE 0 END) * 100.0 / t.total, 2) AS first48_pct,
  ROUND(MAX(CASE WHEN period = 'last12' THEN n ELSE 0 END) * 100.0 / t.total, 2) AS last12_pct,
  ROUND((
    MAX(CASE WHEN period = 'last12' THEN n ELSE 0 END) -
    MAX(CASE WHEN period = 'first48' THEN n ELSE 0 END)
  ) * 100.0 / t.total, 2) AS net_change_pp
FROM counts
CROSS JOIN total_adms t
GROUP BY drug_class, t.total
ORDER BY drug_class;