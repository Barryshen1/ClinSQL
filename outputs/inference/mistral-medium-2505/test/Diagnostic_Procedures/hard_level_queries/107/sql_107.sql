WITH
-- Get female patients aged 65-75 with pulmonary embolism
pe_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND di.icd_code LIKE 'I26.%'
),

-- Get first ICU stay per admission within 72 hours of admission
first_icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    ROW_NUMBER() OVER (PARTITION BY s.subject_id, s.hadm_id ORDER BY s.intime) AS icu_stay_rank
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    pe_patients p
    ON s.subject_id = p.subject_id AND s.hadm_id = p.hadm_id
  WHERE
    TIMESTAMP_DIFF(s.intime, p.admittime, HOUR) <= 72
),

-- Count diagnostic procedures within first 72 hours of ICU admission
procedure_counts AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    COUNT(DISTINCT pe.orderid) AS procedure_count
  FROM
    first_icu_stays f
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON f.subject_id = pe.subject_id
    AND f.hadm_id = pe.hadm_id
    AND f.stay_id = pe.stay_id
    AND TIMESTAMP_DIFF(pe.starttime, f.intime, HOUR) <= 72
  WHERE
    pe.ordercategoryname LIKE '%Diagnostic%'
    OR pe.itemid IN (
      SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items`
      WHERE category LIKE '%Diagnostic%'
    )
  GROUP BY
    f.subject_id, f.hadm_id, f.stay_id
),

-- Calculate quartiles
quartiles AS (
  SELECT
    procedure_count,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM
    procedure_counts
)

-- Final stratified results
SELECT
  q.quartile,
  COUNT(DISTINCT pc.subject_id) AS N,
  AVG(pc.procedure_count) AS mean_procedure_count,
  AVG(f.los) AS mean_icu_los_days,
  AVG(CASE WHEN p.hospital_expire_flag = 1 THEN 100 ELSE 0 END) AS hospital_mortality_percent
FROM
  procedure_counts pc
JOIN
  first_icu_stays f
  ON pc.subject_id = f.subject_id
  AND pc.hadm_id = f.hadm_id
  AND pc.stay_id = f.stay_id
JOIN
  pe_patients p
  ON pc.subject_id = p.subject_id
  AND pc.hadm_id = p.hadm_id
JOIN
  quartiles q
  ON pc.procedure_count = q.procedure_count
WHERE
  f.icu_stay_rank = 1  -- Only first ICU stay
GROUP BY
  q.quartile
ORDER BY
  q.quartile;