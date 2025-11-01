WITH troponin_ids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
    AND LOWER(label) LIKE '%high-sensitivity%'
),
cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
   AND a.hadm_id    = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code    = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
    AND (
      LOWER(dd.long_title) LIKE '%chest pain%'
      OR LOWER(dd.long_title) LIKE '%myocardial infarction%'
      OR LOWER(dd.long_title) LIKE '%ami%'
    )
),
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (
      PARTITION BY l.subject_id, l.hadm_id
      ORDER BY l.charttime
    ) AS rn
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.subject_id = l.subject_id
   AND c.hadm_id    = l.hadm_id
  JOIN troponin_ids t
    ON l.itemid = t.itemid
  WHERE l.valuenum IS NOT NULL
),
first_per_admission AS (
  SELECT
    subject_id,
    hadm_id,
    valuenum,
    CASE
      WHEN valuenum <= 14 THEN 'normal'
      WHEN valuenum <= 52 THEN 'borderline'
      ELSE 'myocardial injury'
    END AS category
  FROM first_troponin
  WHERE rn = 1
)
SELECT
  category,
  COUNT(*) AS count
FROM first_per_admission
GROUP BY category
ORDER BY category;