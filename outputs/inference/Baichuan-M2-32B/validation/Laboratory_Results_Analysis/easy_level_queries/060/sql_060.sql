WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN (
    SELECT DISTINCT d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE LOWER(dd.long_title) LIKE '%pneumonia%'
  ) diag ON a.hadm_id = diag.hadm_id
  WHERE p.gender = 'M'
    AND TIMESTAMP_DIFF(
      a.admittime, 
      DATE(p.anchor_year - p.anchor_age, 1, 1), 
      YEAR
    ) = 67
),
glucose_data AS (
  -- Labevents (hospital)
  SELECT 
    le.hadm_id,
    le.charttime,
    CASE 
      WHEN le.valueuom = 'mg/dL' THEN le.valuenum
      WHEN le.valueuom = 'mmol/L' THEN le.valuenum * 18
      ELSE NULL 
    END AS glucose_mgdl
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li 
    ON le.itemid = li.itemid
  WHERE LOWER(li.label) LIKE '%glucose%'
    AND li.fluid = 'Blood'
  UNION ALL
  -- Chartevents (ICU)
  SELECT 
    ce.hadm_id,
    ce.charttime,
    CASE 
      WHEN ce.valueuom = 'mg/dL' THEN ce.valuenum
      WHEN ce.valueuom = 'mmol/L' THEN ce.valuenum * 18
      ELSE NULL 
    END AS glucose_mgdl
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%glucose%'
    AND di.category = 'Blood Glucose'
),
mean_glucose_per_admission AS (
  SELECT 
    ga.hadm_id,
    AVG(gd.glucose_mgdl) AS mean_glucose
  FROM eligible_admissions ga
  JOIN glucose_data gd 
    ON ga.hadm_id = gd.hadm_id
    AND gd.charttime BETWEEN ga.admittime 
        AND TIMESTAMP_ADD(ga.admittime, INTERVAL 24 HOUR)
  GROUP BY ga.hadm_id
  HAVING COUNT(gd.glucose_mgdl) > 0  -- Exclude admissions without measurements
)
SELECT 
  APPROX_QUANTILES(mean_glucose, 100)[OFFSET(75)] AS p75_mean_glucose
FROM mean_glucose_per_admission;