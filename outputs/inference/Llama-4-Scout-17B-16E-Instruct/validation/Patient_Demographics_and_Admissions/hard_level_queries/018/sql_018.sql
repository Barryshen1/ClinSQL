WITH 
-- Identify target population
target_population AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    p.anchor_age,
    p.gender,
    a.admission_type,
    a.admission_location,
    a.dischtime,
    a.hospital_expire_flag,
    a.admittime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND a.admission_type = 'Emergency'
    AND a.admission_location = 'ED'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
      AND d.seq_num = 1
      AND d.icd_code LIKE '820%'
    )
),

-- Identify readmissions
readmissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    LAG(a.dischtime) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS prev_dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
),

-- Flag readmitted patients
readmitted_patients AS (
  SELECT 
    tp.hadm_id,
    tp.subject_id,
    tp.dischtime,
    tp.admittime,
    tp.los,
    CASE 
      WHEN 
        EXISTS (
          SELECT 1
          FROM readmissions r
          WHERE 
            r.prev_dischtime BETWEEN tp.dischtime AND TIMESTAMP_ADD(tp.dischtime, INTERVAL 30 DAY)
            AND r.hadm_id != tp.hadm_id
        ) 
      THEN 1 
      ELSE 0 
    END AS readmitted
  FROM 
    target_population tp
)

-- Calculate LOS, readmission rate, and percent of stays > 8 days
SELECT 
  COUNT(DISTINCT CASE WHEN rp.readmitted = 1 THEN rp.hadm_id END) AS readmitted_count,
  COUNT(DISTINCT CASE WHEN rp.readmitted = 0 THEN rp.hadm_id END) AS non_readmitted_count,
  APPROX_QUANTILES(CASE WHEN rp.readmitted = 1 THEN rp.los END, 1000)[500] AS median_LOS_readmitted,
  APPROX_QUANTILES(CASE WHEN rp.readmitted = 0 THEN rp.los END, 1000)[500] AS median_LOS_non_readmitted,
  COUNT(DISTINCT CASE WHEN rp.los > 8 THEN rp.hadm_id END) * 100.0 / COUNT(DISTINCT rp.hadm_id) AS percent_stays_over_8_days
FROM 
  readmitted_patients rp;