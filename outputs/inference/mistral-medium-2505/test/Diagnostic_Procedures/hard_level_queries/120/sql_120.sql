WITH
-- Get male patients aged 74-84
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 74 AND 84
),

-- Get upper GI bleeding admissions (using common ICD codes for upper GI bleeding)
upper_gi_bleeding_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    a.subject_id IN (SELECT subject_id FROM eligible_patients)
    AND d.icd_code IN (
      '531.00', '531.01', '531.20', '531.21', '531.40', '531.41', '531.60', '531.61',
      '532.00', '532.01', '532.20', '532.21', '532.40', '532.41', '532.60', '532.61',
      '533.00', '533.01', '533.20', '533.21', '533.40', '533.41', '533.60', '533.61',
      '534.00', '534.01', '534.20', '534.21', '534.40', '534.41', '534.60', '534.61',
      '578.0', '578.1', '578.9', 'K25.0', 'K25.2', 'K25.4', 'K25.6', 'K26.0', 'K26.2',
      'K26.4', 'K26.6', 'K27.0', 'K27.2', 'K27.4', 'K27.6', 'K28.0', 'K28.2', 'K28.4',
      'K28.6', 'K92.0', 'K92.1', 'K92.2'
    )
),

-- Get first ICU stay per admission
first_icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime AS icu_intime,
    s.outtime AS icu_outtime,
    ROW_NUMBER() OVER (PARTITION BY s.subject_id, s.hadm_id ORDER BY s.intime) AS icu_stay_rank
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    upper_gi_bleeding_admissions a
    ON s.subject_id = a.subject_id AND s.hadm_id = a.hadm_id
  WHERE
    s.intime IS NOT NULL
),

-- Get procedure counts in first 72 hours of ICU stay
procedure_counts AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    COUNT(DISTINCT p.itemid) AS procedure_count
  FROM
    first_icu_stays f
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON f.subject_id = p.subject_id
    AND f.hadm_id = p.hadm_id
    AND f.stay_id = p.stay_id
    AND p.starttime BETWEEN f.icu_intime
      AND TIMESTAMP_ADD(f.icu_intime, INTERVAL 72 HOUR)
  WHERE
    f.icu_stay_rank = 1  -- Only first ICU stay
  GROUP BY
    f.subject_id, f.hadm_id, f.stay_id
),

-- Calculate quartiles for procedure counts
quartiles AS (
  SELECT
    procedure_count,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM
    procedure_counts
),

-- Join all data together
final_data AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.procedure_count,
    q.quartile,
    a.hospital_los_days,
    a.hospital_expire_flag
  FROM
    procedure_counts p
  JOIN
    quartiles q
    ON p.procedure_count = q.procedure_count
  JOIN
    upper_gi_bleeding_admissions a
    ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
)

-- Final aggregation by quartile
SELECT
  quartile,
  COUNT(*) AS patient_count,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(hospital_los_days) AS mean_hospital_los_days,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) /
    COUNT(*) AS in_hospital_mortality_rate
FROM
  final_data
GROUP BY
  quartile
ORDER BY
  quartile;