WITH cohort AS (
  -- Base cohort: males 40-50 with HF admission
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.anchor_age BETWEEN 40 AND 50
    AND p.gender = 'M'
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
        ON d.icd_code = icd.icd_code 
        AND d.icd_version = icd.icd_version
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND ((d.icd_version = '10' AND d.icd_code LIKE 'I50%') 
             OR (d.icd_version = '9' AND d.icd_code LIKE '428%'))
    )
),

prescription_meds AS (
  -- Medications from prescriptions within 7 days
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    LOWER(TRIM(pr.drug)) AS med_name
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id
    AND c.hadm_id = pr.hadm_id
    AND pr.drug IS NOT NULL
    AND DATE(pr.starttime) >= DATE(c.admittime)
    AND DATE(pr.starttime) <= DATE_ADD(DATE(c.admittime), INTERVAL 7 DAY)
    AND (pr.stoptime IS NULL OR DATE(pr.stoptime) > DATE(c.admittime))
),

icu_meds AS (
  -- Medications from ICU inputevents within 7 days
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    LOWER(TRIM(di.label)) AS med_name
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON c.subject_id = ie.subject_id
    AND c.hadm_id = ie.hadm_id
    AND ie.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE category = 'Med Admin')
    AND DATE(ie.starttime) >= DATE(c.admittime)
    AND DATE(ie.starttime) <= DATE_ADD(DATE(c.admittime), INTERVAL 7 DAY)
    AND (ie.endtime IS NULL OR DATE(ie.endtime) > DATE(c.admittime))
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON CAST(ie.itemid AS STRING) = di.itemid
  WHERE di.label IS NOT NULL
),

med_complexity AS (
  -- Combine and deduplicate medications
  SELECT DISTINCT
    subject_id,
    hadm_id,
    admittime,
    med_name
  FROM (
    SELECT * FROM prescription_meds
    UNION ALL
    SELECT * FROM icu_meds
  )
  WHERE med_name IS NOT NULL
),

scores AS (
  -- Compute complexity score per admission
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    COUNT(DISTINCT med_name) AS unique_meds,
    COUNT(*) AS total_administrations,
    -- Score: unique meds + 0.5 per extra administration beyond 3 per med
    (COUNT(DISTINCT med_name) + 
     0.5 * GREATEST(0, COUNT(*) - 3 * COUNT(DISTINCT med_name))) AS complexity_score
  FROM med_complexity
  GROUP BY subject_id, hadm_id, admittime
  HAVING complexity_score > 0  -- Exclude no meds
),

outcomes AS (
  -- Add mortality and readmission
  SELECT 
    c.*,
    s.complexity_score,
    c.los_days,
    -- Mortality flag (0/1)
    CAST(c.hospital_expire_flag AS INT64) AS mortality_flag,
    -- 30-day readmission flag
    CASE 
      WHEN c.dischtime IS NULL THEN 0
      ELSE (
        SELECT CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = c.subject_id
          AND a2.hadm_id != c.hadm_id
          AND a2.admittime > c.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(CAST(c.dischtime AS TIMESTAMP), INTERVAL 30 DAY)
      )
    END AS readmission_flag
  FROM cohort c
  INNER JOIN scores s
    ON c.subject_id = s.subject_id 
    AND c.hadm_id = s.hadm_id
),

final AS (
  SELECT 
    quintile,
    COUNT(DISTINCT CONCAT(subject_id, '_', hadm_id)) AS patient_count,
    MIN(complexity_score) AS score_min,
    MAX(complexity_score) AS score_max,
    ROUND(AVG(los_days), 2) AS mean_los_days,
    ROUND(AVG(mortality_flag), 4) AS mortality_rate,
    ROUND(AVG(readmission_flag), 4) AS readmission_rate
  FROM (
    SELECT *,
      NTILE(5) OVER (ORDER BY complexity_score) AS quintile
    FROM outcomes
  )
  GROUP BY quintile
  ORDER BY quintile
)

SELECT * FROM final;