WITH patient_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.insurance,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    a.dischtime IS NOT NULL
),

index_admissions AS (
  SELECT 
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.los_days
  FROM 
    patient_admissions pa
  WHERE 
    pa.gender = 'M'
    AND pa.insurance = 'Medicare'
    AND pa.admission_location = 'EMERGENCY ROOM'
    AND pa.hospital_expire_flag = 0
    AND pa.age_at_admission BETWEEN 65 AND 75
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.subject_id = pa.subject_id
        AND d.hadm_id = pa.hadm_id
        AND d.seq_num = 1
        AND (
          (d.icd_version = 9 AND d.icd_code = '518.81')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'J96%')
        )
    )
),

index_with_readmission AS (
  SELECT 
    ia.*,
    CASE 
      WHEN COUNT(read_adm.hadm_id) > 0 THEN 1 
      ELSE 0 
    END AS readmitted_flag
  FROM 
    index_admissions ia
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` read_adm
    ON ia.subject_id = read_adm.subject_id
    AND read_adm.hadm_id != ia.hadm_id
    AND read_adm.admittime > ia.dischtime
    AND read_adm.admittime <= TIMESTAMP_ADD(ia.dischtime, INTERVAL 30 DAY)
  GROUP BY 
    ia.subject_id, ia.hadm_id, ia.admittime, ia.dischtime, ia.los_days
),

overall_stats AS (
  SELECT 
    COUNT(*) AS total_index,
    COUNTIF(readmitted_flag = 1) AS num_readmitted,
    COUNTIF(los_days > 9) AS num_long_los
  FROM 
    index_with_readmission
),

median_readmitted AS (
  SELECT 
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_readmitted
  FROM 
    index_with_readmission
  WHERE 
    readmitted_flag = 1
),

median_non_readmitted AS (
  SELECT 
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_non_readmitted
  FROM 
    index_with_readmission
  WHERE 
    readmitted_flag = 0
)

SELECT 
  (os.num_readmitted * 100.0 / os.total_index) AS readmission_rate_pct,
  mr.median_los_readmitted,
  mn.median_los_non_readmitted,
  (os.num_long_los * 100.0 / os.total_index) AS percent_los_gt9
FROM 
  overall_stats os
CROSS JOIN 
  median_readmitted mr
CROSS JOIN 
  median_non_readmitted mn;