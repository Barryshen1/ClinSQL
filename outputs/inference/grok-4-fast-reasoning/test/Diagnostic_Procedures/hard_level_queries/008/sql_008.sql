WITH cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^(K25\.0|K25\.4|K26\.0|K26\.4|K27\.0|K27\.4|K92\.2)$'))
          OR
          (d.icd_version = 9 AND (d.icd_code LIKE '531%' OR d.icd_code LIKE '532%' OR d.icd_code LIKE '533%' OR d.icd_code LIKE '534%' OR d.icd_code LIKE '5780%'))
        )
    )
),
first_stay AS (
  SELECT
    c.*,
    fs.stay_id,
    fs.intime
  FROM cohort c
  JOIN (
    SELECT
      hadm_id,
      stay_id,
      intime,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) fs
    ON c.hadm_id = fs.hadm_id
    AND fs.rn = 1
),
with_procs AS (
  SELECT
    fs.*,
    COALESCE(
      (SELECT COUNT(DISTINCT pe.itemid)
       FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
       WHERE pe.subject_id = fs.subject_id
         AND pe.stay_id = fs.stay_id
         AND pe.starttime >= fs.intime
         AND pe.starttime < TIMESTAMP_ADD(fs.intime, INTERVAL 24 HOUR)
      ), 0
    ) AS proc_count
  FROM first_stay fs
)
SELECT
  quintile,
  AVG(proc_count) AS avg_procedures,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_hosp_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_pct
FROM (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY proc_count ASC) AS quintile
  FROM with_procs
)
GROUP BY quintile
ORDER BY quintile;