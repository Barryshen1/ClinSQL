WITH sodium_labs AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dl
    ON le.itemid = dl.itemid
  WHERE
    -- identify serum sodium measurements
    dl.fluid = 'Blood'
    AND dl.category = 'Chemistry'
    AND LOWER(dl.label) LIKE '%sodium%'
    AND le.valuenum IS NOT NULL
),
first_sodium_per_admission AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    -- pick the first (earliest) sodium measurement per admission
    ARRAY_AGG(s.valuenum ORDER BY s.charttime ASC LIMIT 1)[OFFSET(0)] AS first_sodium
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON a.subject_id = icu.subject_id
    AND a.hadm_id = icu.hadm_id
  LEFT JOIN sodium_labs AS s
    ON a.subject_id = s.subject_id
    AND a.hadm_id = s.hadm_id
  WHERE
    p.gender = 'M'
  GROUP BY
    p.subject_id,
    a.hadm_id
  HAVING
    first_sodium IS NOT NULL
)
SELECT
  PERCENTILE_CONT(first_sodium, 0.25) 
    OVER () AS sodium_25th_percentile,
  PERCENTILE_CONT(first_sodium, 0.75) 
    OVER () AS sodium_75th_percentile
FROM first_sodium_per_admission;