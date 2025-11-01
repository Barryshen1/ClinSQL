WITH acute_pancreatitis_admissions AS (
  -- Identify admissions for female patients aged 71-81 with acute pancreatitis
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions adm
    INNER JOIN physionet-data.mimiciv_3_1_hosp.patients pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
      ON adm.hadm_id = diag.hadm_id
    INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
      ON diag.icd_code = dicd.icd_code AND diag.icd_version = dicd.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 71 AND 81
    AND (
      -- ICD-10 K85.x or ICD-9 577.0
      (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
      OR (diag.icd_version = 9 AND diag.icd_code = '5770')
    )
),

med_complexity AS (
  -- Count unique medications prescribed in first 72h of admission
  SELECT
    apa.subject_id,
    apa.hadm_id,
    COUNT(DISTINCT LOWER(TRIM(pres.drug))) AS med_complexity
  FROM
    acute_pancreatitis_admissions apa
    INNER JOIN physionet-data.mimiciv_3_1_hosp.prescriptions pres
      ON apa.hadm_id = pres.hadm_id
      AND pres.starttime >= apa.admittime
      AND pres.starttime < TIMESTAMP_ADD(apa.admittime, INTERVAL 72 HOUR)
  GROUP BY
    apa.subject_id,
    apa.hadm_id
),

index_admissions AS (
  -- Combine admissions and complexity, assign tertiles
  SELECT
    apa.subject_id,
    apa.hadm_id,
    apa.admittime,
    apa.dischtime,
    apa.hospital_expire_flag,
    COALESCE(mc.med_complexity, 0) AS med_complexity
  FROM
    acute_pancreatitis_admissions apa
    LEFT JOIN med_complexity mc
      ON apa.subject_id = mc.subject_id AND apa.hadm_id = mc.hadm_id
),

tertile_assignment AS (
  -- Assign tertiles based on medication complexity
  SELECT
    *,
    NTILE(3) OVER (ORDER BY med_complexity) AS complexity_tertile
  FROM
    index_admissions
),

los_and_outcomes AS (
  -- Calculate LOS, in-hospital mortality, and 30-day readmission
  SELECT
    ta.*,
    -- LOS in days
    SAFE_DIVIDE(TIMESTAMP_DIFF(ta.dischtime, ta.admittime, SECOND), 86400) AS los_days,
    -- In-hospital mortality
    CAST(ta.hospital_expire_flag AS INT64) AS in_hosp_mortality,
    -- 30-day readmission: does another admission for same subject start within 30 days after discharge?
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM physionet-data.mimiciv_3_1_hosp.admissions adm2
        WHERE adm2.subject_id = ta.subject_id
          AND adm2.admittime > ta.dischtime
          AND adm2.admittime <= TIMESTAMP_ADD(ta.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmit_30d
  FROM
    tertile_assignment ta
)

SELECT
  complexity_tertile,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days),2) AS avg_los_days,
  ROUND(APPROX_QUANTILES(los_days, 2)[OFFSET(1)],2) AS median_los_days,
  ROUND(AVG(in_hosp_mortality)*100,1) AS in_hosp_mortality_pct,
  ROUND(AVG(readmit_30d)*100,1) AS readmit_30d_pct
FROM
  los_and_outcomes
GROUP BY
  complexity_tertile
ORDER BY
  complexity_tertile;