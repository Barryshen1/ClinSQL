WITH ARDS_female_stays AS (
  SELECT DISTINCT i.stay_id, i.hadm_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON a.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON p.subject_id = i.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = i.subject_id AND di.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND di.icd_version = 9
    AND di.icd_code = '518.82'
),

ARDS_intensity AS (
  SELECT r.stay_id, COUNT(DISTINCT pe.itemid) AS distinct_proc_24h
  FROM ARDS_female_stays AS r
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON i.stay_id = r.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON pe.stay_id = i.stay_id
   AND pe.starttime >= i.intime
   AND pe.starttime < TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
  GROUP BY r.stay_id
),

ARDS_quantiles AS (
  SELECT quantiles[OFFSET(25)] AS p25,
         quantiles[OFFSET(75)] AS p75,
         quantiles[OFFSET(95)] AS p95
  FROM (
    SELECT APPROX_QUANTILES(distinct_proc_24h, 100) AS quantiles
    FROM ARDS_intensity
  )
),

ARDS_outcomes AS (
  SELECT AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS avg_hosp_los_days,
         AVG(CASE WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 1.0 ELSE 0.0 END) AS hosp_mortality_rate
  FROM ARDS_female_stays AS r
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON a.hadm_id = r.hadm_id
),

-- All ICU population: diagnostic intensity, LOS, mortality

ALL_intensity AS (
  SELECT s.stay_id, s.hadm_id, COUNT(DISTINCT pe.itemid) AS distinct_proc_24h
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON pe.stay_id = s.stay_id
   AND pe.starttime >= s.intime
   AND pe.starttime < TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
  GROUP BY s.stay_id, s.hadm_id
),

ALL_quantiles AS (
  SELECT quantiles[OFFSET(25)] AS p25,
         quantiles[OFFSET(75)] AS p75,
         quantiles[OFFSET(95)] AS p95
  FROM (
    SELECT APPROX_QUANTILES(distinct_proc_24h, 100) AS quantiles
    FROM ALL_intensity
  )
),

ALL_outcomes AS (
  SELECT AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS avg_hosp_los_days,
         AVG(CASE WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 1.0 ELSE 0.0 END) AS hosp_mortality_rate
  FROM ALL_intensity AS s
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON a.hadm_id = s.hadm_id
)

SELECT
  'ARDS_female_84_94' AS group_name,
  ARDS_q.p25,
  ARDS_q.p75,
  ARDS_q.p95,
  ARDS_o.avg_hosp_los_days,
  ARDS_o.hosp_mortality_rate
FROM ARDS_quantiles AS ARDS_q
CROSS JOIN ARDS_outcomes AS ARDS_o

UNION ALL

SELECT
  'All_ICU_population' AS group_name,
  ALL_q.p25,
  ALL_q.p75,
  ALL_q.p95,
  ALL_o.avg_hosp_los_days,
  ALL_o.hosp_mortality_rate
FROM ALL_quantiles AS ALL_q
CROSS JOIN ALL_outcomes AS ALL_o;