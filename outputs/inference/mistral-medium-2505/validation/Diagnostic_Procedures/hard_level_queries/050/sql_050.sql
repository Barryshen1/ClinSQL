WITH
-- Get male patients aged 76-86
eligible_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 76 AND 86
),

-- Get admissions with AMI diagnosis
ami_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM eligible_patients)
    AND (
      -- ICD-10 codes for AMI
      (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
      OR
      -- ICD-9 codes for AMI
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
    )
),

-- Get first ICU stay per admission
first_icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id, i.hadm_id ORDER BY i.intime) as icu_seq
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    ami_admissions a
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  WHERE
    i.intime IS NOT NULL
    AND i.outtime IS NOT NULL
),

-- Get distinct procedures in first 24 hours of ICU stay
icu_procedures AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    COUNT(DISTINCT p.icd_code) AS distinct_procedures
  FROM
    first_icu_stays f
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON f.subject_id = p.subject_id AND f.hadm_id = p.hadm_id
    AND p.chartdate BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 24 HOUR)
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON f.subject_id = pe.subject_id AND f.hadm_id = pe.hadm_id AND f.stay_id = pe.stay_id
    AND pe.starttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 24 HOUR)
  WHERE
    f.icu_seq = 1  -- Only first ICU stay per admission
  GROUP BY
    f.subject_id, f.hadm_id, f.stay_id
),

-- Add quartile information
procedure_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY distinct_procedures) AS procedure_quartile
  FROM
    icu_procedures
)

-- Final aggregation by quartile
SELECT
  procedure_quartile,
  AVG(distinct_procedures) AS mean_procedure_count,
  AVG(los) AS mean_icu_los,
  SUM(hospital_expire_flag) * 100.0 / COUNT(*) AS hospital_mortality_percentage
FROM
  procedure_quartiles q
JOIN
  first_icu_stays f
  ON q.subject_id = f.subject_id AND q.hadm_id = f.hadm_id AND q.stay_id = f.stay_id
JOIN
  ami_admissions a
  ON q.subject_id = a.subject_id AND q.hadm_id = a.hadm_id
WHERE
  f.icu_seq = 1  -- Only first ICU stay per admission
GROUP BY
  procedure_quartile
ORDER BY
  procedure_quartile;