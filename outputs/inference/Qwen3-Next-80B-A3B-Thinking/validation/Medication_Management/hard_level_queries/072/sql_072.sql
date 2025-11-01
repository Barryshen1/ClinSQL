WITH cohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
    ON a.hadm_id = d_icd.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON d_icd.icd_code = d.icd_code AND d_icd.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND d.long_title LIKE '%ketoacidosis%'
),
medications AS (
  SELECT
    p.hadm_id,
    p.starttime,
    p.drug,
    CASE
      WHEN p.drug LIKE '%lisinopril%' OR
           p.drug LIKE '%enalapril%' OR
           p.drug LIKE '%ramipril%' OR
           p.drug LIKE '%losartan%' OR
           p.drug LIKE '%valsartan%' OR
           p.drug LIKE '%spironolactone%' OR
           p.drug LIKE '%eplerenone%' OR
           p.drug LIKE '%triamterene%' OR
           p.drug LIKE '%ibuprofen%' OR
           p.drug LIKE '%naproxen%' OR
           p.drug LIKE '%trimethoprim%' OR
           p.drug LIKE '%potassium%' OR
           p.drug LIKE '%chloride%' OR
           p.drug LIKE '%supplement%' THEN 1
      ELSE 0
    END AS is_hyperkalemia_risk
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN cohort c
    ON p.hadm_id = c.hadm_id
  WHERE
    p.starttime >= c.admittime
    AND p.starttime <= c.admittime + INTERVAL '48' HOUR
),
patient_meds AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COUNT(m.drug) AS med_count,
    MAX(m.is_hyperkalemia_risk) AS has_hyperkalemia_risk
  FROM cohort c
  LEFT JOIN medications m
    ON c.hadm_id = m.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),
quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY med_count) AS complexity_quartile
  FROM patient_meds
)
SELECT
  'with_hyperkalemia_risk' AS group_type,
  AVG(med_count) AS mean_med_complexity,
  PERCENTILE_CONT(med_count, 0.5) AS median_med_complexity,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS mean_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM patient_meds
WHERE has_hyperkalemia_risk = 1

UNION ALL

SELECT
  'without_hyperkalemia_risk' AS group_type,
  AVG(med_count) AS mean_med_complexity,
  PERCENTILE_CONT(med_count, 0.5) AS median_med_complexity,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS mean_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM patient_meds
WHERE has_hyperkalemia_risk = 0

UNION ALL

SELECT
  'top_complexity_quartile' AS group_type,
  NULL AS mean_med_complexity,
  NULL AS median_med_complexity,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS mean_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM quartiles
WHERE complexity_quartile = 4;