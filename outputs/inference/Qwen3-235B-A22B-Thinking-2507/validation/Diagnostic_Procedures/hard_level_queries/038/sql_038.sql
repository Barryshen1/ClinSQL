WITH 
target_stays AS (
  SELECT 
    p.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) / 24.0 AS icu_los
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id, 
      intime, 
      outtime,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu`.icustays
  ) i ON p.subject_id = i.subject_id AND i.rn = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a 
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 60 AND 70
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('430','431','432'))
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
        )
    )
),
target_procedure_burden AS (
  SELECT 
    ts.stay_id,
    COUNT(pe.stay_id) AS procedure_count
  FROM target_stays ts
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents pe
    ON ts.stay_id = pe.stay_id
    AND pe.starttime >= ts.intime
    AND pe.starttime <= TIMESTAMP_ADD(ts.intime, INTERVAL 72 HOUR)
  GROUP BY ts.stay_id
),
general_stays AS (
  SELECT 
    i.stay_id,
    i.intime,
    i.outtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) / 24.0 AS icu_los
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a 
    ON i.hadm_id = a.hadm_id
)
SELECT 
  (SELECT APPROX_QUANTILES(procedure_count, 100)[OFFSET(75)] 
   FROM target_procedure_burden) AS target_procedure_burden_75th,
  (SELECT AVG(icu_los) FROM target_stays) AS target_mean_icu_los,
  (SELECT AVG(hospital_expire_flag) FROM target_stays) AS target_hospital_mortality,
  (SELECT AVG(icu_los) FROM general_stays) AS general_mean_icu_los,
  (SELECT AVG(hospital_expire_flag) FROM general_stays) AS general_hospital_mortality;