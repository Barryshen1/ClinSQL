WITH base_admissions AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 82 AND 92
),
admissions_with_dx AS (
  SELECT DISTINCT
    ba.subject_id,
    ba.hadm_id
  FROM base_admissions ba
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ba.hadm_id = di.hadm_id
  WHERE 
    (di.icd_version = 9 AND di.icd_code LIKE '410%') 
    OR (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
    OR (di.icd_version = 9 AND di.icd_code = '786.5')
    OR (di.icd_version = 10 AND di.icd_code IN ('R07.1','R07.2','R07.8','R07.9'))
),
troponin_events AS (
  SELECT 
    le.hadm_id,
    le.charttime,
    le.valuenum AS troponin_t
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  WHERE le.itemid = 51003  -- Troponin T (itemid 51003)
),
first_troponin AS (
  SELECT 
    te.hadm_id,
    ARRAY_AGG(te.troponin_t ORDER BY te.charttime LIMIT 1)[SAFE_OFFSET(0)] AS initial_troponin
  FROM troponin_events te
  INNER JOIN admissions_with_dx adx 
    ON te.hadm_id = adx.hadm_id
  GROUP BY te.hadm_id
),
cohort AS (
  SELECT 
    hadm_id, 
    initial_troponin
  FROM first_troponin
  WHERE initial_troponin > 0.01
),
quantiles AS (
  SELECT 
    APPROX_QUANTILES(initial_troponin, 100) AS q
  FROM cohort
)
SELECT 
  q[OFFSET(0)] AS min_value,
  q[OFFSET(100)] AS max_value,
  q[OFFSET(25)] AS p25,
  q[OFFSET(50)] AS p50,
  q[OFFSET(75)] AS p75
FROM quantiles;