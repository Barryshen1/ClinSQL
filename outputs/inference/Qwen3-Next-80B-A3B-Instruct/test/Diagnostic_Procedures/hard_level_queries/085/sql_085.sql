WITH female_elderly AS (
  SELECT subject_id, anchor_age
  FROM physionet-data.mimiciv_3_1_hosp.patients
  WHERE gender = 'F' 
    AND anchor_age BETWEEN 87 AND 97
),

first_icu_stay AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN female_elderly f ON i.subject_id = f.subject_id
),

lower_gi_bleeding AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_diag
    ON d.icd_code = d_diag.icd_code AND d.icd_version = d_diag.icd_version
  WHERE LOWER(d_diag.long_title) LIKE '%lower%gastrointestin%' 
     OR LOWER(d_diag.long_title) LIKE '%lower%gi%bleed%'
     OR LOWER(d_diag.long_title) LIKE '%gastrointestinal hemorrhage, lower%'
),

procedures_in_48h AS (
  SELECT 
    i.stay_id,
    COUNT(DISTINCT p.itemid) AS distinct_procedure_count
  FROM first_icu_stay i
  INNER JOIN physionet-data.mimiciv_3_1_icu.procedureevents p
    ON i.stay_id = p.stay_id
  WHERE p.starttime >= i.intime 
    AND p.starttime <= TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
  GROUP BY i.stay_id
),

cohort_with_procedures AS (
  SELECT 
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.los,
    COALESCE(p.distinct_procedure_count, 0) AS distinct_procedure_count,
    a.hospital_expire_flag
  FROM first_icu_stay f
  INNER JOIN lower_gi_bleeding l ON f.hadm_id = l.hadm_id
  LEFT JOIN procedures_in_48h p ON f.stay_id = p.stay_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON f.hadm_id = a.hadm_id
  WHERE f.rn = 1
),

quintiles AS (
  SELECT *,
    NTILE(5) OVER (ORDER BY distinct_procedure_count) AS procedure_quintile
  FROM cohort_with_procedures
)

SELECT 
  procedure_quintile,
  AVG(distinct_procedure_count) AS mean_procedure_count,
  AVG(los) AS mean_icu_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS in_hospital_mortality_percent
FROM quintiles
GROUP BY procedure_quintile
ORDER BY procedure_quintile;