WITH
-- Get male patients aged 77-87
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 77 AND 87
),

-- Get asthma exacerbation admissions
asthma_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    eligible_patients p ON a.subject_id = p.subject_id
  WHERE
    (d.icd_code LIKE 'J45.%' OR d.icd_code LIKE 'J44.%')
    AND d.icd_version = 10
),

-- Get first ICU stay for each admission
first_icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id, i.hadm_id ORDER BY i.intime) AS stay_rank
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    asthma_admissions a ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  WHERE
    i.intime IS NOT NULL
    AND i.outtime IS NOT NULL
),

-- Filter to first ICU stay per admission
filtered_icu_stays AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime
  FROM
    first_icu_stays
  WHERE
    stay_rank = 1
),

-- Count procedures in first 72 hours of ICU stay
procedure_counts AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    COUNT(DISTINCT p.itemid) AS procedure_count
  FROM
    filtered_icu_stays f
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON f.subject_id = p.subject_id
    AND f.hadm_id = p.hadm_id
    AND f.stay_id = p.stay_id
    AND p.starttime BETWEEN f.intime AND DATETIME_ADD(f.intime, INTERVAL 72 HOUR)
  GROUP BY
    f.subject_id, f.hadm_id
),

-- Calculate quartiles
quartiles AS (
  SELECT
    procedure_count,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM
    procedure_counts
),

-- Get hospital outcomes
hospital_outcomes AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.procedure_count,
    q.quartile,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag
  FROM
    procedure_counts p
  JOIN
    quartiles q ON p.procedure_count = q.procedure_count
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  WHERE
    a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
)

-- Final aggregation by quartile
SELECT
  quartile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(los_days) AS mean_hospital_los_days,
  AVG(CAST(hospital_expire_flag AS INT64)) AS hospital_mortality_rate
FROM
  hospital_outcomes
GROUP BY
  quartile
ORDER BY
  quartile;