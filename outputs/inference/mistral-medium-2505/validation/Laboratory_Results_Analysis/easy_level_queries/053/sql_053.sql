WITH
-- Get the first serum glucose measurement per admission
first_glucose AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    l.valuenum AS glucose_mg_dL,
    ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY l.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE
    d.label = 'Glucose'
    AND d.fluid = 'Blood'
    AND l.valuenum IS NOT NULL
    AND a.subject_id IN (
      -- Subquery to get subject_ids for 82-year-old females with ischemic stroke
      SELECT DISTINCT
        p.subject_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
      JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
      JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id
      WHERE
        p.gender = 'F'
        AND p.anchor_age = 82
        AND (
          -- ICD-9 codes for ischemic stroke
          (di.icd_version = 9 AND (di.icd_code LIKE '433.%' OR di.icd_code LIKE '434.%'))
          OR
          -- ICD-10 codes for ischemic stroke
          (di.icd_version = 10 AND di.icd_code LIKE 'I63.%')
        )
    )
)

-- Compute the 75th percentile of the first glucose measurement per admission
SELECT
  PERCENTILE_CONT(glucose_mg_dL, 0.75) OVER() AS p75_glucose_mg_dL
FROM
  first_glucose
WHERE
  rn = 1  -- Only the first glucose measurement per admission
LIMIT 1  -- Since we're calculating a single percentile value
;