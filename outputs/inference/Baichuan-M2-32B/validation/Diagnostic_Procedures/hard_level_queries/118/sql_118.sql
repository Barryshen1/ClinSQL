WITH ami_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE 
    (d.icd_code LIKE '410%' AND d.icd_version = 9) 
    OR (d.icd_code LIKE 'I21%' AND d.icd_version = 10)
),
base_cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_hospital_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN ami_admissions ami
    ON a.subject_id = ami.subject_id AND a.hadm_id = ami.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
),
first_icu_stays AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN base_cohort b
    ON i.subject_id = b.subject_id AND i.hadm_id = b.hadm_id
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY i.hadm_id 
    ORDER BY i.intime
  ) = 1
),
procedure_counts AS (
  SELECT 
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    COALESCE(COUNT(p.starttime), 0) AS procedure_count
  FROM first_icu_stays f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON f.subject_id = p.subject_id 
    AND f.hadm_id = p.hadm_id 
    AND f.stay_id = p.stay_id
    AND p.starttime BETWEEN f.intime AND f.intime + INTERVAL 72 HOUR
  GROUP BY f.subject_id, f.hadm_id, f.stay_id, f.intime
),
final_data AS (
  SELECT 
    b.subject_id,
    b.hadm_id,
    b.los_hospital_days,
    b.hospital_expire_flag,
    pc.procedure_count
  FROM base_cohort b
  INNER JOIN procedure_counts pc
    ON b.subject_id = pc.subject_id AND b.hadm_id = pc.hadm_id
),
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM final_data
)
SELECT 
  quartile,
  COUNT(*) AS n,
  AVG(procedure_count) AS mean_procedure_count,
  COALESCE(AVG(los_hospital_days), 0) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_percent
FROM quartiles
GROUP BY quartile
ORDER BY quartile;