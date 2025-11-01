WITH first_stays AS (
  SELECT 
    subject_id, 
    hadm_id, 
    stay_id, 
    intime, 
    outtime, 
    los,
    ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
qualifying_stays AS (
  SELECT 
    fs.subject_id,
    fs.hadm_id,
    fs.stay_id,
    fs.intime,
    fs.los,
    a.hospital_expire_flag
  FROM first_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON fs.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON fs.subject_id = a.subject_id AND fs.hadm_id = a.hadm_id
  WHERE fs.rn = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = fs.subject_id 
        AND di.hadm_id = fs.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '250.1%') OR
          (di.icd_version = 10 AND (di.icd_code LIKE 'E10.1%' OR di.icd_code LIKE 'E11.1%'))
        )
    )
),
proc_counts AS (
  SELECT 
    qs.*,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM qualifying_stays qs
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.stay_id = qs.stay_id
    AND pe.starttime >= qs.intime
    AND pe.starttime < TIMESTAMP_ADD(qs.intime, INTERVAL 24 HOUR)
  GROUP BY 
    qs.subject_id, qs.hadm_id, qs.stay_id, qs.intime, qs.los, qs.hospital_expire_flag
)
SELECT 
  quintile,
  COUNT(*) AS num_stays,
  ROUND(AVG(proc_count), 2) AS mean_proc_count,
  MIN(proc_count) AS min_proc_count,
  MAX(proc_count) AS max_proc_count,
  ROUND(AVG(los), 2) AS mean_icu_los_days,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS hospital_mortality_pct
FROM (
  SELECT *, NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM proc_counts
)
GROUP BY quintile
ORDER BY quintile;