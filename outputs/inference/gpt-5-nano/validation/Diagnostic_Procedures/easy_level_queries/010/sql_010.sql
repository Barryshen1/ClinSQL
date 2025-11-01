WITH eligible_patients AS (
  -- Male patients aged 84-94
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 84 AND 94
),
echo_events_per_admission AS (
  SELECT
    pe.subject_id,
    pe.hadm_id,
    -- Distinct occurrences of echocardiography per admission
    COUNT(DISTINCT CONCAT(
      CAST(pe.starttime AS STRING), '|',
      CAST(pe.endtime AS STRING)
    )) AS echoc_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON pe.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pe.subject_id = a.subject_id
   AND pe.hadm_id = a.hadm_id
  JOIN eligible_patients AS ep
    ON pe.subject_id = ep.subject_id
  WHERE LOWER(di.label) LIKE '%echo%'
    -- Event must occur during the hospitalization window
    AND pe.starttime BETWEEN a.admittime AND a.dischtime
  GROUP BY pe.subject_id, pe.hadm_id
),
per_patient_max AS (
  -- For each patient, the maximum number of distinct echo procedures in any single admission
  SELECT subject_id, MAX(echoc_count) AS max_echo_per_hosp
  FROM echo_events_per_admission
  GROUP BY subject_id
)
-- Overall maximum across the eligible patient cohort
SELECT
  MAX(max_echo_per_hosp) AS maximum_distinct_echocardiography_procedures_per_patient_during_hosp
FROM per_patient_max;