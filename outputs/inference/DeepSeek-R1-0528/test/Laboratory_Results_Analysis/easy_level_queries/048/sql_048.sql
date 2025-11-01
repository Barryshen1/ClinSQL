WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    -- COPD diagnosis (ICD-9: 490-496; ICD-10: J40-J44, J47)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE
        di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^(490|491|492|494|495|496)'))
          OR
          (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^(J40|J41|J42|J43|J44|J47)'))
        )
    )
),
-- Filter for adults (age >=18) and get creatinine in first 24h
creatinine_24h AS (
  SELECT
    c.hadm_id,
    le.valuenum AS creatinine
  FROM
    cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON c.subject_id = le.subject_id
      AND c.hadm_id = le.hadm_id
  WHERE
    c.age >= 18
    AND le.itemid = 50912  -- Serum creatinine
    AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
    AND le.valuenum IS NOT NULL  -- Ensure numeric value
),
-- Average creatinine per admission
avg_creatinine AS (
  SELECT
    hadm_id,
    AVG(creatinine) AS avg_creat
  FROM
    creatinine_24h
  GROUP BY
    hadm_id
)
-- Calculate 75th percentile of averages
SELECT
  APPROX_QUANTILES(avg_creat, 100)[OFFSET(75)] AS percentile_75_creatinine
FROM
  avg_creatinine;