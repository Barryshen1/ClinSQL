WITH sbp_items AS (
  -- identify itemids that correspond to systolic BP by label pattern
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE (
    LOWER(label) LIKE '%systolic%' -- explicit systolic names
    OR (LOWER(label) LIKE '%bp%' AND LOWER(label) LIKE '%sys%') -- e.g., "BP - SYS"
  )
),
step_transfers AS (
  -- step-down / IMC transfers (take earliest such transfer per admission)
  SELECT
    subject_id,
    hadm_id,
    intime AS unit_intime,
    outtime AS unit_outtime,
    careunit,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.transfers`
  WHERE LOWER(COALESCE(careunit, '')) LIKE '%step%'
     OR LOWER(COALESCE(careunit, '')) LIKE '%imc%'
),
cohort AS (
  -- male patients aged 76-86 with a step-down/IMC transfer on the admission
  SELECT
    p.subject_id,
    a.hadm_id,
    st.unit_intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN step_transfers st
    ON a.hadm_id = st.hadm_id
   AND a.subject_id = st.subject_id
   AND st.rn = 1
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
)
SELECT
  COUNT(*) AS total_sbp_observations,
  COUNT(DISTINCT ce.subject_id) AS distinct_patients,
  STDDEV_SAMP(ce.valuenum) AS sd_sbp_mmHg
FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
JOIN sbp_items di
  ON ce.itemid = di.itemid
JOIN cohort c
  ON ce.subject_id = c.subject_id
 AND ce.hadm_id = c.hadm_id
WHERE ce.charttime BETWEEN c.unit_intime
                       AND TIMESTAMP_ADD(c.unit_intime, INTERVAL 24 HOUR)
  AND ce.valuenum IS NOT NULL
  -- plausible physiologic bounds for SBP to reduce mis-recorded values
  AND ce.valuenum > 30
  AND ce.valuenum < 300;