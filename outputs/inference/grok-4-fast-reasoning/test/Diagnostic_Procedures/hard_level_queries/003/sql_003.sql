WITH ards_hadms AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code IN ('518.5', '518.82', 'J80')
),
subgroup_adms AS (
  SELECT DISTINCT 
    a.hadm_id, 
    a.subject_id,
    p.anchor_age, 
    p.gender,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN ards_hadms ar 
    ON a.subject_id = ar.subject_id AND a.hadm_id = ar.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F' 
    AND p.anchor_age >= 84 
    AND p.anchor_age <= 94
),
first_stays_sub AS (
  SELECT hadm_id, stay_id, intime
  FROM (
    SELECT hadm_id, stay_id, intime,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    WHERE hadm_id IN (SELECT hadm_id FROM subgroup_adms)
  ) 
  WHERE rn = 1
),
procs_sub AS (
  SELECT 
    fs.hadm_id,
    COUNT(DISTINCT pe.itemid) AS distinct_procs
  FROM first_stays_sub fs
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.stay_id = fs.stay_id
    AND pe.starttime >= fs.intime
    AND pe.starttime < TIMESTAMP_ADD(fs.intime, INTERVAL 24 HOUR)
  GROUP BY fs.hadm_id
),
subgroup_metrics AS (
  SELECT 
    sa.hadm_id,
    COALESCE(ps.distinct_procs, 0) AS distinct_procs,
    sa.los,
    sa.hospital_expire_flag
  FROM subgroup_adms sa
  LEFT JOIN procs_sub ps 
    ON sa.hadm_id = ps.hadm_id
),
general_adms AS (
  SELECT DISTINCT 
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.hadm_id = i.hadm_id
),
first_stays_gen AS (
  SELECT hadm_id, stay_id, intime
  FROM (
    SELECT hadm_id, stay_id, intime,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) 
  WHERE rn = 1
),
procs_gen AS (
  SELECT 
    fs.hadm_id,
    COUNT(DISTINCT pe.itemid) AS distinct_procs
  FROM first_stays_gen fs
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.stay_id = fs.stay_id
    AND pe.starttime >= fs.intime
    AND pe.starttime < TIMESTAMP_ADD(fs.intime, INTERVAL 24 HOUR)
  GROUP BY fs.hadm_id
),
general_metrics AS (
  SELECT 
    ga.hadm_id,
    COALESCE(pg.distinct_procs, 0) AS distinct_procs,
    ga.los,
    ga.hospital_expire_flag
  FROM general_adms ga
  LEFT JOIN procs_gen pg 
    ON ga.hadm_id = pg.hadm_id
)
SELECT 
  'ARDS 84-94 Female' AS cohort,
  q4[OFFSET(1)] AS p25_procs,
  q4[OFFSET(3)] AS p75_procs,
  q20[OFFSET(19)] AS p95_procs,
  avg_los AS avg_hosp_los_days,
  avg_mort AS hosp_mortality_rate
FROM (
  SELECT 
    APPROX_QUANTILES(distinct_procs, 4) AS q4,
    APPROX_QUANTILES(distinct_procs, 20) AS q20,
    AVG(los) AS avg_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS avg_mort
  FROM subgroup_metrics
)
UNION ALL
SELECT 
  'General ICU' AS cohort,
  q4[OFFSET(1)] AS p25_procs,
  q4[OFFSET(3)] AS p75_procs,
  q20[OFFSET(19)] AS p95_procs,
  avg_los AS avg_hosp_los_days,
  avg_mort AS hosp_mortality_rate
FROM (
  SELECT 
    APPROX_QUANTILES(distinct_procs, 4) AS q4,
    APPROX_QUANTILES(distinct_procs, 20) AS q20,
    AVG(los) AS avg_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS avg_mort
  FROM general_metrics
);