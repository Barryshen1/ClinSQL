WITH
  -- 1) Male patients aged 50-60 (proxy)
  male_age_filtered AS (
    SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    WHERE LOWER(p.gender) = 'm'
      AND p.anchor_age BETWEEN 50 AND 60
      AND a.dischtime IS NOT NULL
  ),
  -- 2) Admissions with chest pain or AMI
  chest_pain_ami AS (
    SELECT DISTINCT di.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
      ON di.icd_code = d.icd_code
     AND di.icd_version = d.icd_version
    WHERE LOWER(d.long_title) LIKE '%chest pain%'
       OR LOWER(d.long_title) LIKE '%acute myocardial infarction%'
       OR LOWER(d.long_title) LIKE '%myocardial infarction%'
  ),
  -- 3) Earliest troponin measurement per admission
  first_troponin AS (
    SELECT le.hadm_id, MIN(le.charttime) AS first_charttime
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
      ON le.itemid = dli.itemid
    WHERE LOWER(dli.label) LIKE '%troponin%'
    GROUP BY le.hadm_id
  ),
  -- 4) Values for the earliest troponin per admission
  first_troponin_values AS (
    SELECT ft.hadm_id, le.valuenum
    FROM first_troponin ft
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON le.hadm_id = ft.hadm_id
     AND le.charttime = ft.first_charttime
  ),
  -- 5) Filtered admissions: male 50-60, chest pain/AMI, initial hs-TnT > ULN (0.014)
  filtered AS (
    SELECT a.subject_id, a.hadm_id,
           (TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS los
    FROM male_age_filtered AS a
    JOIN chest_pain_ami AS cpa ON a.hadm_id = cpa.hadm_id
    JOIN first_troponin_values AS tn ON a.hadm_id = tn.hadm_id
    WHERE tn.valuenum > 0.014
  ),
  -- 6) Quantiles across the filtered dataset
  quant AS (
    SELECT APPROX_QUANTILES(los, 4) AS cuts
    FROM filtered
  )
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(*) AS admission_count,
  AVG(los) AS mean_los_days,
  (SELECT cuts[OFFSET(2)] FROM quant) AS median_los_days,
  ((SELECT cuts[OFFSET(3)] FROM quant) - (SELECT cuts[OFFSET(1)] FROM quant)) AS iqr_los_days
FROM filtered;