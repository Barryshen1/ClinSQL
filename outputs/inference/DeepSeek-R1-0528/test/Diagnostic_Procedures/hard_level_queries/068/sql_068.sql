WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.gender,
    p.anchor_age,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    icu.stay_id,
    icu.intime AS icu_intime,
    icu.outtime AS icu_outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN (
    SELECT 
      hadm_id,
      stay_id,
      intime,
      outtime,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu
    ON adm.hadm_id = icu.hadm_id AND icu.rn = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND diag.seq_num = 1
    AND ( 
      LOWER(d.long_title) LIKE '%asthma%' AND 
      (LOWER(d.long_title) LIKE '%exacerbation%' OR 
       LOWER(d.long_title) LIKE '%status asthmaticus%')
    )
),
procedures AS (
  SELECT 
    c.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
    AND pe.starttime >= c.icu_intime
    AND pe.starttime < DATETIME_ADD(c.icu_intime, INTERVAL 72 HOUR)
  GROUP BY c.stay_id
),
proc_quartiles AS (
  SELECT 
    c.*,
    p.procedure_count,
    NTILE(4) OVER (ORDER BY p.procedure_count) AS quartile
  FROM cohort c
  LEFT JOIN procedures p
    ON c.stay_id = p.stay_id
)
SELECT 
  quartile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS mean_hospital_los,
  AVG(hospital_expire_flag) * 100 AS hospital_mortality_percent
FROM proc_quartiles
GROUP BY quartile
ORDER BY quartile;