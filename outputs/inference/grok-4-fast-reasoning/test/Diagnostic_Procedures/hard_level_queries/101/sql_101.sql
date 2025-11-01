WITH copd_diagnoses AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON di.icd_code = dd.icd_code 
    AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%chronic obstructive pulmonary disease%' 
    AND LOWER(dd.long_title) LIKE '%exacerbation%'
),
all_stays AS (
  SELECT 
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.los,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    CASE WHEN cd.subject_id IS NOT NULL THEN 1 ELSE 0 END AS is_copd
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON s.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON s.hadm_id = a.hadm_id
  LEFT JOIN copd_diagnoses cd 
    ON s.subject_id = cd.subject_id 
    AND s.hadm_id = cd.hadm_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 88 AND 98
),
proc_counts AS (
  SELECT 
    s.stay_id,
    COUNT(DISTINCT pe.itemid) AS num_distinct_procs
  FROM all_stays s
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
    ON pe.stay_id = s.stay_id
    AND pe.starttime >= s.intime 
    AND pe.starttime <= TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
  GROUP BY s.stay_id
)
SELECT 
  'COPD Exacerbation' AS cohort,
  APPROX_QUANTILES(COALESCE(pc.num_distinct_procs, 0), 100)[OFFSET(75)] AS p75_distinct_procs,
  AVG(s.los) AS mean_icu_los_days,
  AVG(s.hospital_expire_flag * 1.0) AS in_hospital_mortality_rate
FROM all_stays s
LEFT JOIN proc_counts pc ON s.stay_id = pc.stay_id
WHERE s.is_copd = 1
GROUP BY cohort

UNION ALL

SELECT 
  'Age-Matched (All)' AS cohort,
  NULL AS p75_distinct_procs,
  AVG(s.los) AS mean_icu_los_days,
  AVG(s.hospital_expire_flag * 1.0) AS in_hospital_mortality_rate
FROM all_stays s
LEFT JOIN proc_counts pc ON s.stay_id = pc.stay_id
GROUP BY cohort;