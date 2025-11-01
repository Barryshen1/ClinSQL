WITH
-- T2DM admissions identified by diagnosis description containing "type 2" / "type ii"
t2dm_hadm AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON di.icd_code = dicd.icd_code
   AND di.icd_version = dicd.icd_version
  WHERE LOWER(dicd.long_title) LIKE '%type 2%'
     OR LOWER(dicd.long_title) LIKE '%type ii%'
     OR LOWER(dicd.long_title) LIKE '%type 2 diabetes%'
     OR LOWER(dicd.long_title) LIKE '%type ii diabetes%'
),

-- Heart failure admissions identified by diagnosis description containing "heart failure"
hf_hadm AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON di.icd_code = dicd.icd_code
   AND di.icd_version = dicd.icd_version
  WHERE LOWER(dicd.long_title) LIKE '%heart failure%'
     OR LOWER(dicd.long_title) LIKE '%congestive heart failure%'
),

-- Cohort: admissions for patients age 48-58 with both T2DM and HF
cohort_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.anchor_age BETWEEN 48 AND 58
    AND a.hadm_id IN (SELECT hadm_id FROM t2dm_hadm)
    AND a.hadm_id IN (SELECT hadm_id FROM hf_hadm)
),

-- Candidate GLP-1 exposures from multiple hosp medication tables.
-- We capture common agent names and brand names. Times are the event/order times available in each table.
glp_exposures AS (
  SELECT hadm_id, starttime AS exposure_time, LOWER(COALESCE(drug, '')) AS med_text
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE starttime IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(COALESCE(drug, '')),
      r'(liraglutide|dulaglutide|semaglutide|exenatide|lixisenatide|albiglutide|trulicity|victoza|ozempic|bydureon)')
  UNION ALL
  SELECT hadm_id, starttime AS exposure_time, LOWER(COALESCE(medication, '')) AS med_text
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE starttime IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(COALESCE(medication, '')),
      r'(liraglutide|dulaglutide|semaglutide|exenatide|lixisenatide|albiglutide|trulicity|victoza|ozempic|bydureon)')
  UNION ALL
  SELECT hadm_id, charttime AS exposure_time, LOWER(COALESCE(medication, '')) AS med_text
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE charttime IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(COALESCE(medication, '')),
      r'(liraglutide|dulaglutide|semaglutide|exenatide|lixisenatide|albiglutide|trulicity|victoza|ozempic|bydureon)')
),

-- For each cohort admission, find the first GLP-1 exposure time occurring during the hospitalization (if any)
first_exposure_per_admission AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    MIN(e.exposure_time) AS first_exposure_time
  FROM cohort_admissions c
  LEFT JOIN glp_exposures e
    ON c.hadm_id = e.hadm_id
    -- Only consider exposures that occur during the hospital admission window
    AND e.exposure_time BETWEEN c.admittime AND c.dischtime
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime
)

-- Final aggregation: counts and percentages
SELECT
  COUNT(1) AS total_admissions,
  SUM(CASE WHEN first_exposure_time IS NOT NULL
            AND first_exposure_time <= TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS n_initiated_first_72h,
  ROUND(100.0 * SAFE_DIVIDE(
    SUM(CASE WHEN first_exposure_time IS NOT NULL
             AND first_exposure_time <= TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END),
    COUNT(1)
  ), 2) AS pct_initiated_first_72h,
  SUM(CASE WHEN first_exposure_time IS NOT NULL
            AND first_exposure_time >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR)
            AND first_exposure_time <= dischtime THEN 1 ELSE 0 END) AS n_initiated_last_48h,
  ROUND(100.0 * SAFE_DIVIDE(
    SUM(CASE WHEN first_exposure_time IS NOT NULL
             AND first_exposure_time >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR)
             AND first_exposure_time <= dischtime THEN 1 ELSE 0 END),
    COUNT(1)
  ), 2) AS pct_initiated_last_48h,
  ROUND(
    100.0 * SAFE_DIVIDE(
      SUM(CASE WHEN first_exposure_time IS NOT NULL
               AND first_exposure_time <= TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END),
      COUNT(1)
    )
    -
    100.0 * SAFE_DIVIDE(
      SUM(CASE WHEN first_exposure_time IS NOT NULL
               AND first_exposure_time >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR)
               AND first_exposure_time <= dischtime THEN 1 ELSE 0 END),
      COUNT(1)
    )
  , 2) AS absolute_difference_pct_points
FROM first_exposure_per_admission;