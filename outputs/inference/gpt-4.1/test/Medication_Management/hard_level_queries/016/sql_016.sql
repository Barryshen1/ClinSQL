WITH hepatic_failure_icd AS (
  -- List of ICD codes for hepatic failure (ICD-9 and ICD-10)
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (
    -- ICD-10
    (icd_version = 10 AND (
      icd_code LIKE 'K72%' OR  -- Hepatic failure
      icd_code = 'K70.4' OR    -- Alcoholic hepatic failure
      icd_code = 'K71.1' OR    -- Toxic liver disease with hepatic necrosis
      icd_code = 'K76.6'       -- Portal hypertension
    ))
    OR
    -- ICD-9
    (icd_version = 9 AND (
      icd_code = '570' OR      -- Acute necrosis of liver
      icd_code = '5722' OR     -- Hepatic coma
      icd_code = '5723' OR     -- Portal hypertension
      icd_code = '5724'        -- Hepatorenal syndrome
    ))
  )
),
cohort AS (
  -- Female inpatients aged 80-90 with hepatic failure
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN hepatic_failure_icd hfi
    ON d.icd_code = hfi.icd_code AND d.icd_version = hfi.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
),
med_complexity AS (
  -- Calculate 7-day medication complexity score per admission
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT LOWER(e.medication)) AS med_complexity_score
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  WHERE
    e.charttime >= c.admittime
    AND e.charttime < DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
    AND e.medication IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id
),
cohort_with_complexity AS (
  -- Merge cohort and complexity, fill 0 if no meds
  SELECT
    c.*,
    COALESCE(m.med_complexity_score, 0) AS med_complexity_score
  FROM cohort c
  LEFT JOIN med_complexity m
    ON c.subject_id = m.subject_id AND c.hadm_id = m.hadm_id
),
tertile_assignment AS (
  -- Assign tertiles based on complexity score
  SELECT
    *,
    NTILE(3) OVER (ORDER BY med_complexity_score) AS complexity_tertile
  FROM cohort_with_complexity
),
los_and_readmit AS (
  -- Calculate LOS and 30-day readmission
  SELECT
    t.*,
    -- LOS in days
    SAFE_DIVIDE(TIMESTAMP_DIFF(t.dischtime, t.admittime, SECOND), 86400) AS los_days,
    -- 30-day readmission: does subject have another admission within 30 days after discharge?
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE
          a2.subject_id = t.subject_id
          AND a2.admittime > t.dischtime
          AND a2.admittime <= DATETIME_ADD(t.dischtime, INTERVAL 30 DAY)
      ) THEN 1 ELSE 0
    END AS readmit_30d
  FROM tertile_assignment t
)
SELECT
  complexity_tertile,
  COUNT(*) AS n_patients,
  ROUND(AVG(los_days),2) AS avg_los_days,
  ROUND(APPROX_QUANTILES(los_days, 2)[OFFSET(1)],2) AS median_los_days,
  ROUND(AVG(hospital_expire_flag)*100,1) AS in_hospital_mortality_rate_pct,
  ROUND(AVG(readmit_30d)*100,1) AS readmission_30d_rate_pct
FROM los_and_readmit
GROUP BY complexity_tertile
ORDER BY complexity_tertile;