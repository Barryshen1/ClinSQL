WITH hepatic_patients AS (
  -- Identify patients with hepatic failure diagnosis
  SELECT DISTINCT
    di.subject_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%hepatic failure%'
),
first_icu_stays AS (
  -- Get first ICU stay for each patient using ROW_NUMBER
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM
      physionet-data.mimiciv_3_1_icu.icustays
  ) i
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON i.hadm_id = a.hadm_id
  WHERE
    i.rn = 1
),
eligible_patients AS (
  -- Filter for male patients aged 90–100 with hepatic failure and first ICU stay
  SELECT
    p.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    f.los,
    f.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    first_icu_stays f
    ON p.subject_id = f.subject_id
  JOIN
    hepatic_patients h
    ON p.subject_id = h.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),
procedures_in_window AS (
  -- Get diagnostic procedures within 72 hours of ICU intime
  SELECT
    ep.subject_id,
    ep.stay_id,
    ep.los,
    ep.hospital_expire_flag,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM
    eligible_patients ep
  JOIN
    physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON ep.stay_id = pe.stay_id
  JOIN
    physionet-data.mimiciv_3_1_icu.d_items di
    ON pe.itemid = di.itemid
  WHERE
    di.category = 'Diagnostic'
    AND pe.starttime >= ep.intime
    AND pe.starttime <= ep.intime + INTERVAL 72 HOUR
  GROUP BY
    ep.subject_id, ep.stay_id, ep.los, ep.hospital_expire_flag
),
quartiled_data AS (
  -- Stratify patients into quartiles by procedure count
  SELECT
    subject_id,
    stay_id,
    proc_count,
    NTILE(4) OVER (ORDER BY proc_count) AS quartile,
    los,
    hospital_expire_flag
  FROM
    procedures_in_window
)
-- Final aggregation by quartile
SELECT
  quartile,
  COUNT(*) AS num_patients,
  MIN(proc_count) AS min_procedures,
  MAX(proc_count) AS max_procedures,
  AVG(proc_count) AS mean_procedures,
  AVG(los) AS mean_los_days,
  100 * AVG(hospital_expire_flag) AS in_hospital_mortality_percent
FROM
  quartiled_data
GROUP BY
  quartile
ORDER BY
  quartile;