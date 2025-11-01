WITH first_icu_stay AS (
  SELECT 
    stay.subject_id,
    stay.hadm_id,
    stay.stay_id,
    stay.intime,
    stay.los AS icu_los,
    pat.gender,
    (EXTRACT(YEAR FROM stay.intime) - (pat.anchor_year - pat.anchor_age)) AS age_at_icu_admit
  FROM `physionet-data.mimiciv_3_1_icu.icustays` stay
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON stay.subject_id = pat.subject_id
  WHERE stay.stay_id IS NOT NULL
),
ranked_stays AS (
  SELECT 
    *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS stay_rank
  FROM first_icu_stay
),
first_stay_filtered AS (
  SELECT *
  FROM ranked_stays
  WHERE stay_rank = 1
    AND gender = 'M'
    AND age_at_icu_admit BETWEEN 37 AND 47
),
pneumonia_patients AS (
  SELECT DISTINCT fst.*
  FROM first_stay_filtered fst
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON fst.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE LOWER(d_diag.long_title) LIKE '%pneumonia%'
),
procedures_48h AS (
  SELECT 
    p.subject_id,
    COUNT(*) AS procedure_count
  FROM pneumonia_patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON p.stay_id = pe.stay_id
  WHERE pe.starttime >= p.intime
    AND pe.starttime <= p.intime + INTERVAL '48' HOUR
    AND pe.starttime IS NOT NULL
  GROUP BY p.subject_id
),
quintiles AS (
  SELECT 
    p.*,
    COALESCE(proc.procedure_count, 0) AS procedure_count,
    NTILE(5) OVER (ORDER BY COALESCE(proc.procedure_count, 0)) AS quintile
  FROM pneumonia_patients p
  LEFT JOIN procedures_48h proc ON p.subject_id = proc.subject_id
),
final_data AS (
  SELECT 
    q.quintile,
    q.procedure_count,
    q.icu_los,
    a.hospital_expire_flag
  FROM quintiles q
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON q.hadm_id = a.hadm_id
)
SELECT
  quintile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(icu_los) AS mean_icu_los_days,
  AVG(hospital_expire_flag) AS hospital_mortality_rate
FROM final_data
GROUP BY quintile
ORDER BY quintile;