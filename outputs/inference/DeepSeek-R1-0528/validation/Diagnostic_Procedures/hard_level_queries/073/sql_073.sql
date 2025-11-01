WITH diagnostic_procedures AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(category) LIKE '%diagnostic%'
),
cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    adm.hadm_id,
    adm.hospital_expire_flag,
    icu.stay_id,
    icu.intime AS icu_intime,
    icu.los AS icu_los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id, 
      intime, 
      los,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu 
    ON adm.hadm_id = icu.hadm_id AND icu.rn = 1
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 90 AND 100
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        diag.subject_id = adm.subject_id
        AND diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code IN ('570', '572.2', '572.4', '572.8'))
          OR 
          (diag.icd_version = 10 AND diag.icd_code IN ('K72.0', 'K72.1', 'K72.9'))
        )
    )
),
procedure_counts AS (
  SELECT 
    c.subject_id,
    c.stay_id,
    COUNT(DISTINCT pe.itemid) AS num_procedures
  FROM cohort c
  LEFT JOIN (
    SELECT 
      pe.subject_id,
      pe.stay_id,
      pe.itemid,
      pe.starttime
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    INNER JOIN diagnostic_procedures dp 
      ON pe.itemid = dp.itemid
  ) pe
    ON c.subject_id = pe.subject_id
    AND c.stay_id = pe.stay_id
    AND pe.starttime >= c.icu_intime
    AND pe.starttime < DATETIME_ADD(c.icu_intime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.stay_id
),
combined AS (
  SELECT 
    c.subject_id,
    c.stay_id,
    c.hospital_expire_flag,
    c.icu_los,
    COALESCE(pc.num_procedures, 0) AS num_procedures
  FROM cohort c
  LEFT JOIN procedure_counts pc
    ON c.subject_id = pc.subject_id AND c.stay_id = pc.stay_id
),
with_quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY num_procedures) AS quartile
  FROM combined
)
SELECT 
  quartile,
  COUNT(DISTINCT subject_id) AS num_patients,
  MIN(num_procedures) AS min_procedures,
  MAX(num_procedures) AS max_procedures,
  ROUND(AVG(num_procedures), 2) AS mean_procedures,
  ROUND(AVG(icu_los), 2) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_percent
FROM with_quartiles
GROUP BY quartile
ORDER BY quartile;