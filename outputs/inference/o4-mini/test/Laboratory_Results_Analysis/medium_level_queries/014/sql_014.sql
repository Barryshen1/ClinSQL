WITH troponin_ids AS (
  -- Find the itemids corresponding to Troponin T
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),

first_troponin AS (
  -- For each admission, get the earliest Troponin T measurement
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum,
    le.valueuom,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_ids t ON le.itemid = t.itemid
  WHERE le.valuenum IS NOT NULL
),
initial_troponin AS (
  -- Keep only the first measurement
  SELECT
    subject_id,
    hadm_id,
    valuenum
  FROM first_troponin
  WHERE rn = 1
),

acs_admissions AS (
  -- Identify ACS admissions for 79-89yo males
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
   AND a.hadm_id    = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND (
      d.icd_code LIKE '410%'     -- acute myocardial infarction
      OR d.icd_code LIKE '4111%'  -- unstable angina
    )
)

-- Final aggregation
SELECT
  CASE
    WHEN it.valuenum <= 0.01 THEN 'Normal'
    WHEN it.valuenum > 0.01
      AND it.valuenum <= 0.03 THEN 'Borderline'
    WHEN it.valuenum > 0.03 THEN 'Elevated'
    ELSE 'Unknown'
  END AS troponin_category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percent
FROM acs_admissions a
JOIN initial_troponin it
  ON a.subject_id = it.subject_id
 AND a.hadm_id    = it.hadm_id
GROUP BY troponin_category
ORDER BY troponin_category;