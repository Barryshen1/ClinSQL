WITH
-- Get female patients aged 53-63
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 53 AND 63
),

-- Get admissions for these patients
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    female_patients fp ON a.subject_id = fp.subject_id
),

-- Get step-down/IMC transfers
stepdown_transfers AS (
  SELECT
    t.subject_id,
    t.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.transfers` t
  JOIN
    patient_admissions pa ON t.subject_id = pa.subject_id AND t.hadm_id = pa.hadm_id
  WHERE
    t.careunit IN ('Stepdown', 'IMC')  -- Adjust based on actual careunit values in the data
),

-- Get patients who received invasive mechanical ventilation
ventilated_patients AS (
  SELECT DISTINCT
    ce.subject_id,
    ce.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    stepdown_transfers st ON ce.subject_id = st.subject_id AND ce.hadm_id = st.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE
    di.label = 'Invasive Ventilation'  -- Or use itemid 223849 if confirmed
),

-- Get nighttime SBP measurements
nighttime_sbp AS (
  SELECT
    ce.valuenum AS sbp_mmhg
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    ventilated_patients vp ON ce.subject_id = vp.subject_id AND ce.hadm_id = vp.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE
    di.label = 'Systolic Blood Pressure'  -- Or use itemid 220050 if confirmed
    AND EXTRACT(HOUR FROM ce.charttime) BETWEEN 0 AND 6  -- Nighttime (00:00-06:00)
    AND ce.valueuom = 'mmHg'  -- Ensure units are mmHg
)

-- Calculate standard deviation of nighttime SBP
SELECT
  STDDEV(sbp_mmhg) AS nighttime_sbp_stddev
FROM
  nighttime_sbp;