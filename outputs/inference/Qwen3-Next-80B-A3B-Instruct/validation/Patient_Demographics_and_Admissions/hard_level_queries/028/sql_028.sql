WITH index_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.insurance,
    p.anchor_age,
    p.gender,
    -- Calculate LOS in days
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM 
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'Emergency Room'
    AND d.seq_num = 1  -- principal diagnosis
    AND LOWER(did.long_title) LIKE '%cellulitis%'
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
          AND a2.admittime <= DATE_ADD(ia.dischtime, INTERVAL 30 DAY)
      ) THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM index_admissions ia
)

SELECT 
  -- 30-day readmission rate
  AVG(readmitted_30d) * 100 AS readmission_rate_30d_percent,

  -- Median LOS for readmitted vs non-readmitted
  PERCENTILE_CONT(CASE WHEN readmitted_30d = 1 THEN los_days END, 0.5) AS median_los_readmitted_days,
  PERCENTILE_CONT(CASE WHEN readmitted_30d = 0 THEN los_days END, 0.5) AS median_los_non_readmitted_days,

  -- Percent of index stays >7 days
  AVG(CASE WHEN los_days > 7 THEN 1.0 ELSE 0 END) * 100 AS percent_index_stays_gt_7_days

FROM readmission_flag;