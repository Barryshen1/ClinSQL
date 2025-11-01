WITH ami_adms AS (
  -- Admissions for male patients age 77-87 with an AMI diagnosis on that admission
  SELECT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- ICD-9 AMI codes typically start with 410
          (d.icd_version = 9 AND d.icd_code LIKE '410%')
          -- ICD-10 AMI codes: I21 (acute MI) and I22 (subsequent MI)
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
        )
    )
),

trop_first AS (
  -- For each AMI admission, find the first troponin lab (by charttime) within 24 hours of admission
  SELECT
    a.hadm_id,
    a.subject_id,
    -- take the earliest troponin lab row (charttime, valuenum, label) using ARRAY_AGG
    ARRAY_AGG(STRUCT(le.charttime AS charttime, le.valuenum AS valuenum, li.label AS label)
              ORDER BY le.charttime ASC)[OFFSET(0)] AS first_le
  FROM ami_adms a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE le.charttime >= a.admittime
    AND le.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
    AND le.valuenum IS NOT NULL
    -- try to identify troponin T / high-sensitivity troponin by label heuristics
    AND (
      REGEXP_CONTAINS(LOWER(li.label), r'troponin\s*t') OR
      REGEXP_CONTAINS(LOWER(li.label), r'hs[\s-]?troponin') OR
      REGEXP_CONTAINS(LOWER(li.label), r'high[\s-]?sensitivity.*troponin') OR
      REGEXP_CONTAINS(LOWER(li.label), r'trop\s*t')
    )
  GROUP BY a.hadm_id, a.subject_id
)

SELECT
  category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS percent
FROM (
  SELECT
    hadm_id,
    subject_id,
    first_le.valuenum AS valuenum,
    CASE
      WHEN first_le.valuenum < 14 THEN 'Normal (<14 ng/L)'
      WHEN first_le.valuenum >= 14 AND first_le.valuenum < 52 THEN 'Borderline (14–51 ng/L)'
      ELSE 'Myocardial injury (>=52 ng/L)'
    END AS category
  FROM trop_first
)
GROUP BY category
ORDER BY
  -- put Normal first, Borderline second, Myocardial injury third
  CASE
    WHEN category LIKE 'Normal%' THEN 1
    WHEN category LIKE 'Borderline%' THEN 2
    ELSE 3
  END;