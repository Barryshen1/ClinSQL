WITH patients AS (
  SELECT DISTINCT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 65 AND 75
),
first_stays AS (
  SELECT 
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    ROW_NUMBER() OVER (PARTITION BY s.subject_id ORDER BY s.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN patients p ON s.subject_id = p.subject_id
),
eligible_stays AS (
  SELECT 
    fs.subject_id,
    fs.hadm_id,
    fs.stay_id,
    fs.intime,
    fs.los,
    a.hospital_expire_flag
  FROM first_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON fs.hadm_id = a.hadm_id
  WHERE fs.rn = 1
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = fs.subject_id 
        AND d.hadm_id = fs.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '415.1%') 
          OR 
          (d.icd_version = 10 AND d.icd_code LIKE 'I26%')
        )
    )
),
proc_counts AS (
  SELECT 
    es.stay_id,
    es.los,
    es.hospital_expire_flag,
    COUNT(pe.stay_id) AS proc_count
  FROM eligible_stays es
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.subject_id = es.subject_id
    AND pe.hadm_id = es.hadm_id
    AND pe.stay_id = es.stay_id
    AND pe.starttime >= es.intime
    AND pe.starttime < TIMESTAMP_ADD(es.intime, INTERVAL 72 HOUR)
  GROUP BY es.stay_id, es.los, es.hospital_expire_flag
),
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY proc_count ASC) AS quartile
  FROM proc_counts
)
SELECT 
  quartile,
  COUNT(*) AS N,
  ROUND(AVG(proc_count), 2) AS mean_proc_count,
  ROUND(AVG(los), 2) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct
FROM quartiles
GROUP BY quartile
ORDER BY quartile;