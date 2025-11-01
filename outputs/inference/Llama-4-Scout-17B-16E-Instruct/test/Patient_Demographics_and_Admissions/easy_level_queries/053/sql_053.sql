WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT p.subject_id, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 52 AND 62
),

-- Identify AKI events
aki_events AS (
  SELECT DISTINCT ce.subject_id, ce.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE di.label IN ('Creatinine') AND 
        ce.valuenum > 1.5  -- Simplified AKI criteria based on creatinine
  UNION ALL
  SELECT DISTINCT le.subject_id, le.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON le.itemid = dl.itemid
  WHERE dl.label IN ('Creatinine') AND 
        le.valuenum > 1.5  -- Simplified AKI criteria based on creatinine
),

-- Identify index admissions with AKI
index_admissions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patients_of_interest poi ON a.subject_id = poi.subject_id
  JOIN aki_events ae ON a.hadm_id = ae.hadm_id
),

-- Identify readmissions within 30 days
readmissions AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN 
        LAG(dischtime) OVER (PARTITION BY subject_id ORDER BY admittime) IS NOT NULL 
        AND admittime <= DATE_ADD(LAG(dischtime) OVER (PARTITION BY subject_id ORDER BY admittime), INTERVAL 30 DAY)
      THEN 1 
      ELSE 0 
    END AS readmitted_within_30_days
  FROM index_admissions
)

-- Calculate standard deviation of readmission rates per encounter
SELECT 
  STDDEV(readmitted_within_30_days) AS std_dev_readmission_rate
FROM readmissions;