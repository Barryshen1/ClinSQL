WITH /* sepsis_admissions CTE: Identify sepsis admissions for 93-year-old males */
sepsis_admissions AS (
  SELECT 
    a.hadm_id, 
    a.subject_id, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    (d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%') 
    AND d.icd_version = 10
    AND p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year = 93
),

/* platelet_events CTE: Get platelet lab events with numeric values */
platelet_events AS (
  SELECT 
    l.hadm_id,
    l.subject_id,
    l.charttime,
    l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl 
    ON l.itemid = dl.itemid
  WHERE 
    dl.itemid = 51265  -- platelet count itemid
    AND l.valuenum IS NOT NULL
),

/* discharge_day_platelets CTE: Filter platelet events to discharge day */
discharge_day_platelets AS (
  SELECT 
    s.hadm_id,
    s.subject_id,
    s.dischtime,
    p.charttime,
    p.valuenum
  FROM sepsis_admissions s
  INNER JOIN platelet_events p 
    ON s.hadm_id = p.hadm_id
    AND DATE(p.charttime) = DATE(s.dischtime)  -- same date
),

/* ranked_platelets CTE: Rank platelet events per admission by charttime descending */
ranked_platelets AS (
  SELECT 
    hadm_id,
    valuenum,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime DESC) as rn
  FROM discharge_day_platelets
),

/* last_platelet_per_admission CTE: Get the last platelet measurement per admission */
last_platelet_per_admission AS (
  SELECT 
    hadm_id,
    valuenum as platelet_count
  FROM ranked_platelets
  WHERE rn = 1
)

/* Main query: Compute the 75th percentile of platelet counts */
SELECT 
  APPROX_QUANTILES(platelet_count, 100)[OFFSET(75)] AS p75_platelet_count
FROM last_platelet_per_admission;