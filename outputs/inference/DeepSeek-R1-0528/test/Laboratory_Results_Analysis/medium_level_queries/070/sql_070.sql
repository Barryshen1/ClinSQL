WITH base AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    -- Calculate real age at admission
    (IF(p.anchor_age < 300, p.anchor_age, p.anchor_age - 300 + 90)) 
    + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
),
filtered_admissions AS (
  SELECT b.*
  FROM base b
  WHERE 
    age_at_admission BETWEEN 90 AND 100
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.hadm_id = b.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '786.5%') 
          OR (d.icd_version = 10 AND d.icd_code LIKE 'R07%')
        )
    )
),
troponin_events AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    l.ref_range_upper,
    l.flag,
    ROW_NUMBER() OVER (
      PARTITION BY l.hadm_id 
      ORDER BY l.charttime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN filtered_admissions fa
    ON l.hadm_id = fa.hadm_id
  WHERE l.itemid IN (51002, 51002)  -- Troponin I (51002, 51003)
),
elevated_troponin AS (
  SELECT 
    hadm_id,
    valuenum AS initial_troponin_value
  FROM troponin_events
  WHERE 
    rn = 1  -- First measurement per admission
    AND ( 
      (
        SAFE_CAST(ref_range_upper AS FLOAT64) IS NOT NULL 
        AND valuenum > SAFE_CAST(ref_range_upper AS FLOAT64)
      )
      OR (flag = 'High')
    )
),
percentiles AS (
  SELECT 
    APPROX_QUANTILES(initial_troponin_value, 100) AS p
  FROM elevated_troponin
)
SELECT 
  p[OFFSET(25)] AS p25,
  p[OFFSET(50)] AS p50,
  p[OFFSET(75)] AS p75,
  p[OFFSET(0)] AS min_value,
  p[OFFSET(100)] AS max_value
FROM percentiles;