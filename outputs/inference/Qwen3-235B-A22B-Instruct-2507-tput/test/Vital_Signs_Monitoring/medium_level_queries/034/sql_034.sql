WITH patient_icu_age AS (
  SELECT
    p.subject_id,
    i.hadm_id,
    i.stay_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu`.icustays i ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 37 AND 47
),

ventilation_stays AS (
  SELECT DISTINCT
    pe.stay_id
  FROM `physionet-data.mimiciv_3_1_icu`.procedureevents pe
  JOIN `physionet-data.mimiciv_3_1_icu`.d_items di ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%cpap%'
     OR LOWER(di.label) LIKE '%bipap%'
),

dbp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE (LOWER(label) LIKE '%art dbp%'
         OR LOWER(label) LIKE '%arterial diastolic%'
         OR LOWER(label) LIKE '%arterial bp diastolic%'
         OR LOWER(label) LIKE '%non invasive bp diastolic%'
         OR LOWER(label) LIKE '%nibp diastolic%'
         OR LOWER(label) LIKE '%diastolic blood pressure%')
    AND LOWER(unitname) = 'mm hg'
),

max_dbp_per_stay AS (
  SELECT
    ce.stay_id,
    MAX(ce.valuenum) AS max_dbp
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  JOIN dbp_items dbp ON ce.itemid = dbp.itemid
  JOIN patient_icu_age pa ON ce.stay_id = pa.stay_id
  WHERE ce.valuenum IS NOT NULL
    AND LOWER(ce.valueuom) = 'mm hg'
  GROUP BY ce.stay_id
)

SELECT
  PERCENTILE_CONT(max_dbp, 0.25) OVER () AS dbp_25th_percentile
FROM max_dbp_per_stay
WHERE stay_id IN (SELECT stay_id FROM ventilation_stays)
LIMIT 1;