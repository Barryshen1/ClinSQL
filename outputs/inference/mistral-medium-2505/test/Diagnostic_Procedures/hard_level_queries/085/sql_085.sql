WITH
-- Get female patients aged 87-97
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 87 AND 97
),

-- Get first ICU stay per admission with lower GI bleeding diagnosis
first_icu_stays AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.los AS icu_los,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY i.intime) AS icu_stay_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  JOIN
    female_patients p
    ON a.subject_id = p.subject_id
  WHERE
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code IN ('K92.2', 'K92.1', 'K92.0'))
          OR (d.icd_version = 9 AND d.icd_code IN ('578.1', '578.0', '578.9'))
        )
    )
),

-- Get only first ICU stay per admission
first_icu_stays_filtered AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    icu_intime,
    icu_outtime,
    icu_los,
    hospital_expire_flag
  FROM
    first_icu_stays
  WHERE
    icu_stay_rank = 1
),

-- Count distinct procedures in first 48 hours of ICU stay
procedure_counts AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    COUNT(DISTINCT p.itemid) AS procedure_count
  FROM
    first_icu_stays_filtered f
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON f.stay_id = p.stay_id
  WHERE
    p.starttime BETWEEN f.icu_intime
    AND TIMESTAMP_ADD(f.icu_intime, INTERVAL 48 HOUR)
  GROUP BY
    f.subject_id, f.hadm_id, f.stay_id
),

-- Create quintiles based on procedure counts
quintiles AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    procedure_count,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM
    procedure_counts
)

-- Final aggregation by quintile
SELECT
  quintile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(icu_los) AS mean_icu_los_days,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100 AS in_hospital_mortality_percent
FROM
  quintiles q
JOIN
  first_icu_stays_filtered f
  ON q.subject_id = f.subject_id AND q.hadm_id = f.hadm_id AND q.stay_id = f.stay_id
GROUP BY
  quintile
ORDER BY
  quintile;