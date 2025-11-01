WITH eligible_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    adm.deathtime,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
aki_admissions AS (
  SELECT 
    ea.subject_id, 
    ea.hadm_id, 
    ea.admittime, 
    ea.dischtime,
    -- Calculate age at admission
    ea.anchor_age + (EXTRACT(YEAR FROM ea.admittime) - ea.anchor_year) AS age_at_admission
  FROM eligible_admissions ea
  WHERE 
    -- Age 52-62 at admission
    ea.anchor_age + (EXTRACT(YEAR FROM ea.admittime) - ea.anchor_year) BETWEEN 52 AND 62
    -- AKI diagnosis (ICD-9: 584.x, ICD-10: N17.x)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.hadm_id = ea.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '584%') OR
          (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%')
        )
    )
    -- Exclude in-hospital deaths
    AND ea.deathtime IS NULL
),
with_next_admission AS (
  SELECT 
    aa.*,
    LEAD(admittime) OVER (
      PARTITION BY aa.subject_id 
      ORDER BY aa.admittime
    ) AS next_admittime
  FROM aki_admissions aa
),
readmission_flags AS (
  SELECT 
    hadm_id,
    -- Readmission within 30 days of discharge
    CASE 
      WHEN next_admittime IS NOT NULL 
        AND next_admittime <= TIMESTAMP_ADD(dischtime, INTERVAL 30 DAY) 
        THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM with_next_admission
)
-- Calculate standard deviation of readmission indicator
SELECT 
  STDDEV_POP(readmitted_30d) AS std_dev_30d_readmission
FROM readmission_flags;