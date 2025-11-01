WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.gender, 
    p.anchor_age, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'E1[0-4]%') 
          OR (d.icd_version = 9 AND d.icd_code LIKE '250%')
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dd 
      WHERE dd.hadm_id = a.hadm_id
        AND (
          (dd.icd_version = 10 AND dd.icd_code LIKE 'I50%') 
          OR (dd.icd_version = 9 AND dd.icd_code LIKE '428%')
        )
    )
),
insulin_events AS (
  SELECT 
    e.subject_id, 
    e.hadm_id, 
    e.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed 
    ON e.emar_id = ed.emar_id AND e.emar_seq = ed.emar_seq
  JOIN cohort c 
    ON e.subject_id = c.subject_id AND e.hadm_id = c.hadm_id
  WHERE LOWER(ed.product_description) LIKE '%insulin%'
    AND ed.administration_type = 'GIVEN'
),
oral_events AS (
  SELECT 
    e.subject_id, 
    e.hadm_id, 
    e.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed 
    ON e.emar_id = ed.emar_id AND e.emar_seq = ed.emar_seq
  JOIN cohort c 
    ON e.subject_id = c.subject_id AND e.hadm_id = c.hadm_id
  WHERE ed.route = 'PO'
    AND ed.administration_type = 'GIVEN'
    AND (
      LOWER(ed.product_description) LIKE '%metformin%' OR
      LOWER(ed.product_description) LIKE '%glipizide%' OR
      LOWER(ed.product_description) LIKE '%glyburide%' OR
      LOWER(ed.product_description) LIKE '%glimepiride%' OR
      LOWER(ed.product_description) LIKE '%repaglinide%' OR
      LOWER(ed.product_description) LIKE '%nateglinide%' OR
      LOWER(ed.product_description) LIKE '%acarbose%' OR
      LOWER(ed.product_description) LIKE '%miglitol%' OR
      LOWER(ed.product_description) LIKE '%pioglitazone%' OR
      LOWER(ed.product_description) LIKE '%rosiglitazone%' OR
      LOWER(ed.product_description) LIKE '%sitagliptin%' OR
      LOWER(ed.product_description) LIKE '%saxagliptin%' OR
      LOWER(ed.product_description) LIKE '%linagliptin%' OR
      LOWER(ed.product_description) LIKE '%alogliptin%' OR
      LOWER(ed.product_description) LIKE '%canagliflozin%' OR
      LOWER(ed.product_description) LIKE '%dapagliflozin%' OR
      LOWER(ed.product_description) LIKE '%empagliflozin%' OR
      LOWER(ed.product_description) LIKE '%ertugliflozin%'
    )
),
insulin_initiations AS (
  SELECT 
    c.hadm_id,
    MIN(ie.charttime) AS first_insulin_time
  FROM cohort c
  LEFT JOIN insulin_events ie 
    ON c.hadm_id = ie.hadm_id
  GROUP BY c.hadm_id
),
oral_initiations AS (
  SELECT 
    c.hadm_id,
    MIN(oe.charttime) AS first_oral_time
  FROM cohort c
  LEFT JOIN oral_events oe 
    ON c.hadm_id = oe.hadm_id
  GROUP BY c.hadm_id
)
SELECT 
  COUNT(*) AS total_admissions,
  ROUND(100.0 * SUM(
    CASE 
      WHEN ii.first_insulin_time >= c.admittime 
        AND ii.first_insulin_time < c.admittime + INTERVAL 1 DAY 
      THEN 1 
      ELSE 0 
    END
  ) / COUNT(*), 2) AS insulin_first_24h_pct,
  ROUND(100.0 * SUM(
    CASE 
      WHEN oi.first_oral_time >= c.admittime 
        AND oi.first_oral_time < c.admittime + INTERVAL 1 DAY 
      THEN 1 
      ELSE 0 
    END
  ) / COUNT(*), 2) AS oral_first_24h_pct,
  ROUND(100.0 * SUM(
    CASE 
      WHEN ii.first_insulin_time > c.dischtime - INTERVAL 1 DAY 
        AND ii.first_insulin_time <= c.dischtime 
      THEN 1 
      ELSE 0 
    END
  ) / COUNT(*), 2) AS insulin_final_24h_pct,
  ROUND(100.0 * SUM(
    CASE 
      WHEN oi.first_oral_time > c.dischtime - INTERVAL 1 DAY 
        AND oi.first_oral_time <= c.dischtime 
      THEN 1 
      ELSE 0 
    END
  ) / COUNT(*), 2) AS oral_final_24h_pct,
  ROUND(ABS(
    100.0 * SUM(
      CASE 
        WHEN ii.first_insulin_time >= c.admittime 
          AND ii.first_insulin_time < c.admittime + INTERVAL 1 DAY 
        THEN 1 
        ELSE 0 
      END
    ) / COUNT(*) -
    100.0 * SUM(
      CASE 
        WHEN ii.first_insulin_time > c.dischtime - INTERVAL 1 DAY 
          AND ii.first_insulin_time <= c.dischtime 
        THEN 1 
        ELSE 0 
      END
    ) / COUNT(*)
  ), 2) AS insulin_first_vs_final_diff_pct,
  ROUND(ABS(
    100.0 * SUM(
      CASE 
        WHEN oi.first_oral_time >= c.admittime 
          AND oi.first_oral_time < c.admittime + INTERVAL 1 DAY 
        THEN 1 
        ELSE 0 
      END
    ) / COUNT(*) -
    100.0 * SUM(
      CASE 
        WHEN oi.first_oral_time > c.dischtime - INTERVAL 1 DAY 
          AND oi.first_oral_time <= c.dischtime 
        THEN 1 
        ELSE 0 
      END
    ) / COUNT(*)
  ), 2) AS oral_first_vs_final_diff_pct,
  ROUND(ABS(
    100.0 * SUM(
      CASE 
        WHEN ii.first_insulin_time >= c.admittime 
          AND ii.first_insulin_time < c.admittime + INTERVAL 1 DAY 
        THEN 1 
        ELSE 0 
      END
    ) / COUNT(*) -
    100.0 * SUM(
      CASE 
        WHEN oi.first_oral_time >= c.admittime 
          AND oi.first_oral_time < c.admittime + INTERVAL 1 DAY 
        THEN 1 
        ELSE 0 
      END
    ) / COUNT(*)
  ), 2) AS insulin_vs_oral_first_24h_diff_pct,
  ROUND(ABS(
    100.0 * SUM(
      CASE 
        WHEN ii.first_insulin_time > c.dischtime - INTERVAL 1 DAY 
          AND ii.first_insulin_time <= c.dischtime 
        THEN 1 
        ELSE 0 
      END
    ) / COUNT(*) -
    100.0 * SUM(
      CASE 
        WHEN oi.first_oral_time > c.dischtime - INTERVAL 1 DAY 
          AND oi.first_oral_time <= c.dischtime 
        THEN 1 
        ELSE 0 
      END
    ) / COUNT(*)
  ), 2) AS insulin_vs_oral_final_24h_diff_pct
FROM cohort c
LEFT JOIN insulin_initiations ii 
  ON c.hadm_id = ii.hadm_id
LEFT JOIN oral_initiations oi 
  ON c.hadm_id = oi.hadm_id;