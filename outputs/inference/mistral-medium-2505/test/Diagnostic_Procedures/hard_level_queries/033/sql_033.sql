WITH first_icu_stays AS (
  -- Get each patient's first ICU stay
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS icu_stay_seq
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

eligible_patients AS (
  -- Male patients aged 37-47 in their first ICU stay
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    f.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN first_icu_stays f ON p.subject_id = f.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id AND f.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND f.icu_stay_seq = 1  -- First ICU stay
),

procedures_first_48h AS (
  -- Procedures performed in first 48 hours of ICU stay
  SELECT
    e.subject_id,
    e.hadm_id,
    e.stay_id,
    e.itemid,
    e.starttime,
    d.label AS procedure_name
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` e
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON e.itemid = d.itemid
  JOIN eligible_patients p ON e.subject_id = p.subject_id AND e.hadm_id = p.hadm_id AND e.stay_id = p.stay_id
  WHERE TIMESTAMP_DIFF(e.starttime, p.intime, HOUR) <= 48
),

patient_procedure_counts AS (
  -- Count distinct procedures per patient
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    COUNT(DISTINCT itemid) AS procedure_count
  FROM procedures_first_48h
  GROUP BY subject_id, hadm_id, stay_id
),

quintiles AS (
  -- Assign patients to quintiles based on procedure count
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    p.procedure_count,
    NTILE(5) OVER (ORDER BY p.procedure_count) AS quintile,
    e.los,
    e.hospital_expire_flag
  FROM patient_procedure_counts p
  JOIN eligible_patients e ON p.subject_id = e.subject_id AND p.hadm_id = e.hadm_id AND p.stay_id = e.stay_id
)

-- Final results by quintile
SELECT
  quintile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(los) AS mean_icu_los_days,
  AVG(CAST(hospital_expire_flag AS INT64)) AS hospital_mortality_rate
FROM quintiles
GROUP BY quintile
ORDER BY quintile;