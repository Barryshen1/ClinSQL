WITH diabetic_hf_admissions AS (
  -- Step 1 & 2: male patients age 53-63 with both diabetes and heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    -- Diabetes ICD-10 E10.x or E11.x, Heart failure I50.x
    AND (
      d.icd_code LIKE 'E10%' 
      OR d.icd_code LIKE 'E11%'
      OR d.icd_code LIKE 'I50%'
    )
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  HAVING
    -- must have at least one diabetes and one heart failure diagnosis
    COUNT(DISTINCT CASE WHEN d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' THEN d.icd_code END) >= 1
    AND COUNT(DISTINCT CASE WHEN d.icd_code LIKE 'I50%' THEN d.icd_code END) >= 1
),

glp1_events AS (
  -- Step 3: find GLP-1 RA prescription events
  SELECT
    hadm_id,
    MIN(starttime) AS first_tide_start,
    ARRAY_AGG(starttime) AS all_starts
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) LIKE '%tide%'  -- exenatide, liraglutide, etc.
    AND LOWER(route) LIKE '%subcutaneous%'  -- injectable
  GROUP BY
    hadm_id
),

flags AS (
  -- Step 4: flag early vs late initiation
  SELECT
    d.subject_id,
    d.hadm_id,
    d.admittime,
    d.dischtime,
    CASE
      WHEN ge.first_tide_start IS NOT NULL
       AND DATETIME_DIFF(ge.first_tide_start, d.admittime, HOUR) <= 24
      THEN 1 ELSE 0
    END AS early_flag,
    CASE
      WHEN ge.all_starts IS NOT NULL
       AND EXISTS (
         SELECT 1
         FROM UNNEST(ge.all_starts) AS st
         WHERE DATETIME_DIFF(d.dischtime, st, HOUR) <= 12
       )
      THEN 1 ELSE 0
    END AS late_flag
  FROM
    diabetic_hf_admissions AS d
    LEFT JOIN glp1_events AS ge
      ON d.hadm_id = ge.hadm_id
)

-- Step 5: aggregate percentages
SELECT
  COUNT(*) AS total_admissions,
  ROUND(100.0 * SUM(early_flag) / COUNT(*), 1) AS pct_initiated_within_first_24h,
  ROUND(100.0 * SUM(late_flag)  / COUNT(*), 1) AS pct_initiated_final_12h
FROM
  flags;