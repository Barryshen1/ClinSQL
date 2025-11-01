WITH cardiogenic_shock_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    p.gender,
    d.hadm_id,
    a.hospital_expire_flag,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    ON p.subject_id = d.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON d.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND LOWER(dicd.long_title) LIKE '%cardiogenic shock%'
),

first_icu_stay AS (
  SELECT
    cs.subject_id,
    cs.hadm_id,
    cs.hospital_expire_flag,
    cs.admittime,
    cs.dischtime,
    i.stay_id,
    i.intime,
    i.outtime,
    ROW_NUMBER() OVER (PARTITION BY cs.hadm_id ORDER BY i.intime) AS rn
  FROM cardiogenic_shock_patients cs
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON cs.subject_id = i.subject_id AND cs.hadm_id = i.hadm_id
),

first_24h_procedures AS (
  SELECT
    fis.stay_id,
    COUNT(*) AS procedure_count_24h
  FROM first_icu_stay fis
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents pe
    ON fis.stay_id = pe.stay_id
    AND pe.starttime >= fis.intime
    AND pe.starttime < TIMESTAMP_ADD(fis.intime, INTERVAL 24 HOUR)
  WHERE fis.rn = 1
  GROUP BY fis.stay_id
),

hospital_los AS (
  SELECT
    fis.subject_id,
    fis.hadm_id,
    fis.stay_id,
    fis.hospital_expire_flag,
    TIMESTAMP_DIFF(fis.dischtime, fis.admittime, DAY) AS hospital_los_days,
    COALESCE(p24.procedure_count_24h, 0) AS procedure_count_24h
  FROM first_icu_stay fis
  LEFT JOIN first_24h_procedures p24
    ON fis.stay_id = p24.stay_id
  WHERE fis.rn = 1
),

quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY procedure_count_24h) AS procedure_quintile
  FROM hospital_los
)

SELECT
  procedure_quintile,
  AVG(procedure_count_24h) AS mean_procedure_count,
  AVG(hospital_los_days) AS mean_hospital_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT)) * 100 AS in_hospital_mortality_percentage
FROM quintiles
GROUP BY procedure_quintile
ORDER BY procedure_quintile;