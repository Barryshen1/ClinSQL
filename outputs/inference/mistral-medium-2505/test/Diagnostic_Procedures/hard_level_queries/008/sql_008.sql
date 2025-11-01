WITH
-- Get male patients aged 48-58 with UGIB diagnosis
ugib_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND d.icd_code IN (
      '531.00', '531.01', '531.20', '531.21', '531.40', '531.41', '531.60', '531.61',
      '532.00', '532.01', '532.20', '532.21', '532.40', '532.41', '532.60', '532.61',
      '533.00', '533.01', '533.20', '533.21', '533.40', '533.41', '533.60', '533.61',
      '534.00', '534.01', '534.20', '534.21', '534.40', '534.41', '534.60', '534.61',
      '578.0', '578.1', '578.9', 'K25.0', 'K25.2', 'K25.4', 'K25.6', 'K26.0', 'K26.2',
      'K26.4', 'K26.6', 'K27.0', 'K27.2', 'K27.4', 'K27.6', 'K28.0', 'K28.2', 'K28.4',
      'K28.6', 'K92.0', 'K92.1', 'K92.2'
    )
    AND d.icd_version IN (9, 10)
),

-- Get first ICU stay for each patient
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
    ugib_patients u ON s.subject_id = u.subject_id AND s.hadm_id = u.hadm_id
  WHERE
    s.intime IS NOT NULL
),

-- Get procedures in first 24 hours of ICU admission
early_procedures AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    COUNT(DISTINCT p.icd_code) AS procedure_count
  FROM
    first_icu_stays f
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON f.subject_id = p.subject_id AND f.hadm_id = p.hadm_id
  WHERE
    f.icu_stay_rank = 1
    AND p.chartdate BETWEEN f.icu_intime AND DATETIME_ADD(f.icu_intime, INTERVAL 24 HOUR)
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
    early_procedures
)

-- Final aggregation by quintile
SELECT
  q.quintile,
  AVG(q.procedure_count) AS avg_procedures,
  AVG(u.hospital_los) AS avg_hospital_los_days,
  AVG(CASE WHEN u.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100 AS in_hospital_mortality_pct,
  COUNT(*) AS patient_count
FROM
  quintiles q
JOIN
  ugib_patients u ON q.subject_id = u.subject_id AND q.hadm_id = u.hadm_id
GROUP BY
  q.quintile
ORDER BY
  q.quintile;