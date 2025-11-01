WITH pneumonia_hads AS (
  -- hospital admissions with any diagnosis mentioning "pneumonia"
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON d.icd_code = dic.icd_code
   AND d.icd_version = dic.icd_version
  WHERE LOWER(dic.long_title) LIKE '%pneumonia%'
),

male_pneumonia_admissions AS (
  -- restrict to male patients' admissions
  SELECT a.hadm_id, a.subject_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN pneumonia_hads ph
    ON a.hadm_id = ph.hadm_id
  WHERE LOWER(p.gender) = 'm'
),

glucose_lab_items AS (
  -- lab itemids likely representing serum/blood glucose
  SELECT itemid, label, fluid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%glucose%'
    AND (
      LOWER(COALESCE(fluid, '')) LIKE '%serum%'
      OR LOWER(COALESCE(fluid, '')) LIKE '%blood%'
      OR LOWER(label) LIKE '%serum%'
      OR LOWER(label) LIKE '%blood%'
    )
),

glucose_vals_24h AS (
  -- glucose lab measurements within first 24 hours of admission for the cohort
  SELECT
    l.hadm_id,
    l.subject_id,
    l.charttime,
    l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN glucose_lab_items gli
    ON l.itemid = gli.itemid
  JOIN male_pneumonia_admissions mpa
    ON l.hadm_id = mpa.hadm_id
  WHERE l.valuenum IS NOT NULL
    AND l.charttime >= mpa.admittime
    AND l.charttime <= TIMESTAMP_ADD(mpa.admittime, INTERVAL 24 HOUR)
),

mean_glucose_per_hadm AS (
  -- compute mean glucose per admission (first 24h)
  SELECT
    hadm_id,
    AVG(valuenum) AS mean_glucose
  FROM glucose_vals_24h
  GROUP BY hadm_id
)

-- final: 75th percentile (approximate) of per-admission mean glucose
SELECT
  -- APPROX_QUANTILES returns an array of quantiles; using 100 buckets and taking offset 75
  (APPROX_QUANTILES(mean_glucose, 100))[OFFSET(75)] AS p75_mean_serum_glucose_male_pneumonia,
  COUNT(*) AS n_admissions_used
FROM mean_glucose_per_hadm;