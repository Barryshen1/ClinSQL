WITH asthma_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND d.icd_version = 10
    AND LOWER(d_icd.long_title) LIKE '%asthma%'
    AND LOWER(d_icd.long_title) LIKE '%exacerbation%'
),
first_icu_stay AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los AS icu_los_days,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN asthma_patients ap ON i.hadm_id = ap.hadm_id
),
first_icu_procedures AS (
  SELECT
    f.stay_id,
    COUNT(*) AS procedure_count_72h
  FROM first_icu_stay f
  INNER JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON f.stay_id = pe.stay_id
  WHERE pe.starttime >= f.intime
    AND pe.starttime <= DATETIME_ADD(f.intime, INTERVAL 72 HOUR)
  GROUP BY f.stay_id
),
hospital_los AS (
  SELECT
    ap.subject_id,
    ap.hadm_id,
    ap.hospital_expire_flag,
    DATETIME_DIFF(ap.dischtime, ap.admittime, DAY) AS hospital_los_days
  FROM asthma_patients ap
),
quartile_data AS (
  SELECT
    h.hospital_los_days,
    h.hospital_expire_flag,
    COALESCE(p.procedure_count_72h, 0) AS procedure_count_72h,
    NTILE(4) OVER (ORDER BY COALESCE(p.procedure_count_72h, 0)) AS procedure_quartile
  FROM hospital_los h
  INNER JOIN first_icu_stay fis ON h.hadm_id = fis.hadm_id
  LEFT JOIN first_icu_procedures p ON fis.stay_id = p.stay_id
)
SELECT
  procedure_quartile,
  AVG(procedure_count_72h) AS mean_procedure_count,
  AVG(hospital_los_days) AS mean_hospital_los_days,
  AVG(hospital_expire_flag) AS mean_hospital_mortality
FROM quartile_data
GROUP BY procedure_quartile
ORDER BY procedure_quartile;