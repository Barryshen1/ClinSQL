WITH troponin_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%high sensitivity troponin t%'
),
index_tnt AS (
  SELECT hadm_id, valuenum
  FROM (
    SELECT 
      le.hadm_id,
      le.valuenum,
      ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    CROSS JOIN troponin_item ti
    WHERE le.itemid = ti.itemid
      AND le.hadm_id IS NOT NULL
      AND le.valuenum IS NOT NULL
      AND le.valueuom = 'ng/mL'
  )
  WHERE rn = 1
),
cohort AS (
  SELECT 
    a.hadm_id,
    it.valuenum,
    CASE 
      WHEN it.valuenum <= 0.04 THEN 'Normal'
      WHEN it.valuenum <= 0.1 THEN 'Borderline'
      ELSE 'Injury'
    END AS category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id AND di.seq_num = 1
  INNER JOIN index_tnt it
    ON a.hadm_id = it.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND (
      (di.icd_version = 9 AND di.icd_code LIKE '786.5%') 
      OR 
      (di.icd_version = 10 AND di.icd_code LIKE 'R07.%')
    )
),
total_cohort AS (
  SELECT COUNT(*) AS total_n
  FROM cohort
),
counts AS (
  SELECT 
    category,
    COUNT(*) AS n,
    ROUND(COUNT(*) * 100.0 / (SELECT total_n FROM total_cohort), 2) AS percentage
  FROM cohort
  GROUP BY category
),
means AS (
  SELECT 
    category,
    AVG(valuenum) AS mean_tnt
  FROM cohort
  GROUP BY category
),
medians AS (
  SELECT 
    category,
    APPROX_QUANTILES(valuenum, 2)[OFFSET(1)] AS median_tnt
  FROM cohort
  GROUP BY category
),
q1s AS (
  SELECT 
    category,
    APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS q1_tnt
  FROM cohort
  GROUP BY category
),
q3s AS (
  SELECT 
    category,
    APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS q3_tnt
  FROM cohort
  GROUP BY category
)
SELECT 
  c.category,
  c.n,
  c.percentage,
  ROUND(m.mean_tnt, 4) AS mean_tnt,
  ROUND(d.median_tnt, 4) AS median_tnt,
  ROUND(q1.q1_tnt, 4) AS q1_tnt,
  ROUND(q3.q3_tnt, 4) AS q3_tnt,
  ROUND(q3.q3_tnt - q1.q1_tnt, 4) AS iqr_tnt
FROM counts c
INNER JOIN means m ON c.category = m.category
INNER JOIN medians d ON c.category = d.category
INNER JOIN q1s q1 ON c.category = q1.category
INNER JOIN q3s q3 ON c.category = q3.category
ORDER BY 
  CASE c.category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    ELSE 3
  END;