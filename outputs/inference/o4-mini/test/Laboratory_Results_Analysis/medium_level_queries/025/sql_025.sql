WITH troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),

-- Filter admissions for female patients aged 58-68 with chest pain or AMI
eligible_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          LOWER(dd.long_title) LIKE '%chest pain%'
          OR LOWER(dd.long_title) LIKE '%myocardial infarction%'
        )
    )
),

-- Extract first Troponin T measurement per admission
first_troponin AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.valuenum,
    ROW_NUMBER() OVER (
      PARTITION BY e.subject_id, e.hadm_id
      ORDER BY e.charttime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` e
  JOIN troponin_items ti
    ON e.itemid = ti.itemid
  JOIN eligible_admissions ea
    ON e.subject_id = ea.subject_id
   AND e.hadm_id     = ea.hadm_id
  WHERE e.valuenum IS NOT NULL
)

-- Compute distribution for first Troponin T > 0.01 ng/mL
SELECT
  ROUND(AVG(valuenum), 4)      AS mean_troponin,
  ROUND(STDDEV_POP(valuenum), 4) AS stddev_troponin,
  MIN(valuenum)                AS min_troponin,
  MAX(valuenum)                AS max_troponin,
  COUNT(*)                     AS num_patients
FROM first_troponin
WHERE rn = 1
  AND valuenum > 0.01;