WITH aki_cohort AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND (
      (di.icd_version = 9  AND di.icd_code LIKE '584%')  -- ICD-9 AKI codes
      OR (di.icd_version = 10 AND di.icd_code LIKE 'N17%')  -- ICD-10 AKI codes
    )
),

-- 2) Identify each patient's first ICU stay (earliest intime)
first_icu AS (
  SELECT s.subject_id, s.intime, s.outtime
  FROM (
    SELECT subject_id, MIN(intime) AS first_intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY subject_id
  ) AS m
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS s
    ON s.subject_id = m.subject_id
   AND s.intime = m.first_intime
  WHERE s.intime IS NOT NULL
    AND s.outtime IS NOT NULL
),

-- 3) Compute LOS in days for the first ICU stay
los AS (
  SELECT fi.subject_id,
         TIMESTAMP_DIFF(fi.outtime, fi.intime, SECOND) / 86400.0 AS first_los_days
  FROM first_icu fi
)

-- 4) Compute the 25th percentile (approximately) of the first ICU LOS among AKI patients
SELECT
  CAST(APPROX_QUANTILES(first_los_days, 100)[OFFSET(24)] AS FLOAT64) AS percentile_25th_days
FROM los
WHERE subject_id IN (SELECT subject_id FROM aki_cohort);