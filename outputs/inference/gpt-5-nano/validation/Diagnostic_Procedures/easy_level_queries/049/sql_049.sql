WITH male_81_91 AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
),

-- 2) Compute per-patient count of distinct ECG/Telemetry procedure codes observed during hospitalizations
ecg_counts_per_patient AS (
  SELECT m.subject_id,
         COUNT(DISTINCT pe.itemid) AS ecg_codes
  FROM male_81_91 m
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON icu.subject_id = m.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = icu.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.hadm_id = icu.hadm_id
   AND pe.stay_id = icu.stay_id
   AND pe.starttime >= a.admittime
   AND pe.starttime <= a.dischtime
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON di.itemid = pe.itemid
   AND (LOWER(COALESCE(di.label,'')) LIKE '%ecg%'
        OR LOWER(COALESCE(di.label,'')) LIKE '%telemetry%')
  GROUP BY m.subject_id
)

-- 3) SD of the per-patient distinct ECG/Telemetry code counts
SELECT STDDEV_SAMP(ecg_codes) AS ecg_codes_sd
FROM ecg_counts_per_patient;