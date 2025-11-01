WITH first_icu AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age,
    i.stay_id, 
    i.hadm_id, 
    i.intime, 
    i.outtime, 
    i.los,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
),
qualifying_stays AS (
  SELECT 
    f.*,
    a.hospital_expire_flag
  FROM first_icu f
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON f.hadm_id = a.hadm_id
  WHERE f.rn = 1
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON d.icd_code = dd.icd_code 
        AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = f.hadm_id
        AND LOWER(dd.long_title) LIKE '%pneumonia%'
    )
),
procedures AS (
  SELECT 
    qs.stay_id,
    COUNT(pe.stay_id) AS proc_count
  FROM qualifying_stays qs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON qs.stay_id = pe.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON pe.itemid = di.itemid
  WHERE di.category IN ('Diagnostic', 'Imaging')
    AND pe.starttime >= qs.intime
    AND pe.starttime <= TIMESTAMP_ADD(qs.intime, INTERVAL 72 HOUR)
  GROUP BY qs.stay_id
),
stay_procs AS (
  SELECT 
    qs.*,
    COALESCE(p.proc_count, 0) AS proc_count
  FROM qualifying_stays qs
  LEFT JOIN procedures p 
    ON qs.stay_id = p.stay_id
)
SELECT 
  quintile,
  AVG(proc_count) AS avg_procedure_count,
  AVG(los) AS avg_icu_los_days,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_pct
FROM (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY proc_count ASC) AS quintile
  FROM stay_procs
)
GROUP BY quintile
ORDER BY quintile;