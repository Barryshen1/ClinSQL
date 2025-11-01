WITH hemorrhagic_stroke_admissions AS (
  -- Select male patients aged 61-71 with hemorrhagic stroke
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON diag.icd_code = dicd.icd_code AND diag.icd_version = dicd.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 61 AND 71
    AND (
      -- ICD-10: I60.x, I61.x, I62.x
      (diag.icd_version = 10 AND (
        diag.icd_code LIKE 'I60%' OR
        diag.icd_code LIKE 'I61%' OR
        diag.icd_code LIKE 'I62%'
      ))
      -- ICD-9: 430, 431, 432
      OR (diag.icd_version = 9 AND (
        diag.icd_code IN ('430', '431', '432')
      ))
    )
),
med_complexity AS (
  -- Calculate medication complexity score for first 24h of admission
  SELECT
    hsa.subject_id,
    hsa.hadm_id,
    COUNT(DISTINCT emar.medication) AS complexity_score
  FROM
    hemorrhagic_stroke_admissions hsa
    JOIN `physionet-data.mimiciv_3_1_hosp.emar` emar
      ON hsa.subject_id = emar.subject_id AND hsa.hadm_id = emar.hadm_id
  WHERE
    emar.charttime >= hsa.admittime
    AND emar.charttime < DATETIME_ADD(hsa.admittime, INTERVAL 24 HOUR)
  GROUP BY
    hsa.subject_id, hsa.hadm_id
),
admission_with_complexity AS (
  -- Combine admissions and complexity score
  SELECT
    hsa.subject_id,
    hsa.hadm_id,
    hsa.admittime,
    hsa.dischtime,
    hsa.hospital_expire_flag,
    IFNULL(mc.complexity_score, 0) AS complexity_score
  FROM
    hemorrhagic_stroke_admissions hsa
    LEFT JOIN med_complexity mc
      ON hsa.subject_id = mc.subject_id AND hsa.hadm_id = mc.hadm_id
),
quintiles AS (
  -- Assign quintiles based on complexity score
  SELECT
    *,
    NTILE(5) OVER (ORDER BY complexity_score) AS quintile
  FROM
    admission_with_complexity
),
los_and_readmission AS (
  -- Calculate LOS and 30-day readmission flag
  SELECT
    q.*,
    -- LOS in days
    SAFE_DIVIDE(TIMESTAMP_DIFF(q.dischtime, q.admittime, SECOND), 86400) AS los_days,
    -- 30-day readmission flag
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm2
        WHERE
          adm2.subject_id = q.subject_id
          AND adm2.admittime > q.dischtime
          AND adm2.admittime <= DATETIME_ADD(q.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmit_30d
  FROM
    quintiles q
  WHERE
    q.dischtime IS NOT NULL
    AND q.admittime IS NOT NULL
)
SELECT
  quintile,
  COUNT(DISTINCT subject_id) AS num_patients,
  ROUND(AVG(complexity_score),2) AS mean_complexity_score,
  ROUND(AVG(los_days),2) AS avg_los_days,
  ROUND(AVG(hospital_expire_flag),3) AS in_hospital_mortality_rate,
  ROUND(AVG(readmit_30d),3) AS readmission_30d_rate
FROM
  los_and_readmission
GROUP BY
  quintile
ORDER BY
  quintile;