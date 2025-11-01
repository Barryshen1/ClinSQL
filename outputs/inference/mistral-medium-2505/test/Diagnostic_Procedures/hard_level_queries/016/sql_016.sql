WITH
-- Get male patients aged 88-98
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 88 AND 98
),

-- Get first ICU stays with pneumonia diagnosis
first_icu_stays_with_pneumonia AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.los AS icu_los_hours,
    a.hospital_expire_flag
  FROM
    eligible_patients p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    -- First ICU stay per admission
    i.intime = (
      SELECT MIN(intime)
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i2
      WHERE i2.subject_id = i.subject_id AND i2.hadm_id = i.hadm_id
    )
    -- Pneumonia diagnosis (using common pneumonia ICD codes)
    AND (di.icd_code LIKE 'J18.%' OR di.icd_code LIKE 'J13.%' OR di.icd_code LIKE 'J15.%')
),

-- Count diagnostic procedures in first 72 hours of ICU stay
procedure_counts AS (
  SELECT
    f.subject_id,
    f.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM
    first_icu_stays_with_pneumonia f
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON f.subject_id = pe.subject_id AND f.stay_id = pe.stay_id
  WHERE
    -- Procedures within first 72 hours of ICU admission
    TIMESTAMP_DIFF(pe.starttime, f.icu_intime, HOUR) <= 72
    -- Filter for diagnostic procedures (example itemids, adjust as needed)
    AND pe.itemid IN (
      SELECT itemid
      FROM `physionet-data.mimiciv_3_1_icu.d_items`
      WHERE category LIKE '%diagnostic%'
    )
  GROUP BY
    f.subject_id, f.stay_id
),

-- Calculate quintiles
quintiles AS (
  SELECT
    subject_id,
    stay_id,
    procedure_count,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM
    procedure_counts
)

-- Final aggregation by quintile
SELECT
  q.quintile,
  AVG(q.procedure_count) AS avg_procedure_count,
  AVG(f.icu_los_hours / 24) AS avg_icu_los_days,
  AVG(CAST(f.hospital_expire_flag AS INT64)) * 100 AS mortality_percentage
FROM
  quintiles q
JOIN
  first_icu_stays_with_pneumonia f
  ON q.subject_id = f.subject_id AND q.stay_id = f.stay_id
GROUP BY
  q.quintile
ORDER BY
  q.quintile;