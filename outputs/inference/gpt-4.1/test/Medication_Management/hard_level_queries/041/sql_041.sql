WITH hf_admissions AS (
  -- Step 1: Cohort selection
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND (
      -- Heart failure ICD-10: I50.x, ICD-9: 428.x
      (d.icd_version = 9 AND d.icd_code LIKE '428%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
complexity_score AS (
  -- Step 2: Medication complexity score in first 7 days
  SELECT
    h.subject_id,
    h.hadm_id,
    h.admittime,
    h.dischtime,
    h.hospital_expire_flag,
    h.anchor_age,
    COUNT(DISTINCT pr.drug) AS med_complexity_score
  FROM
    hf_admissions h
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON h.hadm_id = pr.hadm_id
      AND pr.starttime >= h.admittime
      AND pr.starttime < DATETIME_ADD(h.admittime, INTERVAL 7 DAY)
      AND pr.drug IS NOT NULL
  GROUP BY
    h.subject_id, h.hadm_id, h.admittime, h.dischtime, h.hospital_expire_flag, h.anchor_age
),
quintiles AS (
  -- Step 3: Assign quintiles based on complexity score
  SELECT
    *,
    NTILE(5) OVER (ORDER BY med_complexity_score) AS complexity_quintile
  FROM
    complexity_score
),
readmissions AS (
  -- Step 4: 30-day readmission flag
  SELECT
    q.subject_id,
    q.hadm_id,
    q.admittime,
    q.dischtime,
    q.complexity_quintile,
    MIN(a2.admittime) AS next_admit_time,
    CASE
      WHEN MIN(a2.admittime) IS NOT NULL
        AND TIMESTAMP_DIFF(MIN(a2.admittime), q.dischtime, DAY) <= 30
        AND TIMESTAMP_DIFF(MIN(a2.admittime), q.dischtime, DAY) > 0
      THEN 1 ELSE 0
    END AS readmit_30d
  FROM
    quintiles q
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
      ON q.subject_id = a2.subject_id
      AND a2.admittime > q.dischtime
  GROUP BY
    q.subject_id, q.hadm_id, q.admittime, q.dischtime, q.complexity_quintile
),
final AS (
  -- Step 5: Combine all metrics
  SELECT
    q.complexity_quintile,
    COUNT(DISTINCT q.subject_id) AS patient_count,
    COUNT(*) AS admission_count,
    MIN(q.med_complexity_score) AS score_min,
    MAX(q.med_complexity_score) AS score_max,
    ROUND(AVG(TIMESTAMP_DIFF(q.dischtime, q.admittime, DAY)),2) AS mean_los_days,
    ROUND(AVG(CAST(q.hospital_expire_flag AS FLOAT64)),4) AS in_hosp_mortality_rate,
    ROUND(AVG(r.readmit_30d),4) AS readmit_30d_rate
  FROM
    quintiles q
    LEFT JOIN readmissions r
      ON q.hadm_id = r.hadm_id
  GROUP BY
    q.complexity_quintile
  ORDER BY
    q.complexity_quintile
)

SELECT
  complexity_quintile AS quintile,
  patient_count,
  admission_count,
  score_min,
  score_max,
  mean_los_days,
  in_hosp_mortality_rate,
  readmit_30d_rate
FROM
  final
ORDER BY
  quintile;