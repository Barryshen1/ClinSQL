WITH ami_admissions AS (
  -- Step 1: Identify male patients age 76-86 with AMI diagnosis
  SELECT DISTINCT a.subject_id,
                  a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code
   AND d.icd_version = diag.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND LOWER(diag.long_title) LIKE '%myocardial infarction%'
),

troponin_items AS (
  -- Step 2: Identify all itemids corresponding to Troponin I
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin i%'
),

first_troponin AS (
  -- Step 3: Extract the first Troponin I measurement per admission
  SELECT
    la.subject_id,
    la.hadm_id,
    la.valuenum,
    CASE
      WHEN la.valuenum <= 0.04 THEN 'normal (<=0.04)'
      WHEN la.valuenum > 0.04
        AND la.valuenum <= 0.40 THEN 'borderline (0.04-0.40)'
      WHEN la.valuenum > 0.40 THEN 'elevated (>0.40)'
      ELSE 'unknown'
    END AS category
  FROM (
    SELECT
      le.subject_id,
      le.hadm_id,
      le.valuenum,
      ROW_NUMBER() OVER (
        PARTITION BY le.hadm_id
        ORDER BY le.charttime
      ) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN ami_admissions aa
      ON le.hadm_id = aa.hadm_id
    JOIN troponin_items ti
      ON le.itemid = ti.itemid
    WHERE le.valuenum IS NOT NULL
  ) la
  WHERE la.rn = 1
)

-- Step 4: Aggregate counts, percentages, mean, median, and IQR by category
SELECT
  category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS percent,
  ROUND(AVG(valuenum), 3) AS mean_value,
  -- APPROX_QUANTILES(x, 4) returns [min, Q1, median, Q3, max]
  ROUND( (APPROX_QUANTILES(valuenum, 4))[OFFSET(2)], 3 ) AS median_value,
  ROUND(
    ( (APPROX_QUANTILES(valuenum, 4))[OFFSET(3)]
    - (APPROX_QUANTILES(valuenum, 4))[OFFSET(1)] ),
    3
  ) AS iqr_value
FROM first_troponin
GROUP BY category
ORDER BY
  CASE
    WHEN category LIKE 'normal%' THEN 1
    WHEN category LIKE 'borderline%' THEN 2
    WHEN category LIKE 'elevated%' THEN 3
    ELSE 4
  END;