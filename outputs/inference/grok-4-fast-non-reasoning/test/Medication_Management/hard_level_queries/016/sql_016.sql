WITH cohort AS (
  -- Base cohort: females 80-90 with primary hepatic failure diagnosis
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime DESC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND d.seq_num = 1  -- Fixed: integer comparison (removed quotes)
    AND (
      -- ICD-10 hepatic failure codes
      (d.icd_version = '10' AND d.icd_code LIKE 'K7[0-4]%') OR
      -- ICD-9 equivalents (e.g., 570, 572.0, 572.2-572.8, 573.3; simplified pattern for liver failure/cirrhosis)
      (d.icd_version = '9' AND d.icd_code IN ('570', '5720', '5722', '5723', '5724', '5728', '5733'))
    )
    AND a.dischtime IS NOT NULL
    AND a.hospital_expire_flag IS NOT NULL
),

med_scores AS (
  -- 7-day medication complexity score (distinct drug count in first 7 days)
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.rn,
    COUNT(DISTINCT pres.drug) AS med_complexity_score
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON c.subject_id = pres.subject_id AND c.hadm_id = pres.hadm_id
  WHERE pres.drug IS NOT NULL 
    AND pres.drug != ''
    AND pres.starttime <= DATE_ADD(c.admittime, INTERVAL 7 DAY)
    AND (pres.stoptime >= c.admittime OR pres.stoptime IS NULL)
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag, c.rn
),

all_adms AS (
  -- All admissions for readmission calculation
  SELECT subject_id, hadm_id, admittime, dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE dischtime IS NOT NULL
),

final_cohort AS (
  SELECT 
    m.*,
    -- Flag 30-day readmission: 1 if any admission within 30 days of discharge
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM all_adms ra
        WHERE m.subject_id = ra.subject_id
          AND ra.hadm_id != m.hadm_id
          AND ra.admittime > m.dischtime
          AND ra.admittime <= DATE_ADD(m.dischtime, INTERVAL 30 DAY)
      ) THEN 1 ELSE 0 
    END AS has_readmit_30d,
    NTILE(3) OVER (ORDER BY m.med_complexity_score) AS complexity_tertile
  FROM med_scores m
)

-- Aggregate by tertile (latest admission per patient)
SELECT 
  complexity_tertile,
  COUNT(*) AS n_patients,
  ROUND(AVG(DATE_DIFF(dischtime, admittime, DAY)), 2) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_rate_pct,
  ROUND(AVG(has_readmit_30d) * 100, 2) AS readmission_30d_rate_pct,
  ROUND(AVG(med_complexity_score), 2) AS mean_med_score
FROM final_cohort
WHERE rn = 1
GROUP BY complexity_tertile
ORDER BY complexity_tertile;