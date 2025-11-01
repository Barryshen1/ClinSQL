WITH cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los,
    adm.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND ie.hadm_id IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 10 AND icd_code IN ('E1010', 'E1011', 'E1110', 'E1111', 'E1310', 'E1311'))
        OR
        (icd_version = 9 AND icd_code IN ('25010', '25011', '25012', '25013'))
    )
),
first_stay AS (
  SELECT 
    *,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS stay_seq
  FROM cohort
),
procedures_first_24h AS (
  SELECT 
    fs.stay_id,
    COUNT(DISTINCT pe.itemid) AS distinct_procedure_count
  FROM first_stay fs
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON fs.stay_id = pe.stay_id
    AND pe.starttime >= fs.intime
    AND pe.starttime <= DATETIME_ADD(fs.intime, INTERVAL 24 HOUR)
  WHERE fs.stay_seq = 1
  GROUP BY fs.stay_id
),
with_quintiles AS (
  SELECT 
    fs.*,
    COALESCE(pf.distinct_procedure_count, 0) AS distinct_procedure_count,
    NTILE(5) OVER (ORDER BY COALESCE(pf.distinct_procedure_count, 0)) AS quintile
  FROM first_stay fs
  LEFT JOIN procedures_first_24h pf
    ON fs.stay_id = pf.stay_id
  WHERE fs.stay_seq = 1
)
SELECT 
  quintile,
  COUNT(stay_id) AS num_stays,
  AVG(distinct_procedure_count) AS mean_procedure_count,
  MIN(distinct_procedure_count) AS min_procedure_count,
  MAX(distinct_procedure_count) AS max_procedure_count,
  AVG(los / 24.0) AS mean_icu_los_days,
  100.0 * SUM(hospital_expire_flag) / COUNT(stay_id) AS hospital_mortality_percent
FROM with_quintiles
GROUP BY quintile
ORDER BY quintile;