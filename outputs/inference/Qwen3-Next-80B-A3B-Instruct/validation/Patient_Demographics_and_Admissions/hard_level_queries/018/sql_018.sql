WITH index_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS index_los,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'Emergency Room'
    AND d.seq_num = 1
    AND (
      d_icd.long_title LIKE '%femoral neck fracture%'
      OR d_icd.long_title LIKE '%fracture of neck of femur%'
      OR d_icd.icd_code LIKE '820%' -- ICD-9
      OR d_icd.icd_code LIKE 'S72.0%' -- ICD-10
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
readmission_flag AS (
  SELECT 
    ia.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM physionet-data.mimiciv_3_1_hosp.admissions a2 
        WHERE a2.subject_id = ia.subject_id 
          AND a2.hadm_id != ia.hadm_id 
          AND a2.admittime > ia.dischtime 
          AND a2.admittime <= DATETIME_ADD(ia.dischtime, INTERVAL 30 DAY)
      ) THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM index_admissions ia
  WHERE rn = 1
)
SELECT 
  SUM(readmitted_30d) * 1.0 / COUNT(*) AS readmission_rate_30d,
  PERCENTILE_DISC(CASE WHEN readmitted_30d = 1 THEN index_los END, 0.5) AS median_los_readmitted,
  PERCENTILE_DISC(CASE WHEN readmitted_30d = 0 THEN index_los END, 0.5) AS median_los_non_readmitted,
  SUM(CASE WHEN index_los > 8 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percent_index_stay_gt_8_days
FROM readmission_flag;