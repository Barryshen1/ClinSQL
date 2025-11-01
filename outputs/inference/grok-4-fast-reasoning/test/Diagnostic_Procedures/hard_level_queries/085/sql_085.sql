WITH first_stays AS (
  SELECT 
    i.subject_id, 
    i.stay_id, 
    i.hadm_id, 
    i.intime, 
    i.outtime, 
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 87 AND 97
),
eligible_stays AS (
  SELECT subject_id, stay_id, hadm_id, intime, outtime, los
  FROM first_stays fs
  WHERE fs.rn = 1
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = fs.subject_id 
        AND d.hadm_id = fs.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code = '5693') OR 
          (d.icd_version = 10 AND d.icd_code = 'K922')
        )
    )
),
patient_procs AS (
  SELECT 
    es.subject_id, 
    es.stay_id, 
    es.hadm_id, 
    es.intime, 
    es.los,
    a.hospital_expire_flag,
    COUNT(DISTINCT pe.itemid) AS num_procs
  FROM eligible_stays es
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON es.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
    ON es.stay_id = pe.stay_id 
    AND pe.starttime >= es.intime 
    AND pe.starttime <= TIMESTAMP_ADD(es.intime, INTERVAL 48 HOUR)
  GROUP BY 
    es.subject_id, es.stay_id, es.hadm_id, es.intime, es.los, a.hospital_expire_flag
)
SELECT 
  NTILE(5) OVER (ORDER BY num_procs) AS quintile,
  AVG(num_procs) AS mean_procedure_count,
  AVG(los) AS mean_icu_los_days,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_pct
FROM patient_procs
GROUP BY quintile
ORDER BY quintile;