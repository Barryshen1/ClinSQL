WITH index_admissions AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.admission_type,
    adm.insurance,
    adm.admission_location,
    pat.dod,  -- Changed from adm.dod to pat.dod
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
    pat.gender,
    pat.anchor_age,
    diag.icd_code,
    diag.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 58 AND 68
    AND adm.insurance = 'Medicare'
    AND adm.admission_type = 'URGENT'  -- ED admissions typically marked as URGENT
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND diag.seq_num = 1  -- principal diagnosis
    AND diag.icd_version = 10
    AND diag.icd_code LIKE 'S72.0%'  -- femoral neck fracture codes
),

cohort AS (
  SELECT 
    ia.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` readm
        WHERE readm.subject_id = ia.subject_id
          AND readm.hadm_id != ia.hadm_id
          AND readm.admittime > ia.dischtime
          AND DATE_DIFF(readm.admittime, ia.dischtime, DAY) <= 30
      ) THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM index_admissions ia
),

readmitted_stats AS (
  SELECT 
    readmitted_30d,
    COUNT(*) AS n,
    APPROX_QUANTILE(los, 0.5) AS median_los
  FROM cohort
  GROUP BY readmitted_30d
),

overall_stats AS (
  SELECT 
    ROUND(100.0 * SUM(readmitted_30d) / COUNT(*), 2) AS readmission_rate_percent,
    ROUND(100.0 * SUM(CASE WHEN los > 8 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_los_gt_8
  FROM cohort
)

SELECT 
  readmission_rate_percent,
  (SELECT median_los FROM readmitted_stats WHERE readmitted_30d = 1) AS median_los_readmitted,
  (SELECT median_los FROM readmitted_stats WHERE readmitted_30d = 0) AS median_los_not_readmitted,
  percent_los_gt_8
FROM overall_stats;