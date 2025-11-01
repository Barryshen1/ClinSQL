WITH cohort AS (
  SELECT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    a.hospital_expire_flag,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE di.subject_id = p.subject_id 
          AND di.hadm_id = i.hadm_id
          AND (
            (di.icd_version = 9 AND di.icd_code IN ('430', '431')) 
            OR 
            (di.icd_version = 10 AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%'))
          )
      ) THEN 1 
      ELSE 0 
    END AS has_stroke
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 40 AND 50
),
procs AS (
  SELECT 
    c.*,
    COUNT(pr.seq_num) AS num_procs
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON c.hadm_id = pr.hadm_id
    AND pr.chartdate >= DATE(c.intime)
    AND pr.chartdate < DATE_ADD(DATE(c.intime), INTERVAL 3 DAY)
  GROUP BY 
    c.subject_id, c.stay_id, c.hadm_id, c.intime, c.los, 
    c.hospital_expire_flag, c.has_stroke
)
SELECT 
  has_stroke,
  APPROX_QUANTILES(num_procs, 100)[OFFSET(90)] AS p90_num_procs,
  AVG(los) AS avg_icu_los_days,
  AVG(hospital_expire_flag) AS in_hosp_mortality_rate
FROM procs
GROUP BY has_stroke
ORDER BY has_stroke;