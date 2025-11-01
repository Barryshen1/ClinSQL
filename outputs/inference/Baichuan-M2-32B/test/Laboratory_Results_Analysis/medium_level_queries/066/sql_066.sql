WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    -- Compute age at admission: anchor_age + (year of admission - anchor_year)
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 39 AND 49
),

chest_pain_admissions AS (
  SELECT DISTINCT
    da.subject_id,
    da.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` da
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
    ON da.icd_code = d.icd_code AND da.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%chest pain%'
    AND da.icd_version = 10
),

-- Get the hs-TnT itemid(s)
hs_tnt_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%troponin T%'
    AND label LIKE '%high-sensitivity%'
),

-- Get the first hs-TnT lab per admission in ng/L
first_hs_tnt AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.valuenum,
    le.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN hs_tnt_itemid h 
    ON le.itemid = h.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/L'  -- ensure unit is ng/L
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
)

-- Now combine and compute statistics
SELECT 
  CASE 
    WHEN f.valuenum < 14 THEN 'Normal'
    WHEN f.valuenum BETWEEN 14 AND 50 THEN 'Borderline'
    WHEN f.valuenum > 50 THEN 'Myocardial injury'
    ELSE 'Unknown'  -- though we filtered NULL, but still
  END AS category,
  COUNT(*) AS count,
  (COUNT(*) * 100.0 / SUM(COUNT(*)) OVER ()) AS percentage,
  APPROX_QUANTILES(f.valuenum, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(f.valuenum, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(f.valuenum, 100)[OFFSET(75)] AS p75,
  (APPROX_QUANTILES(f.valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(f.valuenum, 100)[OFFSET(25)]) AS iqr,
  AVG(f.valuenum) AS mean
FROM patient_admissions pa
INNER JOIN chest_pain_admissions c 
  ON pa.subject_id = c.subject_id AND pa.hadm_id = c.hadm_id
INNER JOIN first_hs_tnt f 
  ON pa.subject_id = f.subject_id AND pa.hadm_id = f.hadm_id
GROUP BY category
ORDER BY 
  CASE category 
    WHEN 'Normal' THEN 1 
    WHEN 'Borderline' THEN 2 
    WHEN 'Myocardial injury' THEN 3 
    ELSE 4 
  END;