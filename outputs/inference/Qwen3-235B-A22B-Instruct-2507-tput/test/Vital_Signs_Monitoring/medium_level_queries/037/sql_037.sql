WITH patient_icu_age AS (
  SELECT
    p.subject_id,
    p.gender,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 88 AND 98
),

hfnc_patients AS (
  SELECT DISTINCT
    stay_id
  FROM `physionet-data.mimiciv_3_1_icu`.procedureevents
  WHERE itemid = 227187  -- 'High Flow Oxygen' as proxy for HFNC
),

gcs_later_days AS (
  SELECT
    ce.valuenum AS gcs_total
  FROM patient_icu_age pia
  INNER JOIN hfnc_patients h
    ON pia.stay_id = h.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
    ON pia.stay_id = ce.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  WHERE di.label = 'GCS Total'
    AND ce.charttime >= DATETIME_ADD(pia.intime, INTERVAL 2 DAY)
    AND ce.valuenum IS NOT NULL
)

SELECT
  APPROX_QUANTILES(gcs_total, 100)[OFFSET(50)] AS median_gcs_total
FROM gcs_later_days;