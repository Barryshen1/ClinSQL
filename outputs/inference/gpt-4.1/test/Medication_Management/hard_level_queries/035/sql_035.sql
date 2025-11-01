WITH female_40_50 AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
),

neutropenic_fever_admissions AS (
  -- Find admissions with BOTH neutropenia and fever ICD codes
  SELECT
    f.subject_id,
    f.hadm_id,
    f.admittime,
    f.dischtime,
    f.hospital_expire_flag
  FROM
    female_40_50 f
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
      ON f.hadm_id = d1.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      ON f.hadm_id = d2.hadm_id
  WHERE
    (
      (d1.icd_code LIKE 'D70%' AND d1.icd_version = 10) -- Neutropenia ICD-10
      OR (d1.icd_code LIKE '2880%' AND d1.icd_version = 9) -- Neutropenia ICD-9
    )
    AND (
      (d2.icd_code LIKE 'R50%' AND d2.icd_version = 10) -- Fever ICD-10
      OR (d2.icd_code LIKE '7806%' AND d2.icd_version = 9) -- Fever ICD-9
    )
),

med_complexity AS (
  -- For each admission, count unique drugs in first 48h
  SELECT
    nfa.subject_id,
    nfa.hadm_id,
    nfa.admittime,
    nfa.dischtime,
    nfa.hospital_expire_flag,
    COUNT(DISTINCT LOWER(pr.drug)) AS complexity_score
  FROM
    neutropenic_fever_admissions nfa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON nfa.hadm_id = pr.hadm_id
      AND pr.starttime >= nfa.admittime
      AND pr.starttime < DATETIME_ADD(nfa.admittime, INTERVAL 48 HOUR)
  GROUP BY
    nfa.subject_id, nfa.hadm_id, nfa.admittime, nfa.dischtime, nfa.hospital_expire_flag
),

quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY complexity_score) AS complexity_quartile,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los
  FROM
    med_complexity
),

readmissions AS (
  -- For each admission, find if patient has another admission within 30 days after discharge
  SELECT
    q.subject_id,
    q.hadm_id,
    MIN(a2.admittime) AS next_admit_time
  FROM
    quartiles q
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
      ON q.subject_id = a2.subject_id
      AND a2.admittime > q.dischtime
      AND DATETIME_DIFF(a2.admittime, q.dischtime, DAY) <= 30
  GROUP BY
    q.subject_id, q.hadm_id
),

final AS (
  SELECT
    q.complexity_quartile,
    COUNT(*) AS admission_count,
    COUNT(DISTINCT q.subject_id) AS patient_count,
    AVG(q.complexity_score) AS mean_score,
    MIN(q.complexity_score) AS min_score,
    MAX(q.complexity_score) AS max_score,
    AVG(q.los) AS mean_los,
    100.0 * SUM(CASE WHEN q.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_percent,
    100.0 * SUM(CASE WHEN r.next_admit_time IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS readmission_30d_percent
  FROM
    quartiles q
    LEFT JOIN readmissions r
      ON q.hadm_id = r.hadm_id
  GROUP BY
    q.complexity_quartile
  ORDER BY
    q.complexity_quartile
)

SELECT
  complexity_quartile,
  patient_count,
  mean_score,
  min_score,
  max_score,
  mean_los,
  mortality_percent,
  readmission_30d_percent
FROM
  final
ORDER BY
  complexity_quartile;