WITH eligible_stays AS (
  SELECT 
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.intime,
    icu.los,
    pat.gender,
    EXTRACT(YEAR FROM icu.intime) - pat.anchor_age AS age_at_icu,
    adm.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE 
    pat.gender = 'M'
    AND EXTRACT(YEAR FROM icu.intime) - pat.anchor_age BETWEEN 37 AND 47
    AND pat.anchor_age IS NOT NULL
    AND icu.stay_id IN (
      SELECT stay_id 
      FROM (
        SELECT stay_id, ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
        FROM `physionet-data.mimiciv_3_1_icu.icustays`
      ) ranked
      WHERE rn = 1
    )
),
proc_counts AS (
  SELECT 
    es.*,
    COUNT(DISTINCT proc.itemid) AS proc_count
  FROM 
    eligible_stays es
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.procedureevents` proc
    ON es.stay_id = proc.stay_id
    AND proc.starttime <= es.intime + INTERVAL 48 HOUR
  GROUP BY 
    es.stay_id, es.subject_id, es.hadm_id, es.intime, es.los, es.gender, 
    es.age_at_icu, es.hospital_expire_flag
),
quintiled AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM 
    proc_counts
)
SELECT 
  quintile AS quintile,
  ROUND(AVG(proc_count), 2) AS mean_procedure_count,
  ROUND(AVG(los), 2) AS mean_icu_los_days,
  ROUND(AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) * 100, 2) AS mean_hospital_mortality_pct
FROM 
  quintiled
GROUP BY 
  quintile
ORDER BY 
  quintile;