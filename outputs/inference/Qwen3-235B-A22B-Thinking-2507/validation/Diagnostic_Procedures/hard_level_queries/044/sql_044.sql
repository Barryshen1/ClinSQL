WITH base_population AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 82 AND 92
    AND EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = a.hadm_id
          AND (
            (d.icd_code = '78551' AND d.icd_version = 9)
            OR (d.icd_code = 'I462' AND d.icd_version = 10)
          )
    )
),
first_icu_stay AS (
  SELECT 
    stay_id,
    hadm_id,
    intime,
    outtime
  FROM (
    SELECT 
      i.stay_id,
      i.hadm_id,
      i.intime,
      i.outtime,
      ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS stay_rank
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN base_population bp
      ON i.hadm_id = bp.hadm_id
  ) ranked
  WHERE stay_rank = 1
),
procedure_count AS (
  SELECT 
    fis.stay_id,
    fis.hadm_id,
    COUNT(pe.stay_id) AS procedure_count
  FROM first_icu_stay fis
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON fis.stay_id = pe.stay_id
    AND pe.starttime >= fis.intime
    AND pe.starttime < TIMESTAMP_ADD(fis.intime, INTERVAL 24 HOUR)
  GROUP BY fis.stay_id, fis.hadm_id
),
quintiles AS (
  SELECT 
    pc.stay_id,
    pc.hadm_id,
    pc.procedure_count,
    NTILE(5) OVER (ORDER BY pc.procedure_count) AS quintile
  FROM procedure_count pc
)
SELECT 
  q.quintile,
  AVG(q.procedure_count) AS mean_procedure_count,
  AVG(TIMESTAMP_DIFF(bp.dischtime, bp.admittime, SECOND) / 86400.0) AS mean_hospital_los_days,
  (SUM(bp.hospital_expire_flag) * 100.0 / COUNT(*)) AS mortality_pct
FROM quintiles q
INNER JOIN base_population bp
  ON q.hadm_id = bp.hadm_id
GROUP BY q.quintile
ORDER BY q.quintile;