WITH patient_cohort AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 81 AND 91
),

hfnc_stays AS (
  -- Find ICU stays where High-Flow Nasal Cannula was used
  SELECT DISTINCT i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu`.inputevents i
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON i.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%high-flow nasal cannula%'
     OR LOWER(di.label) LIKE '%hfnc%'
),

systolic_bp_item AS (
  -- Get itemid for systolic blood pressure
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) = 'non invasive blood pressure systolic'
     OR LOWER(label) = 'arterial blood pressure systolic'
  -- Explicitly check known labels; avoid overbroad LIKE that might catch irrelevant items
  -- Based on MIMIC-IV documentation, these are the standard labels
),

bp_per_stay AS (
  -- For each ICU stay in hfnc_stays and in patient_cohort, compute mean systolic BP
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS mean_sbp
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN systolic_bp_item sbp
    ON ce.itemid = sbp.itemid
  INNER JOIN hfnc_stays h
    ON ce.stay_id = h.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON ce.stay_id = icu.stay_id
  INNER JOIN patient_cohort pc
    ON icu.subject_id = pc.subject_id
  WHERE ce.charttime >= icu.intime
    AND ce.charttime <= icu.outtime
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
  GROUP BY ce.stay_id
)

-- Final: get minimum of the per-stay mean systolic BP
SELECT MIN(mean_sbp) AS min_per_stay_mean_sbp
FROM bp_per_stay;