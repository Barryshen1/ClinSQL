WITH age_filtered AS (
  SELECT 
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admit,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 41 AND 51
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN age_filtered a
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
),

-- Check for fever: temp >= 38.0 in chartevents during ICU stay
fever AS (
  SELECT DISTINCT
    i.hadm_id
  FROM icu_stays i
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
    ON i.stay_id = ce.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) = 'temperature'
    AND ce.valuenum >= 38.0
    AND ce.charttime >= i.intime
    AND ce.charttime <= i.outtime
),

-- Check for neutropenia: ANC < 500 (in 10^9/L, equivalent to K/uL)
neutropenia_labs AS (
  SELECT 
    le.hadm_id,
    le.charttime,
    LOWER(di.label) AS label,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems di
    ON le.itemid = di.itemid
  WHERE le.hadm_id IN (SELECT hadm_id FROM age_filtered)
    AND LOWER(di.label) IN ('neutrophils, abs', 'neutrophils, percent', 'wbc')
),

-- Pivot to get WBC and NEUT% per hadm_id and time
anc_calc AS (
  SELECT
    hadm_id,
    charttime,
    MAX(CASE WHEN label = 'neutrophils, abs' THEN valuenum END) AS neut_abs,
    MAX(CASE WHEN label = 'neutrophils, percent' THEN valuenum END) AS neut_percent,
    MAX(CASE WHEN label = 'wbc' THEN valuenum END) AS wbc
  FROM neutropenia_labs
  GROUP BY hadm_id, charttime
),

-- ANC < 500: either neut_abs < 0.5, or (wbc * neut_percent / 100) < 0.5 (units in 10^9/L)
neutropenia AS (
  SELECT DISTINCT hadm_id
  FROM anc_calc
  WHERE 
    (neut_abs IS NOT NULL AND neut_abs < 0.5)
    OR 
    (neut_percent IS NOT NULL AND wbc IS NOT NULL AND (wbc * neut_percent / 100.0) < 0.5)
),

-- Medications in first 48 hours of admission
meds_48h AS (
  SELECT
    p.hadm_id,
    COUNT(DISTINCT p.drug) AS unique_med_count
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  INNER JOIN age_filtered a
    ON p.hadm_id = a.hadm_id
  WHERE p.starttime >= a.admittime
    AND p.starttime <= DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY p.hadm_id
),

-- Identify patients with fever and neutropenia
eligible_admissions AS (
  SELECT a.*
  FROM age_filtered a
  INNER JOIN fever f ON a.hadm_id = f.hadm_id
  INNER JOIN neutropenia n ON a.hadm_id = n.hadm_id
),

-- Add medication count and assign tertiles
tertile_groups AS (
  SELECT
    e.hadm_id,
    e.subject_id,
    e.admittime,
    e.dischtime,
    e.hospital_expire_flag,
    COALESCE(m.unique_med_count, 0) AS med_count,
    NTILE(3) OVER (ORDER BY COALESCE(m.unique_med_count, 0)) AS med_tertile
  FROM eligible_admissions e
  LEFT JOIN meds_48h m ON e.hadm_id = m.hadm_id
),

-- Compute 30-day readmission
readmission AS (
  SELECT
    t.hadm_id,
    t.med_tertile,
    DATETIME_DIFF(t.dischtime, t.admittime, HOUR) / 24.0 AS los_days,
    t.hospital_expire_flag,
    CASE 
      WHEN LAG(t.subject_id) OVER (PARTITION BY t.subject_id ORDER BY t.admittime) IS NOT NULL
        AND DATETIME_DIFF(
            LEAD(t.admittime) OVER (PARTITION BY t.subject_id ORDER BY t.admittime),
            t.dischtime,
            DAY
          ) BETWEEN 1 AND 30
      THEN 1 ELSE 0 
    END AS thirty_day_readmit
  FROM tertile_groups t
)

-- Final aggregation by tertile
SELECT
  med_tertile,
  AVG(los_days) AS avg_los_days,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
  AVG(thirty_day_readmit) AS thirty_day_readmission_rate
FROM readmission
GROUP BY med_tertile
ORDER BY med_tertile;