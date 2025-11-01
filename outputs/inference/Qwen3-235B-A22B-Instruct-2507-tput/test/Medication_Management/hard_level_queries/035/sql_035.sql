WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 40 AND 50
),

-- Get neutrophil labs < 500 within 48h of admission
neutropenia AS (
  SELECT DISTINCT
    le.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems d
    ON le.itemid = d.itemid
  INNER JOIN patient_admissions pa
    ON le.hadm_id = pa.hadm_id
  WHERE LOWER(d.label) LIKE '%neutrophil%' 
    AND le.valuenum < 500
    AND le.valuenum IS NOT NULL
    AND le.charttime >= pa.admittime
    AND le.charttime <= DATETIME_ADD(pa.admittime, INTERVAL 48 HOUR)
),

-- Get fever: temperature > 38.3°C within 48h of admission
fever AS (
  SELECT DISTINCT
    ce.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items d
    ON ce.itemid = d.itemid
  INNER JOIN patient_admissions pa
    ON ce.hadm_id = pa.hadm_id
  WHERE LOWER(d.label) IN ('temperature', 'temp', 'temperature c')
    AND ce.valuenum > 38.3
    AND ce.charttime >= pa.admittime
    AND ce.charttime <= DATETIME_ADD(pa.admittime, INTERVAL 48 HOUR)
),

-- Admissions with neutropenic fever
neutropenic_fever_admissions AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.hospital_expire_flag
  FROM patient_admissions pa
  INNER JOIN neutropenia n ON pa.hadm_id = n.hadm_id
  INNER JOIN fever f ON pa.hadm_id = f.hadm_id
),

-- Medication complexity: count distinct drugs in first 48h of admission
medication_complexity AS (
  SELECT
    nf.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_count
  FROM neutropenic_fever_admissions nf
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
    ON nf.hadm_id = pr.hadm_id
    AND pr.starttime >= nf.admittime
    AND pr.starttime <= DATETIME_ADD(nf.admittime, INTERVAL 48 HOUR)
  GROUP BY nf.hadm_id
),

-- Assign quartiles based on med_count
quartiles AS (
  SELECT
    mc.hadm_id,
    mc.med_count,
    NTILE(4) OVER (ORDER BY mc.med_count) AS quartile
  FROM medication_complexity mc
  WHERE mc.med_count IS NOT NULL
),

-- Compute 30-day readmission using EXISTS to avoid duplicates
readmissions AS (
  SELECT
    a1.hadm_id,
    EXISTS(
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.admissions a2
      WHERE a2.subject_id = a1.subject_id
        AND a2.admittime > a1.dischtime
        AND a2.admittime <= DATETIME_ADD(a1.dischtime, INTERVAL 30 DAY)
    ) AS readmit_30day
  FROM neutropenic_fever_admissions a1
),

-- Combine all
cohort AS (
  SELECT
    q.hadm_id,
    q.med_count,
    q.quartile,
    nf.hospital_expire_flag,
    DATETIME_DIFF(nf.dischtime, nf.admittime, SECOND) / (24*60*60.0) AS los_days,
    r.readmit_30day
  FROM quartiles q
  INNER JOIN neutropenic_fever_admissions nf ON q.hadm_id = nf.hadm_id
  LEFT JOIN readmissions r ON q.hadm_id = r.hadm_id
)

-- Final aggregation by quartile
SELECT
  quartile,
  COUNT(*) AS patient_count,
  AVG(med_count) AS mean_score,
  MIN(med_count) AS min_score,
  MAX(med_count) AS max_score,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  AVG(CAST(readmit_30day AS INT64)) * 100 AS readmission_30day_pct
FROM cohort
GROUP BY quartile
ORDER BY quartile;