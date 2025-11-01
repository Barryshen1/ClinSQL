WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.admission_location,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND a.admission_location LIKE '%Emergency%'
),
icu_stays_filtered AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON pa.hadm_id = i.hadm_id
  WHERE pa.age_at_admission >= 59 AND pa.age_at_admission <= 69
),
systolic_bp AS (
  SELECT
    di.itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items di
  WHERE LOWER(di.label) LIKE '%systolic%'
    AND LOWER(di.category) = 'vital signs'
    AND LOWER(di.linksto) = 'chartevents'
),
max_sbp_per_stay AS (
  SELECT
    i.stay_id,
    MAX(ce.valuenum) AS max_sbp
  FROM icu_stays_filtered i
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
    ON i.stay_id = ce.stay_id
  INNER JOIN systolic_bp sbp
    ON ce.itemid = sbp.itemid
  WHERE ce.charttime >= i.intime
    AND ce.charttime <= i.outtime
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0  -- Exclude erroneous zero/negative values
  GROUP BY i.stay_id
)
SELECT
  PERCENTILE_CONT(max_sbp, 0.75) OVER() AS sbp_75th_percentile
FROM max_sbp_per_stay
LIMIT 1;