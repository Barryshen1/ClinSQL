WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE 
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) = 94
    AND d.long_title LIKE '%ischemic stroke%'
),

glucose_events AS (
  SELECT 
    c.hadm_id,
    l.valuenum AS glucose,
    ROW_NUMBER() OVER (
      PARTITION BY c.hadm_id 
      ORDER BY l.charttime DESC
    ) AS rn
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON l.itemid = dli.itemid
  WHERE 
    dli.itemid = 50931  -- Serum Glucose
    AND DATE(l.charttime) = DATE(c.dischtime)
),

last_glucose AS (
  SELECT glucose
  FROM glucose_events
  WHERE rn = 1
),

quantiles AS (
  SELECT APPROX_QUANTILES(glucose, 4) AS arr
  FROM last_glucose
)

SELECT 
  arr[SAFE_OFFSET(1)] AS q1,
  arr[SAFE_OFFSET(3)] AS q3,
  arr[SAFE_OFFSET(3)] - arr[SAFE_OFFSET(1)] AS iqr
FROM quantiles;