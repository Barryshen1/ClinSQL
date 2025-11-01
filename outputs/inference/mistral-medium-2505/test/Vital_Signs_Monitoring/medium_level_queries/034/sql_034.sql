WITH
-- Get male patients aged 37-47 at admission
male_patients_37_47 AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 37 AND 47
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    male_patients_37_47 mp ON i.subject_id = mp.subject_id AND i.hadm_id = mp.hadm_id
),

-- Get ICU stays with noninvasive ventilation (CPAP/BiPAP)
icu_stays_with_niv AS (
  SELECT DISTINCT
    isu.stay_id
  FROM
    icu_stays isu
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON isu.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE
    -- CPAP/BiPAP itemids (example, adjust based on actual data)
    ce.itemid IN (223848, 223849) -- Example itemids for CPAP/BiPAP, verify in d_items
),

-- Get maximum diastolic BP per ICU stay
max_diastolic_bp_per_stay AS (
  SELECT
    ce.stay_id,
    MAX(ce.valuenum) AS max_diastolic_bp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE
    ce.stay_id IN (SELECT stay_id FROM icu_stays_with_niv)
    AND di.label = 'Diastolic Blood Pressure' -- or use itemid directly (e.g., 220050)
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ce.stay_id
)

-- Calculate the 25th percentile of the maximum diastolic BP
SELECT
  PERCENTILE_CONT(max_diastolic_bp, 0.25) OVER() AS percentile_25_diastolic_bp
FROM
  max_diastolic_bp_per_stay
LIMIT 1;