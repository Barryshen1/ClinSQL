WITH hhs_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    LOWER(long_title) LIKE '%hyperosmolar%' 
    AND LOWER(long_title) LIKE '%hyperglycemic%'
),

cohort AS (
  SELECT 
    p.subject_id, 
    p.anchor_age,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN hhs_codes 
        ON diag.icd_code = hhs_codes.icd_code 
        AND diag.icd_version = hhs_codes.icd_version
      WHERE diag.hadm_id = adm.hadm_id
    )
),

procedure_counts AS (
  SELECT 
    c.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
    AND pe.starttime >= c.intime
    AND pe.starttime < DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.stay_id
),

cohort_with_procedures AS (
  SELECT 
    c.*,
    COALESCE(pc.procedure_count, 0) AS procedure_count
  FROM cohort c
  LEFT JOIN procedure_counts pc
    ON c.stay_id = pc.stay_id
),

readmissions AS (
  SELECT 
    a1.hadm_id,
    MAX(CASE 
        WHEN a2.hadm_id IS NOT NULL THEN 1 
        ELSE 0 
    END) AS readmission_30d
  FROM cohort_with_procedures c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a1
    ON c.hadm_id = a1.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= DATETIME_ADD(a1.dischtime, INTERVAL 30 DAY)
  GROUP BY a1.hadm_id
),

final_cohort AS (
  SELECT 
    cwp.*,
    COALESCE(r.readmission_30d, 0) AS readmission_30d,
    NTILE(5) OVER (ORDER BY cwp.procedure_count) AS quintile
  FROM cohort_with_procedures cwp
  LEFT JOIN readmissions r
    ON cwp.hadm_id = r.hadm_id
)

SELECT 
  quintile,
  COUNT(stay_id) AS num_icu_stays,
  AVG(procedure_count) AS mean_procedures,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures,
  AVG(hospital_expire_flag) * 100 AS hospital_mortality_percent,
  AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS mean_hospital_los,
  AVG(readmission_30d) * 100 AS readmission_30d_percent
FROM final_cohort
GROUP BY quintile
ORDER BY quintile;